import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { performance } from 'node:perf_hooks';
import { ApiError, fail } from './errors.js';

const now = () => new Date().toISOString();
const retryable = new Set([408, 429, 500, 502, 503, 504]);

export class Monitor {
  constructor(store, logger, c) {
    this.store = store;
    this.logger = logger;
    this.c = c;
    this.enabled = false;
    this.jobs = new Set();
    this.due = new Map();
    this.lastError = null;
    this.stopping = false;
    this.failNextFinalization = false; // Test harness only; never exposed as an API route.
    const old = store.get("SELECT value FROM settings WHERE key='scheduler_enabled'")?.value;
    const interrupted = store.all("SELECT * FROM runs WHERE state='RUNNING'");
    store.transaction(() => {
      store.run("INSERT OR REPLACE INTO settings(key,value) VALUES('scheduler_enabled','false')");
      for (const run of interrupted) {
        store.run("UPDATE runs SET state='INTERRUPTED',finished_at=?,interruption_reason='process_restart' WHERE id=?", now(), run.id);
        store.run("UPDATE endpoints SET status='UNKNOWN',next_due_at=NULL WHERE id=?", run.endpoint_id);
      }
      if (c.seed && !store.get('SELECT id FROM endpoints LIMIT 1')) {
        for (const [name, service, behavior] of [['Library API', 'library', 'stable'], ['Enrollment API', 'enroll', 'flaky'], ['Payments sandbox', 'pay', 'dead']]) {
          store.run('INSERT INTO endpoints(name,url,interval_seconds,demo_behavior,created_at) VALUES(?,?,60,?,?)', name, `https://api.sandbox.example/${service}/health`, behavior, now());
        }
      }
    });
    logger.emit('process_started', { previous_scheduler_enabled: old === 'true', scheduler_enabled: false, max_attempts: c.maxAttempts, timeout_ms: c.timeoutMs, retry_delay_ms: c.retryDelayMs, concurrency: c.concurrency });
    for (const run of interrupted) logger.emit('run_interrupted', { check_id: run.id, endpoint_id: run.endpoint_id, correlation_id: run.correlation_id, reason: 'process_restart' });
    this.lastWall = Date.now();
    this.lastMono = performance.now();
    this.timer = setInterval(() => this.tick(), c.tickMs);
    this.timer.unref();
  }

  log(event, fields) {
    try { return this.logger.emit(event, fields); }
    catch (error) { this.enabled = false; this.lastError = 'LOG_UNAVAILABLE'; throw error; }
  }

  endpoint(id) {
    const endpoint = this.store.get('SELECT * FROM endpoints WHERE id=?', id);
    if (!endpoint) fail(404, 'NOT_FOUND', 'Endpoint not found.');
    const active = this.store.get("SELECT id FROM runs WHERE endpoint_id=? AND state='RUNNING'", id);
    const incident = this.store.get("SELECT id FROM incidents WHERE endpoint_id=? AND state IN ('OPEN','ACKNOWLEDGED')", id);
    return { ...endpoint, checking: !!active, active_check_id: active?.id ?? null, active_incident_id: incident?.id ?? null,
      recent_runs: this.store.all('SELECT id,state,started_at,finished_at,interruption_reason FROM runs WHERE endpoint_id=? ORDER BY id DESC LIMIT 10', id) };
  }
  endpoints() { return this.store.all('SELECT id FROM endpoints ORDER BY id').map(row => this.endpoint(row.id)); }
  runView(id) {
    const run = this.store.get('SELECT * FROM runs WHERE id=?', id);
    if (!run) fail(404, 'NOT_FOUND', 'Check run not found.');
    const result = this.store.get('SELECT * FROM results WHERE check_id=?', id);
    const incident = this.store.get('SELECT id FROM incidents WHERE opening_check_id=? OR recovery_check_id=? ORDER BY id DESC LIMIT 1', id, id);
    return { ...run, attempts: this.store.all('SELECT * FROM attempts WHERE check_id=? ORDER BY ordinal', id), result: result ? { ...result, ok: !!result.ok } : null, incident_id: incident?.id ?? null };
  }
  results(id, limit) {
    this.endpoint(id);
    return this.store.all('SELECT * FROM results WHERE endpoint_id=? ORDER BY id DESC LIMIT ?', id, limit).map(row => ({ ...row, ok: !!row.ok }));
  }
  scheduler() {
    return { enabled: this.enabled, tick_ms: this.c.tickMs, capacity: this.c.concurrency, active_count: this.store.get("SELECT COUNT(*) AS n FROM runs WHERE state='RUNNING'").n, last_error: this.lastError };
  }
  register(input, correlation) {
    if (this.store.get('SELECT id FROM endpoints WHERE url=?', input.url)) fail(409, 'DUPLICATE_ENDPOINT', 'This URL is already registered.', { url: 'This URL is already registered.' });
    const id = Number(this.store.run('INSERT INTO endpoints(name,url,interval_seconds,demo_behavior,created_at,next_due_at) VALUES(?,?,?,?,?,?)', input.name, input.url, input.interval_seconds, input.demo_behavior, now(), this.enabled ? now() : null).lastInsertRowid);
    return { status: 201, data: this.endpoint(id), location: `/api/v1/endpoints/${id}`, after: () => {
      if (this.enabled) this.due.set(id, performance.now());
      this.log('endpoint_registered', { source: 'api', endpoint_id: id, correlation_id: correlation });
    } };
  }
  reserve(endpointId, trigger, correlation, parent = null, scheduleKey = null) {
    const ep = this.endpoint(endpointId);
    if (ep.checking) fail(409, 'CHECK_IN_PROGRESS', `A check is already running (run ${ep.active_check_id}).`, { active_check_id: ep.active_check_id });
    if (this.store.get("SELECT COUNT(*) AS n FROM runs WHERE state='RUNNING'").n >= this.c.concurrency) fail(503, 'CAPACITY_BUSY', 'Two check slots are busy. Retry after a run completes.');
    if (this.stopping || this.logger.failed || this.lastError) fail(503, 'AUTOMATION_PAUSED', 'Automation is paused. Ask the maintainer to inspect local logs.');
    const id = Number(this.store.run("INSERT INTO runs(endpoint_id,trigger,state,correlation_id,parent_correlation_id,schedule_key,behavior,started_at) VALUES(?,?,'RUNNING',?,?,?,?,?)", endpointId, trigger, correlation, parent, scheduleKey, ep.demo_behavior, now()).lastInsertRowid);
    this.store.run('UPDATE endpoints SET next_due_at=NULL WHERE id=?', endpointId);
    return { id, endpoint_id: endpointId, state: 'RUNNING', correlation_id: correlation, status_url: `/api/v1/checks/${id}` };
  }
  trigger(id, correlation) {
    const run = this.reserve(id, 'manual', correlation);
    return { status: 202, data: run, after: () => this.launch(run.id) };
  }
  runAll(parentCorrelation) {
    const outcomes = [];
    for (const { id } of this.store.all('SELECT id FROM endpoints ORDER BY id')) {
      try { outcomes.push({ endpoint_id: id, outcome: 'accepted', run: this.reserve(id, 'run_all', randomUUID(), parentCorrelation) }); }
      catch (error) {
        if (error instanceof ApiError && ['CHECK_IN_PROGRESS', 'CAPACITY_BUSY'].includes(error.code)) outcomes.push({ endpoint_id: id, outcome: error.code, message: error.message });
        else throw error;
      }
    }
    return { status: 202, data: { outcomes }, after: () => { for (const row of outcomes) if (row.run) this.launch(row.run.id); } };
  }
  setScheduler(enabled, correlation) {
    if (enabled && (this.lastError || this.logger.failed)) fail(503, 'AUTOMATION_PAUSED', 'Repair the storage/log error and restart the backend before scheduling.');
    const transition = this.enabled !== enabled;
    this.store.run("INSERT OR REPLACE INTO settings(key,value) VALUES('scheduler_enabled',?)", String(enabled));
    if (enabled && transition) this.store.run("UPDATE endpoints SET next_due_at=? WHERE id NOT IN (SELECT endpoint_id FROM runs WHERE state='RUNNING')", now());
    return { status: 200, data: { ...this.scheduler(), enabled }, after: () => {
      this.enabled = enabled;
      if (enabled && transition) for (const ep of this.endpoints()) if (!ep.checking) this.due.set(ep.id, performance.now());
      this.log(enabled ? 'scheduler_started' : 'scheduler_stopped', { source: 'api', correlation_id: correlation, state_changed: transition });
    } };
  }
  acknowledge(id, actor, correlation) {
    const incident = this.store.get('SELECT * FROM incidents WHERE id=?', id);
    if (!incident) fail(404, 'NOT_FOUND', 'Incident not found.');
    if (incident.state === 'RECOVERED') fail(409, 'INCIDENT_RECOVERED', 'This incident already recovered.');
    const changed = incident.state === 'OPEN';
    if (changed) this.store.run("UPDATE incidents SET state='ACKNOWLEDGED',acknowledged_by=?,acknowledged_at=? WHERE id=?", actor, now(), id);
    return { status: 200, data: this.store.get('SELECT * FROM incidents WHERE id=?', id), after: () => {
      if (changed) this.log('incident_acknowledged', { source: 'api', correlation_id: correlation, incident_id: id, actor_id: actor });
    } };
  }
  changeBehavior(id, behavior, correlation) {
    this.endpoint(id);
    this.store.run('UPDATE endpoints SET demo_behavior=? WHERE id=?', behavior, id);
    return { status: 200, data: this.endpoint(id), after: () => this.log('fixture_behavior_changed', { source: 'api', correlation_id: correlation, endpoint_id: id, behavior }) };
  }

  tick() {
    if (!this.enabled || this.stopping || this.logger.failed) return;
    try {
      const wall = Date.now(), mono = performance.now();
      if (Math.abs((wall - this.lastWall) - (mono - this.lastMono)) > 2000) {
        for (const ep of this.endpoints()) if (!ep.checking) {
          this.due.set(ep.id, mono + ep.interval_seconds * 1000);
          this.store.run('UPDATE endpoints SET next_due_at=? WHERE id=?', new Date(wall + ep.interval_seconds * 1000).toISOString(), ep.id);
        }
        this.log('schedule_reset', { reason: 'wall_clock_change', no_backfill: true });
      }
      this.lastWall = wall; this.lastMono = mono;
      const due = this.store.all("SELECT * FROM endpoints WHERE next_due_at IS NOT NULL AND id NOT IN (SELECT endpoint_id FROM runs WHERE state='RUNNING') ORDER BY next_due_at,id")
        .filter(ep => (this.due.get(ep.id) ?? Infinity) <= mono);
      let blocked = false;
      for (const ep of due) {
        if (this.scheduler().active_count >= this.c.concurrency) { blocked = true; break; }
        const correlation = randomUUID();
        const run = this.store.transaction(() => this.reserve(ep.id, 'scheduled', correlation, null, `schedule:${ep.id}:${ep.next_due_at}`));
        this.launch(run.id);
      }
      if (blocked && !this.capacityBlocked) this.log('scheduler_capacity_blocked', { capacity: this.c.concurrency });
      this.capacityBlocked = blocked;
    } catch (error) { this.pause(error, null); }
  }

  launch(id) {
    const job = this.execute(id).catch(error => this.pause(error, id));
    this.jobs.add(job);
    job.finally(() => this.jobs.delete(job));
  }
  pause(error, id) {
    this.enabled = false;
    this.lastError = this.logger.failed ? 'LOG_UNAVAILABLE' : 'STORAGE_UNAVAILABLE';
    try {
      this.store.transaction(() => {
        this.store.run("INSERT OR REPLACE INTO settings(key,value) VALUES('scheduler_enabled','false')");
        if (id) {
          const run = this.store.get('SELECT * FROM runs WHERE id=?', id);
          if (run?.state === 'RUNNING') {
            this.store.run("UPDATE runs SET state='INTERRUPTED',finished_at=?,interruption_reason=? WHERE id=?", now(), this.lastError, id);
            this.store.run("UPDATE endpoints SET status='UNKNOWN',next_due_at=NULL WHERE id=?", run.endpoint_id);
          }
        }
      });
    } catch { /* Startup reconciliation will handle rows if storage remains unavailable. */ }
    try { this.logger.emit('storage_failure', { level: 'error', check_id: id, error_category: this.lastError, diagnostic_code: error.code ?? 'FINALIZATION_FAILED', automation_paused: true }); }
    catch { /* Logger has already emitted its console fallback. */ }
  }

  async execute(id) {
    const run = this.store.get('SELECT * FROM runs WHERE id=?', id);
    const ep = this.endpoint(run.endpoint_id);
    const common = { source: 'dependency', correlation_id: run.correlation_id, parent_correlation_id: run.parent_correlation_id, check_id: id, endpoint_id: ep.id };
    this.log('check_started', { ...common, trigger: run.trigger, behavior: run.behavior });
    const runStart = performance.now();
    let ok = false, last, count = 0;
    for (let ordinal = 1; ordinal <= this.c.maxAttempts; ordinal++) {
      if (this.lastError || this.logger.failed) throw new Error('Automation paused during run.');
      const startedAt = now(), start = performance.now();
      let status = null, category = null;
      try {
        const target = `http://${this.c.fixtureHost}:${this.c.fixturePort}${new URL(ep.url).pathname}`;
        const response = await fetch(target, { method: 'GET', redirect: 'manual', signal: AbortSignal.timeout(this.c.timeoutMs),
          headers: { 'X-Demo-Behavior': run.behavior, 'X-Check-Id': String(id), 'X-Attempt': String(ordinal), 'X-Correlation-ID': run.correlation_id } });
        status = response.status;
        await response.body?.cancel();
        ok = status >= 200 && status < 300;
        category = ok ? null : retryable.has(status) ? 'retryable_http' : 'non_retryable_http';
      } catch (error) { category = error.name === 'TimeoutError' || error.name === 'AbortError' ? 'timeout' : 'connection_error'; }
      const latency = Math.round((performance.now() - start) * 100) / 100;
      last = { status, category }; count = ordinal;
      this.store.run('INSERT INTO attempts(check_id,ordinal,started_at,finished_at,status_code,error_category,latency_ms) VALUES(?,?,?,?,?,?,?)', id, ordinal, startedAt, now(), status, category, latency);
      this.log('attempt', { ...common, attempt: ordinal, status_code: status, error_category: category, latency_ms: latency, outcome: ok ? 'pass' : 'fail' });
      if (ok) break;
      if (category === 'non_retryable_http') { this.log('permanent_failure', { ...common, status_code: status, reason: 'non_retryable_http' }); break; }
      if (ordinal < this.c.maxAttempts) { this.log('retry_scheduled', { ...common, attempt: ordinal, wait_ms: this.c.retryDelayMs }); await sleep(this.c.retryDelayMs); }
    }
    const at = now(), events = [];
    this.store.transaction(() => {
      this.store.run('INSERT INTO results(check_id,endpoint_id,ok,attempt_count,final_category,completed_at) VALUES(?,?,?,?,?,?)', id, ep.id, ok ? 1 : 0, count, ok ? 'healthy' : last.category === 'non_retryable_http' ? 'non_retryable_http' : 'retry_exhausted', at);
      if (this.failNextFinalization) { this.failNextFinalization = false; this.logger.emit('storage_fault_injected', { ...common, point: 'after_result_insert_before_commit' }); throw new Error('Controlled finalization fault'); }
      this.store.run("UPDATE runs SET state='COMPLETED',finished_at=? WHERE id=?", at, id);
      this.store.run('UPDATE endpoints SET status=?,last_completed_at=?,next_due_at=? WHERE id=?', ok ? 'UP' : 'DOWN', at, new Date(Date.now() + ep.interval_seconds * 1000).toISOString(), ep.id);
      let incident = this.store.get("SELECT * FROM incidents WHERE endpoint_id=? AND state IN ('OPEN','ACKNOWLEDGED')", ep.id);
      if (ok && incident) {
        this.store.run("UPDATE incidents SET state='RECOVERED',recovery_check_id=?,recovered_at=? WHERE id=?", id, at, incident.id);
        this.store.run("INSERT INTO notifications(incident_id,check_id,event,created_at) VALUES(?,?,'recovered',?)", incident.id, id, at);
        events.push(['recovery_verified', { incident_id: incident.id }], ['support_notice_recorded', { incident_id: incident.id, notification_event: 'recovered', channel: 'in_app_demo' }]);
      } else if (!ok && !incident) {
        const reason = last.category === 'non_retryable_http' ? `Non-retryable HTTP ${last.status}; needs a person` : `Down after ${count} attempts (${last.status ?? last.category}); human action required`;
        const incidentId = Number(this.store.run("INSERT INTO incidents(endpoint_id,state,reason,opening_check_id,opened_at) VALUES(?,'OPEN',?,?,?)", ep.id, reason, id, at).lastInsertRowid);
        this.store.run("INSERT INTO notifications(incident_id,check_id,event,created_at) VALUES(?,?,'opened',?)", incidentId, id, at);
        events.push(['incident_opened', { incident_id: incidentId, routed_to: 'human' }], ['support_notice_recorded', { incident_id: incidentId, notification_event: 'opened', channel: 'in_app_demo' }]);
      } else if (!ok && incident) events.push(['incident_already_open', { incident_id: incident.id }]);
    });
    this.due.set(ep.id, performance.now() + ep.interval_seconds * 1000);
    if (ok && count > 1) this.log('transient_recovered', { ...common, attempts: count });
    for (const [event, fields] of events) this.log(event, { ...common, ...fields });
    this.log('check_completed', { ...common, outcome: ok ? 'pass' : 'fail', attempts: count, duration_ms: Math.round((performance.now() - runStart) * 100) / 100 });
  }

  uptime() {
    const rows = this.store.all(`SELECT e.id AS endpoint_id,e.name,COUNT(r.id) AS total_checks,
      COALESCE(SUM(r.ok),0) AS passed_checks,COUNT(r.id)-COALESCE(SUM(r.ok),0) AS failed_checks
      FROM endpoints e LEFT JOIN results r ON r.endpoint_id=e.id GROUP BY e.id ORDER BY e.id`);
    return { basis: 'completed_check_ratio', window: 'current_dataset', dataset_start: this.store.get('SELECT MIN(created_at) AS t FROM endpoints').t,
      as_of: now(), endpoints: rows.map(row => ({ ...row, uptime_percent: row.total_checks ? Math.round(row.passed_checks / row.total_checks * 10000) / 100 : null })) };
  }
  async close() { this.stopping = true; this.enabled = false; clearInterval(this.timer); await Promise.allSettled([...this.jobs]); }
}

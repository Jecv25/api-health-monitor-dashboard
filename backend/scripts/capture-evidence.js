import assert from 'node:assert/strict';
import path from 'node:path';
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { listenRuntime } from '../src/app.js';
import { environment, jsonFile, newEvidenceFolder, projectRoot } from './evidence-utils.js';

const folder = newEvidenceFolder('runs');
jsonFile(path.join(folder, 'environment.json'), environment());
const runtime = await listenRuntime({ port: 0, fixturePort: 0, seed: false, quiet: true, dbPath: path.join(folder, 'monitor.sqlite'), logPath: path.join(folder, 'runtime.jsonl') });
const records = [];
let current, operatorCookie, viewerCookie;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function request(route, method = 'GET', body, options = {}) {
  const headers = { ...(options.cookie === false ? {} : { Cookie: options.cookie ?? operatorCookie }), ...(body === undefined ? {} : { 'Content-Type': 'application/json', 'Idempotency-Key': options.key ?? randomUUID() }), ...(options.headers ?? {}) };
  if (!headers.Cookie) delete headers.Cookie;
  const started = new Date().toISOString();
  const response = await fetch(`${runtime.url}/api/v1${route}`, { method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const actual = { status: response.status, headers: { 'x-correlation-id': response.headers.get('x-correlation-id'), 'idempotency-replayed': response.headers.get('idempotency-replayed') }, body: response.status === 204 ? null : await response.json() };
  if (options.record !== false && current) current.exchanges.push({ requested_at: started, completed_at: new Date().toISOString(), request: { method, path: `/api/v1${route}`, headers: Object.fromEntries(Object.entries(headers).filter(([k]) => k.toLowerCase() !== 'cookie')), demo_persona: options.cookie === false ? 'none' : options.cookie === viewerCookie ? 'viewer' : 'operator', ...(body === undefined ? {} : { body }) }, actual });
  return { ...actual, cookie: response.headers.get('set-cookie')?.split(';')[0] };
}
async function register(service, behavior = 'stable', interval = 60) {
  const response = await request('/endpoints', 'POST', { name: `${service} Demo`, url: `https://api.sandbox.example/${service}/health`, interval_seconds: interval, demo_behavior: behavior });
  assert.equal(response.status, 201);
  return response.body.data;
}
async function run(id, key) {
  const accepted = await request(`/endpoints/${id}/checks`, 'POST', {}, { key });
  assert.equal(accepted.status, 202);
  for (let i = 0; i < 600; i++) {
    const poll = await request(`/checks/${accepted.body.data.id}`, 'GET', undefined, { record: false });
    if (poll.body.data.state !== 'RUNNING') {
      const terminal = await request(`/checks/${accepted.body.data.id}`);
      return terminal.body.data;
    }
    await delay(25);
  }
  throw new Error('Accepted run did not reach terminal state within the observation window.');
}
async function record(id, title, expected, execute) {
  current = { id, title, expected, expected_recorded_at: new Date().toISOString(), status: 'NOT RUN', exchanges: [] };
  jsonFile(path.join(folder, `${id}.json`), current);
  current.started_at = new Date().toISOString();
  try { current.observations = await execute(); current.status = 'PASS'; }
  catch (error) { current.status = 'FAIL'; current.failure = { name: error.name, message: error.message, actual: error.actual, expected: error.expected }; }
  current.finished_at = new Date().toISOString();
  jsonFile(path.join(folder, `${id}.json`), current);
  records.push({ id, title, status: current.status, started_at: current.started_at, finished_at: current.finished_at, artifact: `${id}.json` });
  console.log(`${id} ${current.status}: ${title}`);
  current = null;
}

let stable, flaky, dead, broken, outageIncident, normalRun, normalKey;
try {
  operatorCookie = (await request('/demo/session', 'POST', { persona: 'operator' }, { cookie: false })).cookie;
  viewerCookie = (await request('/demo/session', 'POST', { persona: 'viewer' }, { cookie: false })).cookie;
  await record('N01', 'Successful execution', { registration_status: 201, trigger_status: 202, http_attempts: [200], final_ok: true, incidents: 0, total_checks: 1, passed_checks: 1 }, async () => {
    stable = await register('library');
    assert.equal(stable.status, 'UNKNOWN');
    normalKey = randomUUID(); normalRun = await run(stable.id, normalKey);
    assert.deepEqual(normalRun.attempts.map(a => a.status_code), [200]);
    assert.equal(normalRun.result.ok, true);
    const report = (await request('/reports/uptime')).body.data;
    const incidents = (await request('/incidents')).body.data;
    assert.equal(incidents.length, 0); assert.equal(report.endpoints[0].total_checks, 1);
    return { run: normalRun, report, incident_count: incidents.length };
  });
  await record('I01', 'Invalid input rejected server-side', { status: 422, field_errors: ['name', 'url', 'interval_seconds'], no_endpoint_or_run_added: true }, async () => {
    const before = (await request('/endpoints')).body.data.length;
    const response = await request('/endpoints', 'POST', { name: '', url: 'http://api.sandbox.example/bad/health', interval_seconds: 5, demo_behavior: 'stable' });
    assert.equal(response.status, 422); assert.deepEqual(Object.keys(response.body.error.fields).sort(), ['interval_seconds', 'name', 'url']);
    const after = (await request('/endpoints')).body.data.length;
    assert.equal(after, before);
    return { before_endpoint_count: before, after_endpoint_count: after, field_errors: response.body.error.fields };
  });
  await record('U01', 'Unauthorized mutation rejected', { status: 401, no_run_or_fixture_call_added: true }, async () => {
    const before = runtime.store.get('SELECT COUNT(*) AS n FROM runs').n;
    const beforeCalls = runtime.logger.events.filter(e => e.event === 'fixture_request').length;
    const response = await request(`/endpoints/${stable.id}/checks`, 'POST', {}, { cookie: false });
    assert.equal(response.status, 401);
    assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, before);
    assert.equal(runtime.logger.events.filter(e => e.event === 'fixture_request').length, beforeCalls);
    return { before_run_count: before, after_run_count: runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, before_fixture_calls: beforeCalls, after_fixture_calls: runtime.logger.events.filter(e => e.event === 'fixture_request').length };
  });
  await record('U02', 'Viewer mutation and forged role rejected', { status: 403, no_run_added: true }, async () => {
    const response = await request(`/endpoints/${stable.id}/checks`, 'POST', {}, { cookie: viewerCookie, headers: { 'X-Role': 'operator' } });
    assert.equal(response.status, 403);
    return { status: response.status, actual_role_source: 'server demo session; browser role header ignored' };
  });
  await record('D01', 'Transient failure recovered by retry', { http_attempts: [503, 503, 200], retry_waits: 2, minimum_wait_ms: 700, completed_results: 1, final_ok: true, new_incidents: 0 }, async () => {
    flaky = await register('enrollment', 'flaky');
    const before = (await request('/incidents')).body.data.length;
    const result = await run(flaky.id);
    assert.deepEqual(result.attempts.map(a => a.status_code), [503, 503, 200]); assert.equal(result.result.ok, true);
    const gaps = result.attempts.slice(1).map((a, i) => Date.parse(a.started_at) - Date.parse(result.attempts[i].finished_at));
    assert.ok(gaps.every(gap => gap >= 700));
    assert.equal((await request('/incidents')).body.data.length, before);
    assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM results WHERE endpoint_id=?', flaky.id).n, 1);
    return { run: result, actual_retry_gaps_ms: gaps };
  });
  await record('D02', 'Persistent failure routed to a person and deduplicated', { two_runs_each: [503, 503, 503], active_incidents_for_endpoint: 1, opening_notices: 1, acknowledged_health: 'DOWN' }, async () => {
    dead = await register('payments', 'dead');
    const first = await run(dead.id);
    assert.deepEqual(first.attempts.map(a => a.status_code), [503, 503, 503]);
    outageIncident = (await request('/incidents?state=active')).body.data.find(i => i.endpoint_id === dead.id);
    assert.ok(outageIncident);
    const ack = await request(`/incidents/${outageIncident.id}/acknowledge`, 'POST', {});
    assert.equal(ack.body.data.state, 'ACKNOWLEDGED');
    const second = await run(dead.id);
    assert.equal(second.result.ok, false);
    const active = (await request('/incidents?state=active')).body.data.filter(i => i.endpoint_id === dead.id);
    const notices = (await request('/notifications')).body.data.filter(n => n.incident_id === outageIncident.id);
    assert.equal(active.length, 1); assert.equal(active[0].state, 'ACKNOWLEDGED'); assert.equal(notices.length, 1);
    const endpoint = (await request(`/endpoints/${dead.id}`)).body.data; assert.equal(endpoint.status, 'DOWN');
    return { first, second, active_incident: active[0], notices, endpoint };
  });
  await record('R01', 'Human repair followed by verified recovery', { immediately_after_fix: { health: 'DOWN', incident: 'ACKNOWLEDGED' }, after_check: { http_attempts: [200], health: 'UP', incident: 'RECOVERED', recovery_notices: 1 }, report: { total: 3, passed: 1, failed: 2, percent: 33.33 } }, async () => {
    await request(`/endpoints/${dead.id}/demo-behavior`, 'PATCH', { demo_behavior: 'stable' });
    const beforeEndpoint = (await request(`/endpoints/${dead.id}`)).body.data;
    const beforeIncident = (await request('/incidents')).body.data.find(i => i.id === outageIncident.id);
    assert.equal(beforeEndpoint.status, 'DOWN'); assert.equal(beforeIncident.state, 'ACKNOWLEDGED');
    const result = await run(dead.id); assert.deepEqual(result.attempts.map(a => a.status_code), [200]);
    const incident = (await request('/incidents')).body.data.find(i => i.id === outageIncident.id);
    const notices = (await request('/notifications')).body.data.filter(n => n.incident_id === outageIncident.id);
    assert.equal(incident.state, 'RECOVERED'); assert.equal(notices.filter(n => n.event === 'recovered').length, 1);
    const summary = (await request('/reports/uptime')).body.data.endpoints.find(e => e.endpoint_id === dead.id);
    assert.deepEqual([summary.total_checks, summary.passed_checks, summary.failed_checks, summary.uptime_percent], [3, 1, 2, 33.33]);
    return { beforeEndpoint, beforeIncident, passing_run: result, incident, notices, summary };
  });
  await record('D03', 'Non-retryable HTTP failure', { http_attempts: [404], retry_waits: 0, incident_state: 'OPEN' }, async () => {
    broken = await register('wrong-path', 'broken');
    const result = await run(broken.id); assert.deepEqual(result.attempts.map(a => a.status_code), [404]);
    const retries = runtime.logger.events.filter(e => e.event === 'retry_scheduled' && e.check_id === result.id);
    assert.equal(retries.length, 0);
    return { run: result, retry_events: retries, incidents: (await request('/incidents')).body.data.filter(i => i.endpoint_id === broken.id) };
  });
  await record('X01', 'Idempotent accepted request replay', { trigger_status: 202, original_run_id: normalRun.id, replay_header: 'true', no_run_added: true }, async () => {
    const before = runtime.store.get('SELECT COUNT(*) AS n FROM runs').n;
    const response = await request(`/endpoints/${stable.id}/checks`, 'POST', {}, { key: normalKey });
    assert.equal(response.status, 202); assert.equal(response.body.data.id, normalRun.id); assert.equal(response.headers['idempotency-replayed'], 'true');
    assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, before);
    return { replay_response: response.body, before_runs: before, after_runs: runtime.store.get('SELECT COUNT(*) AS n FROM runs').n };
  });
  await record('F01', 'Actual HTTP timeout injection', { per_attempt_timeout_ms: 3000, injected_fixture_delay_ms: 3500, attempts: 3, final_ok: false }, async () => {
    const endpoint = await register('timeout-demo');
    runtime.fixture.setDelay(3500);
    try {
      const result = await run(endpoint.id);
      assert.deepEqual(result.attempts.map(a => a.error_category), ['timeout', 'timeout', 'timeout']);
      assert.equal(result.result.ok, false);
      return { run: result, injection: 'Fixture delayed response headers by 3500 ms; worker aborted each request at configured 3000 ms.' };
    } finally { runtime.fixture.setDelay(0); }
  });
  await record('F02', 'Atomic result/recovery rollback on controlled storage fault', { fault_point: 'after result insertion, before transaction commit', state: 'INTERRUPTED', result: null, no_recovery_notice: true, dispatch_paused: true }, async () => {
    const before = runtime.store.get('SELECT COUNT(*) AS n FROM results').n;
    await request(`/endpoints/${broken.id}/demo-behavior`, 'PATCH', { demo_behavior: 'stable' });
    runtime.monitor.failNextFinalization = true;
    const result = await run(broken.id);
    assert.equal(result.state, 'INTERRUPTED'); assert.equal(result.result, null);
    assert.deepEqual(result.attempts.map(a => a.status_code), [200]);
    assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM results').n, before);
    assert.equal(runtime.monitor.enabled, false);
    const incident = (await request('/incidents')).body.data.find(i => i.endpoint_id === broken.id);
    assert.equal(incident.state, 'OPEN');
    const notices = (await request('/notifications')).body.data.filter(n => n.incident_id === incident.id);
    assert.equal(notices.filter(n => n.event === 'recovered').length, 0);
    return { run: result, before_results: before, after_results: runtime.store.get('SELECT COUNT(*) AS n FROM results').n, incident, notices, scheduler: (await request('/scheduler')).body.data };
  });
} finally {
  jsonFile(path.join(folder, 'summary.json'), { captured_at: new Date().toISOString(), config: { max_attempts: runtime.config.maxAttempts, retry_delay_ms: runtime.config.retryDelayMs, timeout_ms: runtime.config.timeoutMs, concurrency: runtime.config.concurrency, scheduler_tick_ms: runtime.config.tickMs, seed: false, transport: 'real_loopback_http', api_origin: runtime.url, fixture_origin: `http://127.0.0.1:${runtime.config.fixturePort}` }, records });
  await runtime.close();
  const lines = readFileSync(path.join(folder, 'runtime.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  jsonFile(path.join(folder, 'failure-injection-proof.json'), lines.filter(e => e.source === 'fixture' || ['attempt', 'retry_scheduled', 'incident_opened', 'incident_already_open', 'recovery_verified', 'storage_fault_injected', 'storage_failure'].includes(e.event)));
  const demoCases = [['01-success', ['N01']], ['02-transient-recovered', ['D01']], ['03-persistent-human-recovery', ['D02', 'R01']]];
  for (const [name, ids] of demoCases) {
    writeFileSync(path.join(folder, `${name}.md`), `# ${name}\n\nActual captured executions: ${ids.map(id => `[${id}](${id}.json)`).join(', ')}.\n\n${ids.map(id => { const r = records.find(r => r.id === id); return `- ${id}: **${r?.status ?? 'NOT RUN'}**, ${r?.started_at ?? 'not started'} to ${r?.finished_at ?? 'not finished'} (UTC).`; }).join('\n')}\n\nSee runtime.jsonl, failure-injection-proof.json, and the saved monitor.sqlite. No external service or notification provider was used.\n`);
  }
  writeFileSync(path.join(projectRoot, 'evidence', 'latest-api-run.txt'), `${path.relative(projectRoot, folder).replaceAll('\\', '/')}\n`);
  console.log(`Evidence preserved: ${folder}`);
}
process.exitCode = records.some(r => r.status !== 'PASS') ? 1 : 0;

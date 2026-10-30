import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { listenRuntime } from '../src/app.js';

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function lab(t, overrides = {}) {
  mkdirSync('data', { recursive: true });
  const folder = mkdtempSync(path.resolve('data/test-'));
  t.diagnostic(`Retained dataset: ${folder}`);
  const runtime = await listenRuntime({ port: 0, fixturePort: 0, dbPath: path.join(folder, 'monitor.sqlite'), logPath: path.join(folder, 'monitor.jsonl'), seed: false, quiet: true, ...overrides });
  let cookie;
  async function api(route, method = 'GET', body, extra = {}) {
    const response = await fetch(`${runtime.url}/api/v1${route}`, { method, headers: {
      ...(cookie ? { Cookie: cookie } : {}), ...(body !== undefined ? { 'Content-Type': 'application/json', 'Idempotency-Key': randomUUID() } : {}), ...extra,
    }, ...(body !== undefined ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}) });
    if (route === '/demo/session' && response.headers.has('set-cookie')) cookie = response.headers.get('set-cookie').split(';')[0];
    return { status: response.status, body: response.status === 204 ? null : await response.json(), headers: response.headers };
  }
  async function register(behavior = 'stable', interval = 60, service = `test-${randomUUID().slice(0, 8)}`) {
    const response = await api('/endpoints', 'POST', { name: 'Fictional API', url: `https://api.sandbox.example/${service}/health`, interval_seconds: interval, demo_behavior: behavior });
    assert.equal(response.status, 201);
    return response.body.data;
  }
  async function run(id, key = randomUUID()) {
    const response = await api(`/endpoints/${id}/checks`, 'POST', {}, { 'Idempotency-Key': key });
    assert.equal(response.status, 202);
    return response.body.data;
  }
  async function wait(id) {
    for (let i = 0; i < 500; i++) {
      const response = await api(`/checks/${id}`);
      if (response.body.data.state !== 'RUNNING') return response.body.data;
      await delay(30);
    }
    throw new Error(`Run ${id} did not complete.`);
  }
  t.after(async () => runtime.close());
  await api('/demo/session', 'POST', { persona: 'operator' });
  return { runtime, api, register, run, wait, folder };
}

test('normal check persists actual fixture response and contributes one passed observation', async t => {
  const { runtime, api, register, run, wait } = await lab(t);
  const ep = await register();
  assert.equal(ep.status, 'UNKNOWN');
  const result = await wait((await run(ep.id)).id);
  assert.equal(result.result.ok, true);
  assert.deepEqual(result.attempts.map(a => a.status_code), [200]);
  assert.equal((await api('/reports/uptime')).body.data.endpoints[0].uptime_percent, 100);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM incidents').n, 0);
  assert.ok(runtime.logger.events.some(e => e.event === 'fixture_response' && e.check_id === result.id));
});

test('invalid and unauthorized requests do not create work; browser role claim grants nothing', async t => {
  const { runtime, api, register } = await lab(t);
  const ep = await register();
  const invalid = await api('/endpoints', 'POST', { name: '', url: 'http://api.sandbox.example/bad/health', interval_seconds: 5 });
  assert.equal(invalid.status, 422);
  assert.deepEqual(Object.keys(invalid.body.error.fields).sort(), ['interval_seconds', 'name', 'url']);
  assert.equal((await api(`/endpoints/${ep.id}/checks`, 'POST', {}, { Cookie: '' })).status, 401);
  await api('/demo/session', 'POST', { persona: 'viewer' });
  assert.equal((await api(`/endpoints/${ep.id}/checks`, 'POST', {}, { 'X-Role': 'operator' })).status, 403);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, 0);
});

test('registration rejects unsafe namespaces, unknown fields, types and canonical duplicates', async t => {
  const { api, register } = await lab(t);
  const ep = await register();
  for (const input of [
    { url: 'https://real.example/service/health' }, { url: 'https://api.sandbox.example/a/../service/health' },
    { url: 'https://user@api.sandbox.example/service/health' }, { url: 'https://api.sandbox.example/service/health?x=1' },
    { interval_seconds: true }, { interval_seconds: 10.5 }, { interval_seconds: '60' }, { status: 'UP' }, { demo_behavior: 'unknown' },
  ]) {
    const result = await api('/endpoints', 'POST', { name: 'Valid name', url: 'https://api.sandbox.example/valid/health', ...input });
    assert.equal(result.status, 422, JSON.stringify(input));
  }
  assert.equal((await api('/endpoints', 'POST', { name: 'Duplicate', url: ep.url.replace('https://', 'https://').replace('api.sandbox.example', 'API.SANDBOX.EXAMPLE') })).status, 409);
  assert.equal((await api('/endpoints', 'POST', '{"broken":')).status, 400);
  assert.equal((await api('/endpoints', 'POST', {}, { 'Content-Type': 'text/plain' })).status, 415);
  for (const interval of [10, 3600]) assert.equal((await register('stable', interval)).interval_seconds, interval);
});

test('transient fault has three real attempts and bounded gaps but only one passed result', async t => {
  const { runtime, register, run, wait } = await lab(t);
  const result = await wait((await run((await register('flaky')).id)).id);
  assert.deepEqual(result.attempts.map(a => a.status_code), [503, 503, 200]);
  assert.equal(result.result.ok, true);
  for (let i = 1; i < 3; i++) assert.ok(Date.parse(result.attempts[i].started_at) - Date.parse(result.attempts[i - 1].finished_at) >= 700);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM results').n, 1);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM incidents').n, 0);
});

test('persistent failures deduplicate incident; acknowledgement and repair do not bypass verification', async t => {
  const { runtime, api, register, run, wait } = await lab(t);
  const ep = await register('dead');
  const first = await wait((await run(ep.id)).id);
  assert.equal(first.result.ok, false);
  const incident = (await api('/incidents')).body.data[0];
  await api(`/incidents/${incident.id}/acknowledge`, 'POST', {});
  await wait((await run(ep.id)).id);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM incidents').n, 1);
  assert.equal((await api('/incidents')).body.data[0].state, 'ACKNOWLEDGED');
  await api(`/endpoints/${ep.id}/demo-behavior`, 'PATCH', { demo_behavior: 'stable' });
  assert.equal((await api(`/endpoints/${ep.id}`)).body.data.status, 'DOWN');
  assert.equal((await api('/incidents')).body.data[0].state, 'ACKNOWLEDGED');
  await wait((await run(ep.id)).id);
  assert.equal((await api('/incidents')).body.data[0].state, 'RECOVERED');
  assert.deepEqual((await api('/notifications')).body.data.map(n => n.event), ['recovered', 'opened']);
  assert.equal((await api('/reports/uptime')).body.data.endpoints[0].uptime_percent, 33.33);
});

test('404 is non-retryable; replay and changed payload do not duplicate accepted changes', async t => {
  const { runtime, api, register, run, wait } = await lab(t);
  const ep = await register('broken');
  const key = randomUUID();
  const accepted = await run(ep.id, key);
  const complete = await wait(accepted.id);
  assert.deepEqual(complete.attempts.map(a => a.status_code), [404]);
  const replay = await api(`/endpoints/${ep.id}/checks`, 'POST', {}, { 'Idempotency-Key': key });
  assert.equal(replay.status, 202);
  assert.equal(replay.body.data.id, accepted.id);
  assert.equal(replay.headers.get('idempotency-replayed'), 'true');
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, 1);
  const createKey = randomUUID(), body = { name: 'Replay Test', url: 'https://api.sandbox.example/replay/health' };
  assert.equal((await api('/endpoints', 'POST', body, { 'Idempotency-Key': createKey })).status, 201);
  assert.equal((await api('/endpoints', 'POST', { ...body, name: 'Changed name' }, { 'Idempotency-Key': createKey })).status, 409);
});

test('overlap and global capacity stay bounded and are visible in run-all outcomes', async t => {
  const { api, register, run, wait } = await lab(t);
  const a = await register('flaky'), b = await register('flaky'), c = await register();
  const first = await run(a.id);
  assert.equal((await api(`/endpoints/${a.id}/checks`, 'POST', {})).status, 409);
  const second = await run(b.id);
  assert.equal((await api(`/endpoints/${c.id}/checks`, 'POST', {})).status, 503);
  const all = (await api('/checks/run-all', 'POST', {})).body.data.outcomes;
  assert.deepEqual(all.map(x => x.outcome), ['CHECK_IN_PROGRESS', 'CHECK_IN_PROGRESS', 'CAPACITY_BUSY']);
  assert.equal((await api('/scheduler')).body.data.active_count, 2);
  await Promise.all([wait(first.id), wait(second.id)]);
});

test('scheduler honors 10/60-second intervals and stop prevents further dispatch', async t => {
  const { runtime, api, register } = await lab(t);
  const short = await register('stable', 10), long = await register('stable', 60);
  await api('/scheduler/start', 'POST', {});
  for (let i = 0; i < 160; i++) {
    if (runtime.store.get('SELECT COUNT(*) AS n FROM results WHERE endpoint_id=?', short.id).n >= 2) break;
    await delay(100);
  }
  const shortRuns = runtime.store.all("SELECT * FROM runs WHERE endpoint_id=? AND state='COMPLETED' ORDER BY id", short.id);
  assert.equal(shortRuns.length, 2);
  assert.ok(Date.parse(shortRuns[1].started_at) - Date.parse(shortRuns[0].finished_at) >= 10000);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM results WHERE endpoint_id=?', long.id).n, 1);
  await api('/scheduler/stop', 'POST', {});
  const count = runtime.store.get('SELECT COUNT(*) AS n FROM runs').n;
  await delay(1200);
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM runs').n, count);
});

test('real timeout exhausts three attempts; failed final transaction rolls back and pauses work', async t => {
  const { runtime, api, register, run, wait } = await lab(t, { timeoutMs: 80, retryDelayMs: 20 });
  const ep = await register();
  runtime.fixture.setDelay(150);
  const timedOut = await wait((await run(ep.id)).id);
  assert.equal(timedOut.result.ok, false);
  assert.deepEqual(timedOut.attempts.map(a => a.error_category), ['timeout', 'timeout', 'timeout']);
  runtime.fixture.setDelay(0);
  runtime.monitor.failNextFinalization = true;
  const replayKey = randomUUID();
  const accepted = await run(ep.id, replayKey);
  const interrupted = await wait(accepted.id);
  assert.equal(interrupted.state, 'INTERRUPTED');
  assert.equal(interrupted.result, null);
  assert.equal((await api('/incidents')).body.data[0].state, 'OPEN');
  assert.equal(runtime.store.get('SELECT COUNT(*) AS n FROM notifications').n, 1);
  assert.equal((await api('/scheduler')).body.data.last_error, 'STORAGE_UNAVAILABLE');
  const replay = await api(`/endpoints/${ep.id}/checks`, 'POST', {}, { 'Idempotency-Key': replayKey });
  assert.equal(replay.status, 202);
  assert.equal(replay.body.data.id, accepted.id);
  assert.equal(replay.headers.get('idempotency-replayed'), 'true');
});

test('restart preserves history and marks leftover running work interrupted without replaying it', async t => {
  const { runtime, api, register, run, wait, folder } = await lab(t);
  const ep = await register();
  await wait((await run(ep.id)).id);
  const before = runtime.store.get('SELECT COUNT(*) AS n FROM results').n;
  const abandoned = runtime.store.run("INSERT INTO runs(endpoint_id,trigger,state,correlation_id,behavior,started_at) VALUES(?,'manual','RUNNING',?,'stable',?)", ep.id, randomUUID(), new Date().toISOString());
  // A committed unfinished record represents the on-disk state left by abrupt termination.
  const second = await listenRuntime({ port: 0, fixturePort: 0, dbPath: path.join(folder, 'monitor.sqlite'), logPath: path.join(folder, 'restart.jsonl'), seed: false, quiet: true });
  t.after(async () => second.close());
  assert.equal(second.monitor.runView(Number(abandoned.lastInsertRowid)).state, 'INTERRUPTED');
  assert.equal(second.monitor.endpoint(ep.id).status, 'UNKNOWN');
  assert.equal(second.store.get('SELECT COUNT(*) AS n FROM results').n, before);
  assert.equal(second.monitor.enabled, false);
  assert.equal((await fetch(second.url + '/api/v1/endpoints')).status, 401);
  assert.equal((await api('/reports/uptime')).body.data.endpoints[0].total_checks, 1);
});

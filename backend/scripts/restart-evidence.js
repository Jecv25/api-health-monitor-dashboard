import { spawn } from 'node:child_process';
import { openSync, closeSync, writeFileSync } from 'node:fs';
import { once } from 'node:events';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { environment, jsonFile, newEvidenceFolder, projectRoot } from './evidence-utils.js';

const folder = newEvidenceFolder('restart');
jsonFile(path.join(folder, 'environment.json'), environment());
const record = { id: 'C01', expected_recorded_at: new Date().toISOString(), expected: 'Abruptly terminate an actual child backend after a saved 503 attempt. Restart on the same SQLite file: interrupted run, no fabricated result, scheduler OFF, previous session invalid. Original idempotency key replays old run. A new-key run verifies health.', exchanges: [], status: 'NOT RUN' };
jsonFile(path.join(folder, 'C01.json'), record);
const children = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function start(label) {
  const output = openSync(path.join(folder, `${label}-console.log`), 'wx');
  const child = spawn(process.execPath, ['src/server.js'], { cwd: path.join(projectRoot, 'backend'), windowsHide: true,
    env: { ...process.env, PORT: '0', FIXTURE_PORT: '0', START_FIXTURE: 'true', SEED_DATA: 'true', DB_PATH: path.join(folder, 'monitor.sqlite'), LOG_PATH: path.join(folder, 'runtime.jsonl') },
    stdio: ['ignore', 'pipe', output] });
  children.push({ child, output });
  let all = '';
  child.stdout.on('data', chunk => { all += chunk.toString(); writeFileSync(path.join(folder, `${label}-stdout.log`), all); });
  for (let i = 0; i < 150; i++) {
    const line = all.split(/\r?\n/).find(line => line.includes('"event":"api_listening"'));
    if (line) return { child, url: `http://127.0.0.1:${JSON.parse(line).port}` };
    if (child.exitCode !== null) throw new Error(`Child ${label} exited before readiness.`);
    await delay(50);
  }
  throw new Error('Child readiness timeout.');
}
async function request(instance, route, method = 'GET', body, cookie, key) {
  const response = await fetch(`${instance.url}/api/v1${route}`, { method, headers: { ...(cookie ? { Cookie: cookie } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json', 'Idempotency-Key': key ?? randomUUID() }) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const actual = { timestamp: new Date().toISOString(), request: { method, path: route, ...(body === undefined ? {} : { body }), ...(key ? { idempotency_key: key } : {}) }, status: response.status, body: await response.json(), replayed: response.headers.get('idempotency-replayed') };
  record.exchanges.push(actual);
  return { ...actual, cookie: response.headers.get('set-cookie')?.split(';')[0] };
}
try {
  record.started_at = new Date().toISOString();
  const first = await start('before-crash');
  const cookie = (await request(first, '/demo/session', 'POST', { persona: 'operator' })).cookie;
  const key = randomUUID();
  const accepted = await request(first, '/endpoints/2/checks', 'POST', {}, cookie, key);
  assert.equal(accepted.status, 202);
  const id = accepted.body.data.id;
  let before;
  for (let i = 0; i < 100; i++) {
    before = (await request(first, `/checks/${id}`, 'GET', undefined, cookie)).body.data;
    if (before.attempts.length) break;
    await delay(10);
  }
  assert.equal(before.state, 'RUNNING'); assert.equal(before.attempts[0].status_code, 503);
  record.kill = { pid: first.child.pid, signal: 'SIGKILL', timestamp: new Date().toISOString(), target: 'Only the backend child spawned by this script.' };
  const exited = once(first.child, 'exit'); first.child.kill('SIGKILL'); await exited;
  const second = await start('after-restart');
  const rejected = await request(second, '/endpoints', 'GET', undefined, cookie); assert.equal(rejected.status, 401);
  const newCookie = (await request(second, '/demo/session', 'POST', { persona: 'operator' })).cookie;
  const interrupted = (await request(second, `/checks/${id}`, 'GET', undefined, newCookie)).body.data;
  assert.equal(interrupted.state, 'INTERRUPTED'); assert.equal(interrupted.result, null); assert.equal(interrupted.attempts.length, before.attempts.length);
  const endpoint = (await request(second, '/endpoints/2', 'GET', undefined, newCookie)).body.data; assert.equal(endpoint.status, 'UNKNOWN');
  const scheduler = (await request(second, '/scheduler', 'GET', undefined, newCookie)).body.data; assert.equal(scheduler.enabled, false);
  const replay = await request(second, '/endpoints/2/checks', 'POST', {}, newCookie, key);
  assert.equal(replay.body.data.id, id); assert.equal(replay.replayed, 'true');
  const fresh = await request(second, '/endpoints/2/checks', 'POST', {}, newCookie);
  let verified;
  for (let i = 0; i < 150; i++) {
    verified = (await request(second, `/checks/${fresh.body.data.id}`, 'GET', undefined, newCookie)).body.data;
    if (verified.state !== 'RUNNING') break;
    await delay(25);
  }
  assert.equal(verified.result.ok, true);
  const report = (await request(second, '/reports/uptime', 'GET', undefined, newCookie)).body.data;
  assert.equal(report.endpoints.find(e => e.endpoint_id === 2).total_checks, 1);
  record.actual = { before_crash: before, after_restart: interrupted, endpoint_after_restart: endpoint, scheduler_after_restart: scheduler, new_verification: verified, report };
  record.status = 'PASS';
} catch (error) { record.status = 'FAIL'; record.error = { name: error.name, message: error.message }; }
finally {
  for (const { child, output } of children) {
    if (child.exitCode === null && child.signalCode === null) { const exited = once(child, 'exit'); child.kill(); await exited; }
    closeSync(output);
  }
  record.finished_at = new Date().toISOString();
  jsonFile(path.join(folder, 'C01.json'), record);
  writeFileSync(path.join(projectRoot, 'evidence', 'latest-restart-run.txt'), `${path.relative(projectRoot, folder).replaceAll('\\', '/')}\n`);
  console.log(`C01 ${record.status}. Actual process interruption evidence: ${folder}`);
}
process.exitCode = record.status === 'PASS' ? 0 : 1;

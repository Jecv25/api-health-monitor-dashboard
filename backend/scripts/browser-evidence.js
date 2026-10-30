import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { listenRuntime } from '../src/app.js';
import { environment, jsonFile, newEvidenceFolder, projectRoot } from './evidence-utils.js';

const folder = newEvidenceFolder('browser');
jsonFile(path.join(folder, 'environment.json'), environment());
const runtime = await listenRuntime({ port: 0, fixturePort: 0, quiet: true, seed: true, dbPath: path.join(folder, 'monitor.sqlite'), logPath: path.join(folder, 'runtime.jsonl') });
const results = [], snapshots = [], errors = [], exchanges = [];
let browser, page;
async function capture(name) {
  const file = `${name}.png`;
  await page.screenshot({ path: path.join(folder, file), fullPage: true });
  snapshots.push({ file, captured_at: new Date().toISOString(), viewport: page.viewportSize() });
}
async function check(id, expected, action) {
  const record = { id, expected, expected_recorded_at: new Date().toISOString(), status: 'NOT RUN' };
  jsonFile(path.join(folder, `${id}.json`), record);
  record.started_at = new Date().toISOString();
  try { record.actual = await action(); record.status = 'PASS'; }
  catch (error) {
    record.status = 'FAIL'; record.error = { name: error.name, message: error.message };
    try { await capture(`${id}-failure`); writeFileSync(path.join(folder, `${id}-semantics.txt`), await page.locator('body').innerText()); jsonFile(path.join(folder, `${id}-semantics.json`), await page.locator('flt-semantics').evaluateAll(nodes => nodes.map(n => ({ role: n.getAttribute('role'), label: n.getAttribute('aria-label'), text: n.textContent })).slice(0, 500))); } catch { /* Preserve original failure even if browser died. */ }
  }
  record.finished_at = new Date().toISOString();
  jsonFile(path.join(folder, `${id}.json`), record);
  results.push(record);
  console.log(`${id} ${record.status}${record.error ? `: ${record.error.message.slice(0, 240)}` : ''}`);
  return record.status === 'PASS';
}
async function clickButton(name) { await page.getByRole('button', { name, exact: true }).last().click({ timeout: 12000 }); }
async function nav(name) {
  if (page.viewportSize().width < 1000) await clickButton('Open navigation menu');
  const safeName = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  await page.getByRole('button', { name: new RegExp(safeName) }).first().click({ timeout: 12000 });
}
async function waitText(text) { await page.getByText(text, { exact: false }).or(page.getByLabel(text, { exact: false })).first().waitFor({ timeout: 18000 }); }

try {
  browser = await chromium.launch({ executablePath: process.env.CHROME_PATH ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--no-first-run', '--no-default-browser-check'] });
  jsonFile(path.join(folder, 'browser-version.json'), { browser: browser.version(), driver: JSON.parse(readFileSync(path.join(projectRoot, 'backend/node_modules/playwright-core/package.json'), 'utf8')).version });
  page = await browser.newPage({ viewport: { width: 1280, height: 1000 }, deviceScaleFactor: 1 });
  page.on('pageerror', error => errors.push({ timestamp: new Date().toISOString(), message: error.message }));
  page.on('response', async response => {
    const request = response.request();
    if (!response.url().includes('/api/v1') || request.method() === 'GET') return;
    try { exchanges.push({ timestamp: new Date().toISOString(), request: { method: request.method(), path: new URL(request.url()).pathname, body: request.postDataJSON() }, actual: { status: response.status(), body: await response.json() } }); } catch { /* DELETE has no body. */ }
  });
  await page.goto(runtime.url, { waitUntil: 'networkidle', timeout: 45000 });
  jsonFile(path.join(folder, 'initial-semantics.json'), await page.locator('flt-semantics').evaluateAll(nodes => nodes.map(n => ({ role: n.getAttribute('role'), label: n.getAttribute('aria-label'), text: n.textContent })).slice(0, 300)));
  const ready = await check('B01-login', 'Actual Flutter release app displays labeled placeholder login; operator enters dashboard.', async () => {
    await waitText('Enter the local demo');
    await capture('01-login-desktop');
    await clickButton('Enter dashboard');
    await waitText('Endpoint overview');
    await capture('02-endpoints-desktop');
    return { title: await page.title(), endpoints: runtime.monitor.endpoints().length, frontend: 'Compiled Flutter Web release, not an HTML substitute.' };
  });
  if (!ready) throw new Error('Cannot continue UI demo until initial Flutter access is fixed.');
  await check('B02-success-demo', 'Library API completes one real 200 attempt and displays the saved passing observation.', async () => {
    await page.getByRole('button', { name: 'View results', exact: true }).nth(0).click();
    await clickButton('Run check'); await waitText('Verified healthy');
    await capture('03-success-demo');
    const run = runtime.store.get('SELECT id FROM runs WHERE endpoint_id=1 ORDER BY id DESC LIMIT 1');
    const saved = runtime.monitor.runView(run.id); assert.deepEqual(saved.attempts.map(a => a.status_code), [200]);
    return { run: saved };
  });
  await check('B03-transient-demo', 'Enrollment API shows 503, 503, 200 and one passed result.', async () => {
    await nav('Endpoints');
    await page.getByRole('button', { name: 'View results', exact: true }).nth(1).click();
    await clickButton('Run check'); await waitText('Verified healthy');
    await capture('04-transient-demo');
    const run = runtime.store.get('SELECT id FROM runs WHERE endpoint_id=2 ORDER BY id DESC LIMIT 1');
    const saved = runtime.monitor.runView(run.id); assert.deepEqual(saved.attempts.map(a => a.status_code), [503, 503, 200]);
    return { run: saved };
  });
  await check('B04-persistent-human-recovery-demo', 'Payments fails after three attempts, operator acknowledges and simulates repair; only a new passing check recovers the incident and records a notice.', async () => {
    await nav('Endpoints');
    await page.getByRole('button', { name: 'View results', exact: true }).nth(2).click();
    await clickButton('Run check'); await waitText('Check failed');
    await capture('05-persistent-demo');
    await nav('Incidents'); await clickButton('Acknowledge'); await waitText('ACKNOWLEDGED');
    await capture('06-acknowledged');
    await clickButton('View endpoint'); await clickButton('Simulate fix');
    await waitText('Always healthy');
    const before = runtime.store.get('SELECT * FROM incidents WHERE endpoint_id=3'); assert.equal(before.state, 'ACKNOWLEDGED');
    await capture('07-repair-awaiting-verification');
    await clickButton('Run check'); await waitText('Verified healthy');
    await nav('Incidents'); await waitText('RECOVERED'); await capture('08-verified-recovery');
    const after = runtime.store.get('SELECT * FROM incidents WHERE endpoint_id=3'); assert.equal(after.state, 'RECOVERED');
    assert.equal(runtime.store.get("SELECT COUNT(*) AS n FROM notifications WHERE event='recovered'").n, 1);
    return { before_passing_check: before, after_passing_check: after, notices: runtime.store.all('SELECT * FROM notifications') };
  });
  await check('B05-report', 'Report displays persisted completed-check ratios; browser demo Payments has 1 fail + 1 pass = 50%.', async () => {
    await nav('Uptime report'); await waitText('50.00%'); await capture('09-uptime-report-desktop');
    const report = runtime.monitor.uptime(); assert.equal(report.endpoints.find(e => e.endpoint_id === 3).uptime_percent, 50);
    return report;
  });
  await check('B06-responsive', 'Endpoint list and incident/report navigation remain usable at 768 and 390 CSS pixels without document horizontal overflow.', async () => {
    const actual = [];
    for (const width of [768, 390]) {
      await page.setViewportSize({ width, height: 1000 });
      await nav('Endpoints'); await waitText('Endpoint overview');
      await capture(`10-endpoints-${width}`);
      const layout = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth }));
      assert.ok(layout.document <= layout.viewport);
      await nav('Incidents'); await waitText('In-app demo notifications'); await capture(`11-incidents-${width}`);
      await nav('Uptime report'); await waitText('50.00%'); await capture(`12-report-${width}`);
      actual.push({ width, layout });
    }
    return actual;
  });
  await check('B07-invalid-form', 'Submitting a blank name, HTTP URL, and interval 5 shows inline client errors and creates no endpoint.', async () => {
    await page.setViewportSize({ width: 1280, height: 1000 });
    await nav('Register endpoint');
    await page.getByRole('textbox', { name: 'Health URL', exact: true }).fill('http://api.sandbox.example/bad/health');
    await page.getByRole('textbox', { name: 'Check interval (seconds)', exact: true }).fill('5');
    const before = runtime.monitor.endpoints().length;
    await clickButton('Register endpoint'); await waitText('Enter 3–40 characters'); await capture('13-invalid-form');
    assert.equal(runtime.monitor.endpoints().length, before);
    return { before_endpoint_count: before, after_endpoint_count: runtime.monitor.endpoints().length };
  });
  await check('B08-network-error', 'An explicitly injected browser transport refusal produces network feedback while retaining last confirmed records.', async () => {
    await nav('Endpoints');
    await page.route('**/api/v1/**', route => route.abort('connectionrefused'));
    await clickButton('Refresh records'); await waitText('Cannot reach the local server'); await capture('14-network-error');
    await page.unroute('**/api/v1/**'); await clickButton('Retry connection'); await waitText('Endpoint overview');
    return { injection: 'Playwright abort(connectionrefused) at browser transport; not represented as backend failure.', endpoint_records_retained: runtime.monitor.endpoints().length };
  });
  await check('B09-server-error-state', 'A labeled browser-only 503-response injection shows safe server-error text and a reference; no success is claimed.', async () => {
    const correlation = randomUUID();
    await page.route('**/api/v1/endpoints', route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'CONTROLLED_UI_503', message: 'Controlled UI-only server-error injection. Local storage requires maintainer review.' }, correlation_id: correlation }) }));
    await clickButton('Refresh records'); await waitText('Controlled UI-only server-error injection'); await capture('15-server-error-state');
    await page.unroute('**/api/v1/endpoints'); await clickButton('Retry connection');
    return { injection: 'Browser response stub, UI rendering verification only. Actual SQLite fault evidence is F02 in the API run.', response_status: 503, correlation };
  });
} catch (error) { errors.push({ timestamp: new Date().toISOString(), fatal: true, message: error.message }); }
finally {
  jsonFile(path.join(folder, 'summary.json'), { recorded_at: new Date().toISOString(), origin: runtime.url, results: results.map(r => ({ id: r.id, status: r.status })), snapshots, errors });
  jsonFile(path.join(folder, 'mutations.json'), exchanges);
  await browser?.close();
  await runtime.close();
  writeFileSync(path.join(projectRoot, 'evidence', 'latest-browser-run.txt'), `${path.relative(projectRoot, folder).replaceAll('\\', '/')}\n`);
  console.log(`Browser evidence preserved: ${folder}`);
}
process.exitCode = results.some(r => r.status !== 'PASS') || errors.some(e => e.fatal) || !results.length ? 1 : 0;

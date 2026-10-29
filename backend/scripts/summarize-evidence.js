import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { environment, jsonFile, projectRoot } from './evidence-utils.js';

const evidenceRoot = path.join(projectRoot, 'evidence');
const slash = value => value.replaceAll('\\', '/');
const relative = file => slash(path.relative(evidenceRoot, file));
const load = file => JSON.parse(readFileSync(file, 'utf8'));
function pointer(name) {
  const file = path.join(evidenceRoot, `latest-${name}-run.txt`);
  if (!existsSync(file)) return null;
  const resolved = path.resolve(projectRoot, readFileSync(file, 'utf8').trim());
  if (!resolved.startsWith(evidenceRoot + path.sep)) throw new Error('Evidence pointer is outside evidence/.');
  return resolved;
}
function runs(kind) {
  const directory = path.join(evidenceRoot, kind);
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).filter(x => x.isDirectory()).map(x => path.join(directory, x.name)).sort();
}

const api = pointer('api'), browser = pointer('browser'), restart = pointer('restart');
const validation = runs('validation').filter(dir => existsSync(path.join(dir, 'results.json')));
const latestFull = validation.filter(dir => load(path.join(dir, 'results.json')).some(r => r.name === 'backend-tests')).at(-1);
const index = ['# Module 13 evidence index', '', `Generated from retained execution artifacts at ${new Date().toISOString()} (UTC). Display timezone: Asia/Manila. No expected value was substituted for an actual result.`, '', '## Latest API cases', ''];
const summary = api ? load(path.join(api, 'summary.json')) : null;
const metrics = { generated_at: new Date().toISOString() };
if (summary) {
  index.push(`Dataset: [summary](${relative(api)}/summary.json), [source/environment identity](${relative(api)}/environment.json), [actual JSONL logs](${relative(api)}/runtime.jsonl), [SQLite](${relative(api)}/monitor.sqlite), [failure-injection proof](${relative(api)}/failure-injection-proof.json).`, '', '| Case | Actual status | Started (UTC) | Request / expected / actual / timestamps |', '| --- | --- | --- | --- |');
  for (const r of summary.records) index.push(`| ${r.id}: ${r.title} | ${r.status} | ${r.started_at} | [record](${relative(api)}/${r.artifact}) |`);
  index.push('', 'Three preserved demos:', '', `1. [Successful execution](${relative(api)}/01-success.md).`, `2. [Transient recovered by retry](${relative(api)}/02-transient-recovered.md).`, `3. [Persistent failure, human acknowledgement, and verified recovery](${relative(api)}/03-persistent-human-recovery.md).`, '');
  const db = new DatabaseSync(path.join(api, 'monitor.sqlite'), { readOnly: true });
  const events = readFileSync(path.join(api, 'runtime.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  metrics.api = {
    source: relative(api), configuration: summary.config,
    runs: db.prepare('SELECT state,COUNT(*) AS count FROM runs GROUP BY state').all(),
    results: db.prepare('SELECT COUNT(*) AS total,SUM(ok) AS passed,COUNT(*)-SUM(ok) AS failed FROM results').get(),
    attempts: db.prepare('SELECT COUNT(*) AS count FROM attempts').get().count,
    retries: events.filter(e => e.event === 'retry_scheduled').length,
    durations: events.filter(e => e.event === 'check_completed').map(e => ({ check_id: e.check_id, endpoint_id: e.endpoint_id, outcome: e.outcome, duration_ms: e.duration_ms, attempts: e.attempts })),
    interrupted: db.prepare("SELECT id,endpoint_id,interruption_reason FROM runs WHERE state='INTERRUPTED'").all(),
    interpretation: 'Deliberately injected local scenarios; these durations are observations, not a capacity/load benchmark. Interrupted finalization has no result; attempt rows remain.',
  };
  const startEvent = events.find(e => e.event === 'check_started');
  const endEvent = events.filter(e => e.event === 'check_completed').at(-1);
  if (startEvent && endEvent) {
    const observedSeconds = (Date.parse(endEvent.timestamp) - Date.parse(startEvent.timestamp)) / 1000;
    metrics.api.observed_sequence = { seconds: observedSeconds, completed_checks_per_second: Math.round(metrics.api.results.total / observedSeconds * 1000) / 1000, completed_check_failure_ratio: metrics.api.results.failed / metrics.api.results.total,
      basis: 'One deliberately injected sequential lab scenario, including waits and API interactions; not a capacity or availability benchmark.' };
  }
  db.close();
}
if (latestFull) {
  const dataRoot = path.join(latestFull, 'backend-test-datasets');
  if (existsSync(dataRoot)) for (const entry of readdirSync(dataRoot)) {
    const logfile = path.join(dataRoot, entry, 'monitor.jsonl');
    if (!existsSync(logfile)) continue;
    const events = readFileSync(logfile, 'utf8').trim().split('\n').map(JSON.parse);
    const started = events.find(e => e.event === 'scheduler_started');
    if (!started) continue;
    const db = new DatabaseSync(path.join(dataRoot, entry, 'monitor.sqlite'), { readOnly: true });
    const endpoints = db.prepare('SELECT id,interval_seconds FROM endpoints ORDER BY id').all();
    const observations = endpoints.map(ep => {
      const completed = db.prepare("SELECT id,started_at,finished_at FROM runs WHERE endpoint_id=? AND state='COMPLETED' ORDER BY id").all(ep.id);
      return { ...ep, completed_runs: completed, first_dispatch_delay_ms: completed.length ? Date.parse(completed[0].started_at) - Date.parse(started.timestamp) : null,
        completion_to_next_start_gaps_ms: completed.slice(1).map((run, i) => Date.parse(run.started_at) - Date.parse(completed[i].finished_at)) };
    });
    metrics.scheduler = { source: relative(path.join(dataRoot, entry)), observations, stopped_at: events.find(e => e.event === 'scheduler_stopped')?.timestamp,
      interpretation: 'Actual small 10/60-second interval/stop test. No starvation/load conclusion.' };
    db.close();
  }
}
index.push('## Actual browser walkthrough', '');
if (browser) {
  const data = load(path.join(browser, 'summary.json'));
  index.push(`[Browser summary](${relative(browser)}/summary.json), [browser version](${relative(browser)}/browser-version.json), [actual mutation responses](${relative(browser)}/mutations.json), [backend logs](${relative(browser)}/runtime.jsonl).`, '', '| Case | Actual status | Detailed record |', '| --- | --- | --- |');
  for (const r of data.results) index.push(`| ${r.id} | ${r.status} | [expected / actual](${relative(browser)}/${r.id}.json) |`);
  index.push('', 'Actual screenshots (compiled Flutter Web):', '');
  for (const s of data.snapshots) index.push(`- [${s.file}](${relative(browser)}/${s.file}) — ${s.viewport.width}×${s.viewport.height}, captured ${s.captured_at}.`);
  index.push('', 'The browser demo has one failed Payments check and one passing repair-verification check: 50.00%. The API D02/R01 dataset intentionally has two failed checks and one pass: 33.33%. They are separately identified datasets. B08 and B09 explicitly inject browser transport/HTTP responses to verify feedback; actual backend timeout and transaction-failure evidence is F01/F02.', '');
  metrics.browser = { source: relative(browser), results: data.results, errors: data.errors };
}
index.push('## Actual crash / restart', '');
if (restart) {
  const data = load(path.join(restart, 'C01.json'));
  index.push(`[C01 ${data.status}](${relative(restart)}/C01.json): an actual spawned backend was abruptly terminated after a saved 503 attempt, then restarted against the same database. See [logs](${relative(restart)}/runtime.jsonl) and [source/environment](${relative(restart)}/environment.json).`, '');
  metrics.restart = { source: relative(restart), status: data.status, actual_process_interruption: true };
}
index.push('## Validation and preserved failures', '', '| Run | Command | Actual exit | Output |', '| --- | --- | --- | --- |');
for (const folder of validation) for (const r of load(path.join(folder, 'results.json'))) index.push(`| ${path.basename(folder)} | ${r.command} | ${r.exit_code} | [log](${relative(folder)}/${r.name}.log) |`);
index.push('', 'Earlier browser runs are retained:', '');
for (const folder of runs('browser')) {
  if (!existsSync(path.join(folder, 'summary.json'))) continue;
  const data = load(path.join(folder, 'summary.json'));
  index.push(`- [${path.basename(folder)}](${relative(folder)}/summary.json): ${data.results.map(r => `${r.id} ${r.status}`).join('; ')}.`);
}
index.push('', 'Earlier API executions are retained:', '');
for (const folder of runs('runs')) if (existsSync(path.join(folder, 'summary.json'))) index.push(`- [${path.basename(folder)}](${relative(folder)}/summary.json).`);
index.push('', 'The initial dropdown overflow, selector failures, and setup problems are not erased. See [setup issues](setup-issues.md) and [lab log](lab-log.md). The original failure logs and later passing reruns are separate artifacts.', '');
if (latestFull) index.push(`Latest complete validation: [results](${relative(latestFull)}/results.json), [environment/source identity](${relative(latestFull)}/environment.json). The backend-test datasets/logs are copied under that validation directory after the tests close their databases.`, '');
index.push('[Observed metrics](metrics.json) · [Lab log](lab-log.md) · [Limitations](../limitations.md) · [Maintainability](../maintainability-note.md)', '');
index.push('[Configuration/log audit](configuration-audit.json) · [Module 13 interpretation](interpretation.md) · [Local source-control record](source-control.json) · [Viva practice notes](../docs/viva-guide.md)', '');
writeFileSync(path.join(evidenceRoot, 'evidence-index.md'), index.join('\n'));
jsonFile(path.join(evidenceRoot, 'metrics.json'), metrics);
jsonFile(path.join(evidenceRoot, 'final-source-inventory.json'), environment());

const log = ['# Module 13 laboratory log', '', 'Scope: local API Health Monitoring Dashboard, Module 13 only. All services/data are fictional. The user first requested Stage 1 only, then explicitly authorized completing the whole Module 13; later stages therefore proceeded without another approval pause.', '', '## Environment and identity', '', 'Node.js 24.x, installed Flutter 3.47.8 / Dart 3.13.7, Windows, installed Chrome, locked npm/pub dependencies. Exact runtime/OS/source hashes accompany each execution; the latest validation includes raw Flutter toolchain output. UTC timestamps are real execution-clock readings; add eight hours for Asia/Manila. No commit/revision timestamp is invented.', '', '## Observations and improvements', '', '1. Read the brief, introduction, Module 13, and HTML reference. Wrote the boundary, decisions, pattern comparison, retry/recovery policy, runbook, API/screen contracts, diagrams, and acceptance criteria before application code.', '2. Implemented Express + SQLite + a real loopback HTTP fixture, then Flutter Web. Initial setup hit PowerShell npm.ps1 execution policy, restricted npm network access, and an unprivileged Flutter-cache lock loop. Used npm.cmd and approved SDK/network execution; did not change machine execution policy. One smoke command initially failed because its temporary-data parent did not exist. See setup-issues.md; no application check was claimed from that failed command.', '3. Ten backend checks passed on the first test suite run, including actual retry gaps, 10/60-second scheduler behavior, duplicate/capacity control, timeout handling, and rollback. Raw final reruns and closed test databases are retained in validation/.', '4. Initial Flutter widget tests failed on dropdown/layout overflow. Preserved a complete reproduction in the timestamped reproduced-layout-failure directory. Added expanded/ellipsized dropdown options and wrapping scheduler status; the same three tests then passed. Later added first-invalid-field focus and removal of the boot status after first frame.', '5. The first browser automation run could not locate rendered Flutter text using plain DOM text. The saved screenshot shows the real login; the run remains FAIL. Updated the driver to use Flutter accessibility labels. The next run exposed the incident-badge name mismatch and a registration submit selector that clicked navigation; preserved those failures and corrected the driver. Subsequent complete walkthroughs passed the actual success/transient/persistent-recovery/report/responsive/invalid/network/server-error cases.', '6. Strengthened rollback evidence: after changing a failed endpoint to healthy behavior, injected a transaction fault after the actual HTTP 200 result insertion but before commit. No final result/recovery notice was committed and the active incident stayed OPEN. Retained the earlier result-rollback run too. Idempotent accepted-response lookup is allowed while automation is paused, and a focused test verifies it.', '7. Captured actual process interruption by killing only a backend child created by the restart script, then restarting on its same database. The previous session failed, the old attempt survived as INTERRUPTED, no result was invented, original-key replay referenced the old run, and a new-key run completed normally.', '', '## Latest execution references', ''];
if (api) log.push(`- API demos/adverse cases: [summary](${relative(api)}/summary.json).`);
if (browser) log.push(`- Actual Flutter walkthrough/screenshots: [summary](${relative(browser)}/summary.json).`);
if (restart) log.push(`- Actual process recovery: [C01](${relative(restart)}/C01.json).`);
if (latestFull) log.push(`- Complete checks/build and exact execution times: [results](${relative(latestFull)}/results.json).`);
log.push('', '## Interpretation and remaining limits', '', 'Observed outcomes support this controlled local automation workflow. They do not establish internet-service availability, secure real identity, sustained-load capacity, external notification delivery, cross-browser certification, or production deployment. The full limitation list and maintainability discussion are linked from the evidence index. Failed observations are retained with their disposition; a passing rerun does not rewrite them.', '', 'AI assistance: Codex assisted with implementation, tests, and documentation. The student must verify the artifacts, acknowledge assistance, and provide their own individual contribution/reflection under the institution’s policy.', '');
writeFileSync(path.join(evidenceRoot, 'lab-log.md'), log.join('\n'));
writeFileSync(path.join(evidenceRoot, 'README.md'), '# Module 13 execution evidence\n\nStart with [evidence-index.md](evidence-index.md). It links actual requests, expected/actual outcomes, UTC timestamps, the three demos, saved SQLite data, real logs, failure-injection proof, Chrome screenshots, restart proof, validation, and preserved failures. [lab-log.md](lab-log.md) records the interpretation and improvement history.\n\nRe-run commands from the project README. Every run writes a new timestamped directory; summarize-evidence.js refreshes the index without deleting runs. The latest pointers identify the selected datasets; do not combine counts from different runs.\n');
console.log(`Evidence index and lab log refreshed: ${evidenceRoot}`);

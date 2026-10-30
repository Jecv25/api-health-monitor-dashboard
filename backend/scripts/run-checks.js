import { mkdirSync, openSync, closeSync, writeFileSync, readFileSync, readdirSync, cpSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { environment, jsonFile } from './evidence-utils.js';

const root = path.resolve(import.meta.dirname, '../..');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const label = process.argv[2] ?? 'validation';
const folder = path.join(root, 'evidence', 'validation', `${stamp}-${label}`);
mkdirSync(folder, { recursive: true });
jsonFile(path.join(folder, 'environment.json'), environment());
const onlyFlutter = process.argv.includes('--flutter-only');
const commands = onlyFlutter ? [['flutter-tests', 'flutter_web', 'flutter.bat test --reporter expanded']] : [
  ['toolchain', 'flutter_web', 'flutter.bat --version --machine'],
  ['backend-tests', 'backend', 'npm.cmd test'],
  ['flutter-analyze', 'flutter_web', 'flutter.bat analyze'],
  ['flutter-tests', 'flutter_web', 'flutter.bat test --reporter expanded'],
  ['flutter-build', 'flutter_web', 'flutter.bat build web --release --no-web-resources-cdn'],
];
const records = [];
for (const [name, directory, command] of commands) {
  const dataDirectory = path.join(root, 'backend/data');
  const previousDatasets = new Set(existsSync(dataDirectory) ? readdirSync(dataDirectory) : []);
  const startedAt = new Date().toISOString();
  const filename = path.join(folder, `${name}.log`);
  const output = openSync(filename, 'wx');
  const result = spawnSync('cmd.exe', ['/d', '/s', '/c', command], { cwd: path.join(root, directory), stdio: ['ignore', output, output], windowsHide: true });
  closeSync(output);
  const record = { name, command, started_at: startedAt, finished_at: new Date().toISOString(), exit_code: result.status, signal: result.signal, ...(result.error ? { launch_error: result.error.message } : {}), output: path.relative(root, filename).replaceAll('\\', '/') };
  records.push(record);
  if (name === 'backend-tests' && existsSync(dataDirectory)) {
    const target = path.join(folder, 'backend-test-datasets');
    mkdirSync(target, { recursive: true });
    for (const entry of readdirSync(dataDirectory)) if (entry.startsWith('test-') && !previousDatasets.has(entry)) {
      cpSync(path.join(dataDirectory, entry), path.join(target, entry), { recursive: true, errorOnExist: true, force: false });
    }
    record.retained_datasets = path.relative(root, target).replaceAll('\\', '/');
  }
  console.log(JSON.stringify(record));
  console.log(readFileSync(filename, 'utf8').split(/\r?\n/).filter(Boolean).slice(-7).join('\n'));
}
writeFileSync(path.join(folder, 'results.json'), JSON.stringify(records, null, 2));
console.log(`Validation preserved: ${folder}`);
process.exitCode = records.some(r => r.exit_code !== 0) ? 1 : 0;

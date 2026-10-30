import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

export const projectRoot = path.resolve(import.meta.dirname, '../..');
export function sourceIdentity() {
  const files = [];
  function walk(relative) {
    const full = path.join(projectRoot, relative);
    for (const entry of readdirSync(full, { withFileTypes: true })) {
      if (['node_modules', '.npm-cache', 'data', '.dart_tool', 'build', '.git', '.idea'].includes(entry.name)) continue;
      const child = `${relative}/${entry.name}`;
      if (entry.isDirectory()) walk(child);
      else files.push(child);
    }
  }
  walk('backend'); walk('flutter_web');
  const entries = files.sort().map(file => ({ file, sha256: createHash('sha256').update(readFileSync(path.join(projectRoot, file))).digest('hex') }));
  return { source_sha256: createHash('sha256').update(JSON.stringify(entries)).digest('hex'), files: entries };
}
export function newEvidenceFolder(kind) {
  const folder = path.join(projectRoot, 'evidence', kind, new Date().toISOString().replace(/[:.]/g, '-'));
  mkdirSync(folder, { recursive: true });
  return folder;
}
export const jsonFile = (filename, value) => writeFileSync(filename, `${JSON.stringify(value, null, 2)}\n`);
export function environment() {
  return { recorded_at: new Date().toISOString(), display_timezone: 'Asia/Manila', timestamp_basis: 'Actual execution clock in UTC; dates may precede PHT by eight hours.', node: process.version, platform: process.platform, os_release: os.release(), architecture: process.arch, ...sourceIdentity() };
}

import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

export class Logger {
  constructor(filename, quiet = false) {
    this.filename = filename;
    this.quiet = quiet;
    this.failed = false;
    this.events = [];
    mkdirSync(path.dirname(filename), { recursive: true });
    if (existsSync(filename)) {
      for (const line of readFileSync(filename, 'utf8').split('\n').filter(Boolean).slice(-500)) {
        try { this.events.push(JSON.parse(line)); } catch { /* Preserve damaged source line; report below. */ this.damaged = true; }
      }
    }
    appendFileSync(filename, '');
    if (this.damaged) this.emit('log_gap_detected', { level: 'warn', source: 'system', reason: 'Invalid historical JSON line retained in source file.' });
  }
  emit(event, fields = {}) {
    const item = { timestamp: new Date().toISOString(), level: 'info', source: 'system', correlation_id: randomUUID(), ...fields, event };
    const line = JSON.stringify(item);
    try { appendFileSync(this.filename, `${line}\n`); }
    catch (error) { this.failed = true; process.stderr.write(`${JSON.stringify({ ...item, event: 'log_write_failed', level: 'error' })}\n`); throw error; }
    this.events.push(item);
    if (this.events.length > 500) this.events.shift();
    if (!this.quiet) process.stdout.write(`${line}\n`);
    return item;
  }
  recent(limit, correlation) { return this.events.filter(x => !correlation || x.correlation_id === correlation).slice(-limit).reverse(); }
}

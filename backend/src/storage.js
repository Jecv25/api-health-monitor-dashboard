import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

export class Storage {
  constructor(filename) {
    mkdirSync(path.dirname(filename), { recursive: true });
    this.db = new DatabaseSync(filename);
    this.db.exec(`
      PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=3000;
      CREATE TABLE IF NOT EXISTS endpoints (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL UNIQUE,
        interval_seconds INTEGER NOT NULL CHECK(interval_seconds BETWEEN 10 AND 3600),
        demo_behavior TEXT NOT NULL CHECK(demo_behavior IN ('stable','flaky','dead','broken')),
        status TEXT NOT NULL DEFAULT 'UNKNOWN', created_at TEXT NOT NULL,
        last_completed_at TEXT, next_due_at TEXT
      );
      CREATE TABLE IF NOT EXISTS runs (
        id INTEGER PRIMARY KEY, endpoint_id INTEGER NOT NULL REFERENCES endpoints(id),
        trigger TEXT NOT NULL, state TEXT NOT NULL, correlation_id TEXT NOT NULL,
        parent_correlation_id TEXT, schedule_key TEXT UNIQUE, behavior TEXT NOT NULL,
        started_at TEXT NOT NULL, finished_at TEXT, interruption_reason TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS one_running_check ON runs(endpoint_id) WHERE state='RUNNING';
      CREATE TABLE IF NOT EXISTS attempts (
        id INTEGER PRIMARY KEY, check_id INTEGER NOT NULL REFERENCES runs(id), ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 1 AND 3),
        started_at TEXT NOT NULL, finished_at TEXT NOT NULL, status_code INTEGER,
        error_category TEXT, latency_ms REAL NOT NULL, UNIQUE(check_id,ordinal)
      );
      CREATE TABLE IF NOT EXISTS results (
        id INTEGER PRIMARY KEY, check_id INTEGER NOT NULL UNIQUE REFERENCES runs(id),
        endpoint_id INTEGER NOT NULL REFERENCES endpoints(id), ok INTEGER NOT NULL,
        attempt_count INTEGER NOT NULL, final_category TEXT NOT NULL, completed_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS incidents (
        id INTEGER PRIMARY KEY, endpoint_id INTEGER NOT NULL REFERENCES endpoints(id),
        state TEXT NOT NULL, reason TEXT NOT NULL, opening_check_id INTEGER NOT NULL REFERENCES runs(id),
        opened_at TEXT NOT NULL, acknowledged_by TEXT, acknowledged_at TEXT,
        recovery_check_id INTEGER REFERENCES runs(id), recovered_at TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS one_active_incident ON incidents(endpoint_id) WHERE state IN ('OPEN','ACKNOWLEDGED');
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY, incident_id INTEGER NOT NULL REFERENCES incidents(id),
        check_id INTEGER NOT NULL REFERENCES runs(id), event TEXT NOT NULL,
        audience TEXT NOT NULL DEFAULT 'support', channel TEXT NOT NULL DEFAULT 'in_app_demo',
        created_at TEXT NOT NULL, UNIQUE(incident_id,event)
      );
      CREATE TABLE IF NOT EXISTS idempotency (
        scope TEXT NOT NULL, key TEXT NOT NULL, payload_hash TEXT NOT NULL,
        status INTEGER NOT NULL, response TEXT NOT NULL, PRIMARY KEY(scope,key)
      );
      CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    `);
  }
  get(sql, ...args) { return this.db.prepare(sql).get(...args); }
  all(sql, ...args) { return this.db.prepare(sql).all(...args); }
  run(sql, ...args) { return this.db.prepare(sql).run(...args); }
  transaction(fn) {
    this.db.exec('BEGIN IMMEDIATE');
    try { const value = fn(); this.db.exec('COMMIT'); return value; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  close() { this.db.close(); }
}

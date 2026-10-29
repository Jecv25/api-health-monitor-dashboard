import { existsSync } from 'node:fs';
import path from 'node:path';

export const backendRoot = path.resolve(import.meta.dirname, '..');
const envFile = path.join(backendRoot, '.env');
if (existsSync(envFile)) process.loadEnvFile(envFile);

function integer(value, fallback, min, max, name) {
  const raw = value ?? String(fallback);
  if (!/^\d+$/.test(String(raw))) throw new Error(`Invalid ${name}`);
  const number = Number(raw);
  if (!Number.isSafeInteger(number) || number < min || number > max) throw new Error(`Invalid ${name}`);
  return number;
}

export function config(overrides = {}) {
  const c = {
    host: process.env.APP_HOST ?? '127.0.0.1',
    port: integer(process.env.PORT, 3000, 0, 65535, 'PORT'),
    fixtureHost: process.env.FIXTURE_HOST ?? '127.0.0.1',
    fixturePort: integer(process.env.FIXTURE_PORT, 4001, 0, 65535, 'FIXTURE_PORT'),
    startFixture: process.env.START_FIXTURE !== 'false',
    flutterOrigin: process.env.FLUTTER_ORIGIN ?? 'http://localhost:8080',
    dbPath: path.resolve(backendRoot, process.env.DB_PATH ?? './data/monitor.sqlite'),
    logPath: path.resolve(backendRoot, process.env.LOG_PATH ?? './data/monitor.jsonl'),
    tickMs: integer(process.env.SCHEDULER_TICK_MS, 1000, 10, 60000, 'SCHEDULER_TICK_MS'),
    concurrency: integer(process.env.MAX_CONCURRENT_CHECKS, 2, 1, 2, 'MAX_CONCURRENT_CHECKS'),
    timeoutMs: integer(process.env.CHECK_TIMEOUT_MS, 3000, 10, 3000, 'CHECK_TIMEOUT_MS'),
    maxAttempts: integer(process.env.MAX_ATTEMPTS, 3, 1, 3, 'MAX_ATTEMPTS'),
    retryDelayMs: integer(process.env.RETRY_DELAY_MS, 700, 1, 60000, 'RETRY_DELAY_MS'),
    seed: process.env.SEED_DATA !== 'false',
    demoMode: process.env.DEMO_MODE !== 'false',
    quiet: false,
    webRoot: path.resolve(backendRoot, '../flutter_web/build/web'),
    ...overrides,
  };
  if (c.host !== '127.0.0.1' || c.fixtureHost !== '127.0.0.1' || !c.demoMode) {
    throw new Error('This Module 13 demo requires loopback hosts and DEMO_MODE=true.');
  }
  if (c.maxAttempts < 1 || c.maxAttempts > 3 || c.concurrency < 1 || c.concurrency > 2) {
    throw new Error('Invalid execution bound.');
  }
  const origin = new URL(c.flutterOrigin);
  if (!['localhost', '127.0.0.1'].includes(origin.hostname) || origin.protocol !== 'http:') {
    throw new Error('FLUTTER_ORIGIN must be a local HTTP origin.');
  }
  return c;
}

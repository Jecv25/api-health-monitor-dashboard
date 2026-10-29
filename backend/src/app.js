import express from 'express';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';
import { existsSync } from 'node:fs';
import { config } from './config.js';
import { Storage } from './storage.js';
import { Logger } from './logger.js';
import { Monitor } from './monitor.js';
import { startFixture } from './fixture.js';
import { ApiError, behaviors, fail, limitValue, objectBody, positiveId, registration } from './errors.js';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}

export async function createRuntime(overrides = {}) {
  const c = config(overrides);
  const logger = new Logger(c.logPath, c.quiet);
  const store = new Storage(c.dbPath);
  let fixture;
  try {
    if (c.startFixture) { fixture = await startFixture({ host: c.fixtureHost, port: c.fixturePort, logger }); c.fixturePort = fixture.port; }
  } catch (error) { store.close(); throw error; }
  const monitor = new Monitor(store, logger, c);
  const app = express();
  app.disable('x-powered-by');
  const sessions = new Map();
  const log = (event, fields) => monitor.log(event, fields);

  app.use((req, res, next) => {
    req.correlationId = randomUUID();
    res.set('X-Correlation-ID', req.correlationId);
    res.set('Cache-Control', 'no-store');
    const origin = req.get('Origin');
    if (origin === c.flutterOrigin) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Access-Control-Allow-Credentials', 'true');
      res.set('Vary', 'Origin');
      res.set('Access-Control-Expose-Headers', 'X-Correlation-ID,Idempotency-Replayed,Location');
    }
    if (req.method === 'OPTIONS') {
      if (origin && origin !== c.flutterOrigin) return res.sendStatus(403);
      res.set('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
      res.set('Access-Control-Allow-Headers', 'Content-Type,Idempotency-Key');
      return res.sendStatus(204);
    }
    next();
  });
  app.use('/api/v1', (req, res, next) => {
    const sessionRoute = req.path === '/demo/session';
    const cookie = req.headers.cookie?.split(';').map(x => x.trim()).find(x => x.startsWith('demo_session='))?.slice(13);
    req.demoSession = cookie ? sessions.get(cookie) : undefined;
    req.demoCookie = cookie;
    if (sessionRoute && ['POST', 'DELETE'].includes(req.method)) return next();
    if (!req.demoSession) {
      log('authorization_denied', { source: 'api', correlation_id: req.correlationId, status_code: 401, method: req.method });
      return next(new ApiError(401, 'SESSION_REQUIRED', 'Select a local demo persona to continue.'));
    }
    if (!['GET', 'HEAD'].includes(req.method) && req.demoSession.persona !== 'operator') {
      log('authorization_denied', { source: 'api', correlation_id: req.correlationId, actor_id: req.demoSession.actor, status_code: 403, method: req.method });
      return next(new ApiError(403, 'FORBIDDEN', 'This demo persona can read records but cannot change them.'));
    }
    next();
  });
  app.use('/api/v1', (req, res, next) => {
    if (['POST', 'PATCH'].includes(req.method) && !req.is('application/json')) return next(new ApiError(415, 'JSON_REQUIRED', 'Use application/json.'));
    next();
  }, express.json({ limit: '16kb' }));

  const send = (req, res, data, status = 200) => res.status(status).json({ data, correlation_id: req.correlationId });
  function mutate(req, res, input, operation) {
    const key = req.get('Idempotency-Key');
    if (!key || !uuidPattern.test(key)) fail(422, 'IDEMPOTENCY_KEY_REQUIRED', 'Supply a UUID Idempotency-Key header.');
    const scope = `${req.demoSession.actor}|${req.method}|${req.path}`;
    const hash = createHash('sha256').update(JSON.stringify(canonical(input))).digest('hex');
    let replay = false;
    const outcome = store.transaction(() => {
      const old = store.get('SELECT * FROM idempotency WHERE scope=? AND key=?', scope, key);
      if (old) {
        if (old.payload_hash !== hash) fail(409, 'IDEMPOTENCY_CONFLICT', 'That idempotency key was accepted with a different payload.');
        replay = true;
        return { status: old.status, body: JSON.parse(old.response) };
      }
      if (logger.failed || monitor.lastError) fail(503, 'AUTOMATION_PAUSED', 'Repair local storage/logging and restart the backend before changing records.');
      const result = operation();
      const body = { data: result.data, correlation_id: req.correlationId };
      store.run('INSERT INTO idempotency(scope,key,payload_hash,status,response) VALUES(?,?,?,?,?)', scope, key, hash, result.status, JSON.stringify(body));
      return { ...result, body };
    });
    if (replay) res.set('Idempotency-Replayed', 'true');
    if (outcome.location) res.set('Location', outcome.location);
    // Post-commit logging may fail. Preserve the committed replay record so the caller can reconcile.
    outcome.after?.();
    return res.status(outcome.status).json(outcome.body);
  }

  const api = express.Router();
  api.post('/demo/session', (req, res) => {
    objectBody(req.body, ['persona']);
    if (!['operator', 'viewer'].includes(req.body.persona)) fail(422, 'VALIDATION_ERROR', 'Select operator or viewer.');
    if (req.demoCookie) sessions.delete(req.demoCookie);
    const token = randomUUID();
    const session = { persona: req.body.persona, actor: `demo-${req.body.persona}`, capabilities: req.body.persona === 'operator' ? ['read', 'mutate'] : ['read'] };
    sessions.set(token, session);
    res.cookie('demo_session', token, { httpOnly: true, sameSite: 'lax', path: '/api/v1' });
    log('demo_session_selected', { source: 'api', correlation_id: req.correlationId, actor_id: session.actor });
    send(req, res, session);
  });
  api.get('/demo/session', (req, res) => send(req, res, req.demoSession));
  api.delete('/demo/session', (req, res) => {
    if (req.demoCookie) sessions.delete(req.demoCookie);
    res.clearCookie('demo_session', { path: '/api/v1' });
    res.status(204).end();
  });
  api.get('/endpoints', (req, res) => send(req, res, monitor.endpoints()));
  api.post('/endpoints', (req, res) => {
    const input = registration(req.body);
    mutate(req, res, input, () => monitor.register(input, req.correlationId));
  });
  api.get('/endpoints/:id', (req, res) => send(req, res, monitor.endpoint(positiveId(req.params.id))));
  api.post('/endpoints/:id/checks', (req, res) => {
    objectBody(req.body, []);
    const id = positiveId(req.params.id);
    mutate(req, res, {}, () => monitor.trigger(id, req.correlationId));
  });
  api.post('/checks/run-all', (req, res) => {
    objectBody(req.body, []);
    mutate(req, res, {}, () => monitor.runAll(req.correlationId));
  });
  api.get('/checks/:id', (req, res) => send(req, res, monitor.runView(positiveId(req.params.id))));
  api.get('/endpoints/:id/results', (req, res) => send(req, res, monitor.results(positiveId(req.params.id), limitValue(req.query.limit))));
  api.patch('/endpoints/:id/demo-behavior', (req, res) => {
    objectBody(req.body, ['demo_behavior']);
    if (!behaviors.includes(req.body.demo_behavior)) fail(422, 'VALIDATION_ERROR', 'Select a supported demo behavior.');
    const id = positiveId(req.params.id);
    mutate(req, res, req.body, () => monitor.changeBehavior(id, req.body.demo_behavior, req.correlationId));
  });
  api.get('/scheduler', (req, res) => send(req, res, monitor.scheduler()));
  for (const [action, enabled] of [['start', true], ['stop', false]]) api.post(`/scheduler/${action}`, (req, res) => {
    objectBody(req.body, []);
    mutate(req, res, {}, () => monitor.setScheduler(enabled, req.correlationId));
  });
  api.get('/incidents', (req, res) => {
    const state = req.query.state;
    if (state !== undefined && !['active', 'OPEN', 'ACKNOWLEDGED', 'RECOVERED'].includes(state)) fail(422, 'VALIDATION_ERROR', 'Unknown incident-state filter.');
    const rows = state === 'active' ? store.all("SELECT * FROM incidents WHERE state IN ('OPEN','ACKNOWLEDGED') ORDER BY id DESC") : state ? store.all('SELECT * FROM incidents WHERE state=? ORDER BY id DESC', state) : store.all('SELECT * FROM incidents ORDER BY id DESC');
    send(req, res, rows);
  });
  api.post('/incidents/:id/acknowledge', (req, res) => {
    objectBody(req.body, []);
    const id = positiveId(req.params.id);
    mutate(req, res, {}, () => monitor.acknowledge(id, req.demoSession.actor, req.correlationId));
  });
  api.get('/notifications', (req, res) => send(req, res, store.all('SELECT * FROM notifications ORDER BY id DESC LIMIT ?', limitValue(req.query.limit))));
  api.get('/reports/uptime', (req, res) => send(req, res, monitor.uptime()));
  api.get('/logs', (req, res) => {
    const correlation = req.query.correlation_id;
    if (correlation !== undefined && (typeof correlation !== 'string' || !uuidPattern.test(correlation))) fail(422, 'VALIDATION_ERROR', 'Invalid correlation ID.');
    send(req, res, logger.recent(limitValue(req.query.limit, 100, 200), correlation));
  });
  api.use((req, res) => fail(404, 'NOT_FOUND', 'API route not found.'));
  app.use('/api/v1', api);
  if (existsSync(c.webRoot)) {
    app.use(express.static(c.webRoot));
    app.get(/.*/, (req, res) => res.sendFile(path.join(c.webRoot, 'index.html')));
  } else app.get('/', (req, res) => res.type('text').send('Module 13 API running. Build flutter_web to serve the dashboard here.'));
  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);
    let status = error.status ?? 500;
    let code = error.code ?? 'INTERNAL_ERROR';
    let message = error instanceof ApiError ? error.message : 'The server could not complete the request. Please retry with the same mutation key.';
    if (error.type === 'entity.parse.failed') { status = 400; code = 'INVALID_JSON'; message = 'The JSON body is malformed.'; }
    else if (error.type === 'entity.too.large') { status = 413; code = 'REQUEST_TOO_LARGE'; message = 'The request is too large.'; }
    else if (String(error.code).startsWith('ERR_SQLITE') || logger.failed) { status = 503; code = logger.failed ? 'LOG_UNAVAILABLE' : 'STORAGE_UNAVAILABLE'; message = 'Local storage/logging is unavailable. Automation is paused.'; monitor.pause(error, null); }
    if (status >= 500 && !(error instanceof ApiError)) monitor.pause(error, null);
    try { logger.emit('request_rejected', { source: 'api', correlation_id: req.correlationId, level: status >= 500 ? 'error' : 'warn', status_code: status, error_category: code }); } catch { /* Console fallback already emitted. */ }
    res.status(status).json({ error: { code, message, ...(error.fields ? { fields: error.fields } : {}) }, correlation_id: req.correlationId });
  });
  return { app, store, logger, monitor, fixture, config: c, async close() { await monitor.close(); await fixture?.close(); store.close(); } };
}

export async function listenRuntime(overrides = {}) {
  const runtime = await createRuntime(overrides);
  try {
    runtime.server = await new Promise((resolve, reject) => { const server = runtime.app.listen(runtime.config.port, runtime.config.host, () => resolve(server)); server.once('error', reject); });
  } catch (error) { await runtime.close(); throw error; }
  runtime.url = `http://127.0.0.1:${runtime.server.address().port}`;
  const close = runtime.close.bind(runtime);
  runtime.close = async () => { await new Promise(resolve => runtime.server.close(resolve)); await close(); };
  runtime.logger.emit('api_listening', { port: runtime.server.address().port });
  return runtime;
}

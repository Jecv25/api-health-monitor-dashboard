import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { config } from './config.js';
import { Logger } from './logger.js';

export async function startFixture({ host = '127.0.0.1', port = 4001, logger, delayMs = 0 } = {}) {
  let faultDelay = delayMs;
  const server = http.createServer((req, res) => {
    const behavior = req.headers['x-demo-behavior'];
    const ordinal = Number(req.headers['x-attempt']);
    const valid = req.method === 'GET' && /^\/[a-z][a-z0-9-]{0,39}\/health$/.test(req.url ?? '');
    const status = !valid || behavior === 'broken' ? 404 : behavior === 'dead' || (behavior === 'flaky' && ordinal < 3) ? 503 : 200;
    const fields = {
      source: 'fixture', correlation_id: req.headers['x-correlation-id'], check_id: Number(req.headers['x-check-id']),
      attempt: ordinal, behavior, path: req.url, transport: 'loopback_http', injected_delay_ms: faultDelay,
    };
    try { logger?.emit('fixture_request', fields); }
    catch { res.destroy(); return; }
    const respond = () => {
      if (res.destroyed) return;
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ fictional: true, status }));
      try { logger?.emit('fixture_response', { ...fields, status_code: status }); } catch { /* Logger already signals failure. */ }
    };
    if (faultDelay) { const timer = setTimeout(respond, faultDelay); timer.unref(); req.on('close', () => { if (res.destroyed) clearTimeout(timer); }); }
    else respond();
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
  return {
    server, port: server.address().port,
    setDelay(ms) { faultDelay = ms; logger?.emit('fixture_fault_injected', { source: 'fixture', injected_delay_ms: ms }); },
    async close() { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); },
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const c = config();
  const logger = new Logger(c.logPath, c.quiet);
  const fixture = await startFixture({ host: c.fixtureHost, port: c.fixturePort, logger, delayMs: Number(process.env.FIXTURE_DELAY_MS ?? 0) });
  logger.emit('fixture_listening', { port: fixture.port });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await fixture.close(); process.exit(0); });
}

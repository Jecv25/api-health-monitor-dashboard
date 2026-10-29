import { listenRuntime } from './app.js';

try {
  const runtime = await listenRuntime();
  process.stdout.write(`\nModule 13 dashboard/API: http://localhost:${runtime.server.address().port}\nLocal demo only. Scheduler starts OFF.\n`);
  let closing = false;
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
    if (closing) return;
    closing = true;
    await runtime.close();
    process.exit(0);
  });
} catch (error) {
  process.stderr.write(`Startup refused: ${error.code ?? error.message}\n`);
  process.exitCode = 1;
}

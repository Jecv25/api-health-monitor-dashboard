# Backend — Module 13

Node.js 24.x + Express + native SQLite. No database server or native npm SQLite addon is required. `npm.cmd ci` installs the locked npm dependencies; `npm.cmd start` starts the loopback API and its local HTTP fixture. The backend also serves `../flutter_web/build/web` when it exists. Browser address: `http://localhost:3000` with default configuration.

## Configuration

Copy `.env.example` to `.env` only when overriding defaults. Paths in `.env` resolve relative to `backend/`. `.env` is ignored; the example has no credentials. `DEMO_MODE=true`, loopback hosts, at most two concurrent checks, and at most three attempts are enforced. Invalid environment values refuse startup. The usual policy is 3,000 ms timeout, 700 ms retry delay, 1,000 ms dispatcher tick, and interval 60 seconds. Unit tests may explicitly override bounds within these limits and record their configuration.

Default data is in `backend/data/monitor.sqlite` and `backend/data/monitor.jsonl`. Seed registration happens only when the endpoint table is empty; it never invents results. Restart preserves data, invalidates in-memory demo sessions, marks leftover running checks INTERRUPTED, and leaves scheduling OFF.

| File | Responsibility |
| --- | --- |
| `src/app.js` | API/session boundaries, idempotent mutation transactions, safe errors, local static client hosting |
| `src/monitor.js` | Due-time dispatcher, GET attempts/retry, result/incident/notification finalization, uptime |
| `src/storage.js` | Parameterized SQL, schema, constraints, synchronous transaction boundary |
| `src/fixture.js` | Real loopback HTTP dependency with controlled response modes |
| `src/config.js` | Nonsecret configuration and execution-bound validation |
| `src/errors.js` | Authoritative field/type/range/URL validation |
| `src/logger.js` | Sanitized JSON-lines append and recent-event view |

See [the API contract](../docs/api-contract.md) for routes and fields. All domain mutations need an operator demo session and UUID `Idempotency-Key`; reads need a demo session. Missing session gives 401, viewer mutation 403, invalid data 422, malformed JSON 400, wrong content type 415, duplicate/active conflict 409, and capacity/storage error 503. Cookies and raw payloads are not logged.

Idempotency reserves changes and the accepted response atomically. Repeating the same method/route/actor/key/payload returns the original status/body; the new HTTP request has a new correlation header. Replays remain readable during an automation pause if SQLite is accessible. A changed payload under that key is 409. Run results are inspected separately after the asynchronous 202 response.

The local fixture accepts only server-supplied run/attempt metadata. Registered labels use the fixed fictional namespace; checks use the fixed fixture origin and do not follow redirects. `START_FIXTURE=false` supports a separately started `npm.cmd run fixture`. Stopping that listener or setting its nonsecret `FIXTURE_DELAY_MS` above 3,000 permits manual dependency-failure injection. The evidence harness also controls fixture delay directly and injects a one-shot transaction failure through an internal test hook; those controls have no public fault-injection API.

## Checks and recovery

`npm.cmd test` runs ten focused tests. `npm.cmd run verify` captures tests, analysis, and Flutter build output. Other evidence commands are listed in the root README. Every evidence run uses its own database/log path and ephemeral ports, with real timestamps and source-file hashes. Runtime JSONL and actual SQLite snapshots are retained.

Use [the runbook](../docs/recovery-runbook.md) for recovery. Stop dispatch before maintenance, preserve files, and use a consistent SQLite backup or stop the process before copying database/WAL/SHM files. Never delete a failed record to clean the demonstration. A result-finalization/log failure pauses further automation; repair and restart before new work. Acknowledgement and fixture repair cannot bypass a new passing observation.

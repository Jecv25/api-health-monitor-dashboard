# Recovery runbook

Status: runbook for the implemented Module 13 local demo. Start the backend with `npm.cmd start` in `backend/`; use the root README for setup. Actual screenshots/logs and fault/restart runs are linked from [the evidence index](../evidence/evidence-index.md). Use fictional records and the fixed local fixture; do not test production services.

## Ownership and first response

The demo operator owns incident acknowledgement and injected repair. The student maintainer owns the process, configuration, fixture, SQLite, logs, and evidence preservation. If the cause cannot be safely corrected in the lab, stop automatic dispatch, preserve the record, and leave the incident unresolved for human review. Do not repeatedly change configuration to make a result appear successful.

Before intervention, record the actual timestamp with timezone, build/revision identity, environment and runtime versions, endpoint/incident/run IDs, current state, correlation ID, and the visible error. Copy relevant JSON log lines and requests/responses without cookies or secret values. Record the predicted outcome before rerunning. Existing failure records stay intact.

## A. Transient dependency failure recovered by retry

1. Select the fictional Enrollment API or another endpoint with `flaky` behavior. Stop scheduling when a deterministic single-run demonstration is needed; let any active runs finish.
2. Predict two 503 responses, two retry waits, then a 200 on attempt three. Submit one manual check using a new idempotency key.
3. Observe the returned run until completed. Inspect the three saved attempts, actual latencies, wait gaps, one passed final result, `transient_recovered`, and `UP` status.
4. If there was no active incident before the run, confirm none was created. If one was active, confirm it recovered with exactly one recovery notice.
5. Record actual results and any discrepancy. Do not manufacture an incident just to make the transient demo resemble an outage.

## B. Persistent outage or non-retryable path failure

1. For persistent outage, select `dead`; predict three 503s and a failed final result. For `broken`, predict one 404, no retry, and a failed result.
2. Run the check and inspect its incident. Confirm one `OPEN` incident and one opening in-app support notice. The cause is either `retry_exhausted` or `non_retryable_http`, not an unsupported diagnosis of the external service.
3. Acknowledge using the operator session. Confirm `ACKNOWLEDGED`, the fictional actor/time, unchanged `DOWN` health, and no recovery notice.
4. Repeat a failed check if verifying incident deduplication. Confirm the existing active incident remains the only active incident and no second opening notice appears.
5. Examine the fixture mode/path and actual attempt errors. Keep the original failed runs. A 404 requires a person to examine the path/fixture; more retries are not the remedy.

## C. Repair and verify recovery

1. Record the repair decision and time. In this lab, use Simulate fix to change future-run behavior to `stable`. An active run keeps its old behavior snapshot.
2. Confirm the endpoint remains `DOWN` and the incident remains active immediately after the change. Repair selection alone must not count as recovery.
3. Start a new check or wait for the next scheduled check. Confirm a real 2xx response, one committed passed result, endpoint `UP`, and the same incident changing to `RECOVERED` with a linked recovery run/time.
4. Confirm exactly one persisted recovery support notice and the matching `recovery_verified` event. Inspect the notice through the UI/API; a toast alone is insufficient.
5. Review the uptime summary. Earlier failed checks remain in the denominator. Re-enable scheduling only if the operator intends continued observation.
6. Record expected and actual behavior, timings, requests/responses, and identifiers. If the verification fails, preserve that failure and continue investigation under the same active incident.

## D. Duplicate request or uncertain browser outcome

1. If a mutation's response is lost, retain its original idempotency key and exact payload.
2. Retry the same method/route/key/payload. Expect the original accepted response and a replay marker, then inspect the referenced endpoint/run/incident.
3. A changed payload under that key is 409; intentionally different work needs a new key. A different key while a check is active is 409 with the active run ID.
4. Do not repeatedly press Run all to build a hidden queue. Its response lists accepted, busy, and capacity-blocked endpoints. Retry unaccepted work deliberately after slots free.

## E. Backend crash, restart, or interrupted run

1. Preserve existing database and log files before repair; never delete them to reset the demonstration. If taking a backup while the process is running, use a SQLite-consistent backup; otherwise stop the process before copying its database and any WAL/SHM companion files.
2. Restore the process using validated local configuration. Expect scheduling to start disabled and sessions to require reselection.
3. Before new work, confirm old `RUNNING` rows were marked `INTERRUPTED`, their saved attempts remain, and affected endpoints show `UNKNOWN`. Interrupted runs have no invented final result and do not alter uptime counts or recover incidents.
4. Sign into the demo placeholder again, submit a new check with a new key, and verify its actual result. Replaying the original trigger key points to the original interrupted run; it must not execute it again.
5. After reconciliation, the operator may start the scheduler. There is no catch-up burst or claim of checks during downtime. Record the outage gap and startup events.

## F. Database, log, or fixture unavailability

| Failure | Expected signal and safe action | Return-to-service check |
| --- | --- | --- |
| Fixture listener stopped/refusing connections or intentionally timing out | Retryable dependency error, maximum three attempts; failed completed run opens/reuses an incident | Restore the local fixture, perform a new passing run, then verify incident recovery |
| Database unavailable or result transaction fails | Safe 503 storage error where possible; dispatch pauses; no partial recovery/result/notice is claimed | Maintainer repairs access/storage, reconciles unfinished runs, verifies a new write/check, then operator restarts scheduling |
| Log file cannot be written | Console/visible error; pause new automation and preserve committed DB state; do not claim file-log completeness | Repair local path/permissions, record the gap, verify a real append, reconcile state before resuming |
| Invalid startup configuration | Startup refuses to run checks | Correct nonsecret configuration; verify reported effective policy before dispatch |

Do not retry database writes indefinitely, reset the dataset, suppress the error, or turn a storage failure into a dependency incident. If finalization status is uncertain, inspect the committed run before making another decision.

## Evidence handoff and unresolved limitations

Stage 4 must retain original requests, expected outcomes written before execution, actual outcomes, timestamps, logs, injection settings, and before/after database/UI observations. An improvement gets a new rerun record linked to the original failure plus a small regression set. Use `NOT RUN` until an execution actually occurs; use `FAIL` when actual differs from expected.

Backup evidence is a previously captured, clearly dated recording/log set for the same identified build; it is not a live demo. Remaining limitations include selectable demo identities, loopback HTTP fixture transport, no offline monitoring or distributed worker, one-check recovery threshold, separate DB/log sinks, and no external notification delivery.

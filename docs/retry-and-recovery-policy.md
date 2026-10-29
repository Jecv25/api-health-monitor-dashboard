# Retry and recovery policy

Status: implemented Module 13 policy. Actual attempts, gaps, timings, outages, rollback, and restart proof are in [the evidence index](../evidence/evidence-index.md). Related: [trigger contract](pattern-matrix.md), [API contract](api-contract.md), [runbook](recovery-runbook.md).

## Execution bounds and failure taxonomy

One check is one logical observation with **at most three total HTTP attempts**, including the first. It has at most two retry waits. Use GET only; discard response bodies and do not follow redirects. Each request has a 3,000 ms timeout covering connection and response headers. The controlled fixture sends small responses without streaming bodies.

| Category | Examples | Action | Saved/visible outcome |
| --- | --- | --- | --- |
| Healthy | HTTP 200–299 | Stop immediately | One passed final result; endpoint `UP` |
| Retryable dependency failure | Timeout, refused/reset connection, HTTP 408, 429, 500, 502, 503, 504 | Retry only while attempt count is below three | Attempt failures retained; final success or retry exhaustion |
| Non-retryable dependency failure | HTTP 3xx, 400, 401, 403, 404, 405, other statuses outside the explicit retry list | Stop after the observed attempt | One failed result and active incident requiring a person |
| Invalid registration/request | Bad fields, malformed JSON, invalid identifier | Reject before dispatch | API 400/422; no endpoint/run/result/incident mutation |
| Unauthorized/forbidden action | No demo session / viewer requests a mutation | Reject before dispatch | API 401/403; no domain mutation |
| Duplicate/conflicting action | Replayed key, changed payload with same key, active endpoint check | Replay accepted response or reject conflict | No duplicate work or active incident |
| Monitoring-system failure | SQLite unavailable, failed result transaction, invalid startup config | Fail closed; pause dispatch; do not claim saved success | Safe API/storage error; unresolved/interrupted run is visible after reconciliation |
| Process interruption | Crash or termination during a run | On restart mark unfinished run `INTERRUPTED`; require a new observation | Preserve attempts; no invented pass/fail result or recovery |

Dependency HTTP 401/403 is a failed **dependency check**, not an API-login error. API 401/403 rejects the caller before any dependency request. Logs distinguish `source: dependency` from `source: api`.

The fixture modes from the prototype are: `stable` = 200; `flaky` = 503, 503, 200 per run; `dead` = 503 on every attempt; `broken` = 404. Controlled timeout/refusal injection is also required for checking transport failure handling. Fixture control is limited to the local demo operator and is recorded.

## Retry timing

After an unsuccessful retryable attempt, persist the attempt, emit `retry_scheduled`, and wait at least 700 ms before the next request. No wait follows the final attempt or a non-retryable response. Success stops the loop immediately. Attempts are sequential within one run.

The configured HTTP-plus-wait budget is `3 × 3,000 + 2 × 700 = 10,400 ms` in a timeout-only run. This excludes dispatch, SQLite, logging, and event-loop overhead; it is not an observed runtime or hard real-time guarantee. Actual elapsed duration and gap measurements must be retained. A quick 503 response does not pretend to have taken 3,000 ms as it does in the browser simulator.

Keep the prototype's fixed delay for a predictable two-worker lab. Exponential backoff/jitter and circuit breaking are alternatives recorded in decision D3. The fixture does not emit `Retry-After`; support for real provider throttling policies is outside this design. No automatic retry applies to invalid input, authorization failures, or an uncommitted storage operation. The client must not blindly resend mutations with fresh idempotency keys.

## Persistence and idempotency

1. Validate the caller and input. For every domain mutation, require a UUID `Idempotency-Key`. Scope it by server-side demo actor, HTTP method, and concrete route. Normalize the accepted payload before hashing it. Login/logout are excluded.
2. A repeat with the same scope, key, and payload returns the original accepted status/body, with `Idempotency-Replayed: true`. A changed payload under the same scope/key returns 409 `IDEMPOTENCY_CONFLICT`. A check replay returns its original 202/run ID even after completion; the client reads that run for current state. Rejected requests do not create accepted-operation records.
3. Reserve a running check and available capacity in a transaction before the HTTP call. Commit the accepted response/idempotency record in that same transaction; other domain mutations likewise commit their change and replay record together. A unique idempotency scope/key prevents concurrent copies from both being accepted. Enforce one active run per endpoint, a unique scheduler occurrence key, and two total accepted/running slots. A different manual key during an active run returns 409 `CHECK_IN_PROGRESS`; global capacity exhaustion returns 503 `CAPACITY_BUSY`. Both leave no pending run.
4. Persist each real attempt before scheduling another. If an attempt cannot be saved, stop execution and pause dispatch. Never continue external work after losing the audit/storage boundary.
5. On completion, one transaction inserts the unique final result, updates endpoint state/next due time, completes the run, and opens or recovers an incident plus its support notice if needed. Failure rolls back the entire finalization. Release capacity only after finalization or explicit interruption reconciliation.
6. Store a maximum of one active incident per endpoint with a database constraint covering `OPEN` and `ACKNOWLEDGED`. Repeat failure logs `incident_already_open` without another opening notice. Repeated acknowledgement of an acknowledged incident preserves the original actor/time. A recovered incident cannot be acknowledged again.

Accepted mutation records persist for the lab dataset, including across demo sessions and process restarts. Demo actor IDs are fixed fictional identifiers, not cookie values. The lab does not promise exactly-once external delivery: a crash can occur after a GET response but before its attempt is saved. Startup marks the run interrupted; a subsequent run may make another GET. No side-effecting dependency methods are allowed.

## Incident and recovery rules

| Condition | Transition | Human/notification behavior |
| --- | --- | --- |
| Completed failed check, no active incident | Create `OPEN` incident | Persist one opening support notice; operator reviews cause |
| Completed failed check, active incident exists | Keep `OPEN` or `ACKNOWLEDGED` | Preserve acknowledgement; append result, no duplicate incident/notice |
| Operator acknowledges `OPEN` | `OPEN` → `ACKNOWLEDGED` | Record server-derived fictional actor/time; health stays `DOWN` |
| Operator changes behavior to stable | No incident or health transition | This is an injected repair, not proof of recovery |
| Completed passing check, active incident exists | `OPEN` or `ACKNOWLEDGED` → `RECOVERED` | Link passing run, set recovery time, persist one recovery support notice |
| Completed passing check, no active incident | No incident | Endpoint `UP`; if attempts > 1, log `transient_recovered` |
| Failed check after previous incident recovered | Create a new `OPEN` incident | Preserve older history; new outage gets its own notice |

The transient 503→503→200 demo produces a passed result and no incident if none was active. Recovery of an active incident requires a completed passing run, even if nobody acknowledged it. There is no manual “mark recovered” shortcut. One passing run is the lab's recovery threshold; sustained recovery and flapping suppression remain limitations.

In-app notices are committed records with audience `support`, event, incident/run references, and time. The UI labels them as demo notifications. No mail, SMS, external recipient, or delivery guarantee is implied. A UI toast alone is not evidence of a saved notice.

## Structured logging and metrics

Every event is one JSON object per line in a local append-only lab log and the console. Required common fields are `timestamp` (UTC ISO 8601), `level`, `event`, `source`, and server-generated `correlation_id`. Use `endpoint_id`, `check_id`, `incident_id`, `actor_id`, `attempt`, `status_code`, `error_category`, `latency_ms`, `duration_ms`, `wait_ms`, and `outcome` when relevant; omit unavailable fields rather than inventing values. HTTP errors return the request correlation ID in the body and `X-Correlation-ID` header.

A single-run trigger shares its correlation ID with its run. Run all and scheduler dispatch create one child correlation ID per run, retaining `parent_correlation_id` for the triggering request/tick. Subsequent acknowledgement and recovery requests have their own correlations and reference the same incident/run IDs. Polling requests receive new request IDs; the stored run correlation stays unchanged. This supports tracing across multiple requests without pretending they are one request.

Required events include registration, authorization denial, check start, attempt, retry scheduled, transient recovered, check completed, incident opened/already open/acknowledged, recovery verified, support notice recorded, fixture behavior changed, scheduler started/stopped/capacity blocked/schedule reset, run interrupted, and storage failure. Denials and fixture changes must be observable too.

Do not log cookies, session IDs, passwords, tokens, arbitrary headers, raw JSON bodies, dependency bodies, or personal information. Use endpoint IDs in diagnostic events. Client errors expose safe codes/messages, field errors, and correlation IDs, not internal paths or stack traces. The log view provides recent sanitized events and copying; it cannot clear saved logs. A file-write failure pauses automation and signals the maintainer; console output is a fallback, not proof that a missing file entry was saved.

SQLite and the log file cannot commit atomically. Reconcile missing final log lines against committed runs and notices; preserve any gap as a limitation/failure. Stage 4 records counts of completed/passed/failed/interrupted checks, attempts and retries, run and request timings, capacity deferrals, and actual expected-versus-actual outcomes. No runtime measurements are claimed here.

# Pattern comparison and trigger contract

Status: implemented Module 13 pattern baseline, originally compared in Stage 1. This compares approaches for the approved monitoring workflow, not additional office systems. See [actual scheduler/backend evidence](../evidence/evidence-index.md).

## Pattern comparison

| Pattern | Latency and volume | Reliability, duplicates, ordering, back-pressure | Security, effort, and ownership | Decision |
| --- | --- | --- | --- | --- |
| In-process scheduled polling | Endpoint interval plus dispatch/capacity delay; suitable for a small lab | Process must run; unique run reservation prevents overlap; due records wait when two slots are occupied | One backend owner; fixed fixture target; small implementation surface | Selected for repeated observation and detection of silent services |
| OS cron / task scheduler | Coarser external schedule; can start work independently of UI | Process overlap and missed-run handling need persistent guards; shutdown coordination is separate | Platform setup and filesystem/runtime permissions become extra responsibilities | Feasible alternative, unnecessary for the current local demonstration |
| Manual request-driven event | Immediate if capacity exists; operator determines volume | Same idempotency and per-endpoint guard as polling; no detection without a person | Backend checks demo capability; easy to reproduce via API client | Selected for Run check, Run all, acknowledgement, and verification after repair |
| Webhook | Low latency after a producer sends an event | Silence may mean healthy, failed, or missing event; duplicate/out-of-order delivery requires handling | Needs approved event producer and verified sender; another trust boundary | Not selected; a monitored service must not be trusted to report its own silence |
| Durable queue + worker | Good buffering for higher volume | Redelivery, ordering, poison jobs, and backlog ownership must be designed | Broker installation, access, monitoring, and recovery add effort | Defer; current design has no broker or unbounded work queue |
| Change-data events | Near database-change latency | Captures record changes, not independent service availability; offsets and duplicates need ownership | Requires access to a source database/change stream | Does not fit the primary health-check trigger |
| Hybrid schedule + manual event | Automatic recurring checks and immediate human verification | One shared worker policy prevents divergent retries and duplicate incidents | Student owns one dispatcher and API; UI has no timer authority | Chosen overall approach |

For Module 13 Activity 1's contrasting workflows, the three bounded examples are endpoint registration (request-driven validation), health observation (scheduled polling), and recovery verification (human repair followed by manual or scheduled observation). Their latency, ownership, and failure contracts differ without introducing unrelated project scope.

## Trigger contract

| Trigger | Preconditions and accepted input | Work and output | Duplicate/capacity behavior |
| --- | --- | --- | --- |
| Register endpoint | Operator session, valid JSON, unique canonical URL, idempotency key | Store endpoint as `UNKNOWN`; if scheduler is on, mark due now | Replay returns original registration; duplicate URL with a new key is 409 |
| Run one | Operator, existing endpoint, key, storage available | Reserve run and a worker slot; return 202 with run ID | Same key replays; different key while endpoint is running returns 409 with active run ID; no slot returns 503 without a run |
| Run all | Operator and key | Evaluate endpoints in ascending ID order; reserve only available slots; 202 contains per-endpoint accepted/busy/capacity outcomes | No waiting jobs are silently created; client shows which endpoints require another request |
| Start scheduler | Operator and key | Persist enabled flag, make idle endpoints due now, return state; dispatch after commit | Starting an already enabled scheduler is a state-preserving success; no duplicate runs |
| Scheduler tick | Enabled, valid config, storage available | Scan due idle endpoints in `(next_due_at, endpoint ID)` order and reserve at most two total slots | Busy endpoints are not re-enqueued; capacity-blocked endpoints stay due; no backlog of tick events |
| Stop scheduler | Operator and key | Persist disabled flag; no future automatic reservations | Existing runs complete within retry bound; manual runs remain available |
| Acknowledge incident | Operator, key, existing `OPEN` incident | Record fictional server-side actor and time; return `ACKNOWLEDGED` | Already acknowledged returns existing state without another acknowledgement event; recovered incident is 409 |
| Change fixture behavior | Operator, key, known behavior | Set future-run fixture mode; keep health/incident state unchanged | Current run retains its snapshot; “fix” is behavior `stable` |

## Timing, capacity, and restart semantics

- Registered intervals are integer seconds 10–3600, default 60. Dispatcher tick is 1,000 ms; global accepted/running capacity is two; per-endpoint capacity is one. There is no durable queue of waiting checks.
- First registration while enabled, or a disabled→enabled transition, makes idle endpoints due immediately. In normal operation, idle capacity dispatches them on the next tick. A manual run uses the same slot budget and resets the endpoint's next due time after completion.
- After a completed check, set the next due time to completion plus that endpoint's interval. This is fixed delay after completion, not an exact wall-clock frequency. Starting the scheduler while a run is active does not duplicate it; completion establishes its next due time.
- Reserve run/slot, schedule occurrence key, and due-state changes transactionally before any HTTP call. A scheduler occurrence key is based on endpoint ID and its recorded due time; store it uniquely so the same due occurrence cannot create another run.
- Within a live process, elapsed durations and retry waits use a monotonic clock; persisted/audit times use UTC ISO 8601. The UI may display Asia/Manila time with an explicit timezone. DST and local timezone changes do not create extra jobs. Do not backfill missed checks after downtime or a clock change; record a schedule reset and calculate the next due time from the current observation.
- Each process start records the previous scheduler state and then starts disabled. After storage becomes available, mark leftover running records `INTERRUPTED` before accepting new work, preserve attempts, set affected endpoint status to `UNKNOWN`, and release their reservations. An operator must restart scheduling. No old attempt is silently replayed.
- If the database is unavailable, do not reserve runs or issue further HTTP attempts. Disable dispatch and expose a safe storage error. After repair, reconcile records before operator restart.

## Claims to verify later

With idle capacity, an already-due endpoint should be reserved within two seconds of a dispatcher observation in the controlled lab; record actual times rather than treating a general-purpose OS as a hard real-time scheduler. Under capacity pressure, verify two concurrent runs at most, no overlap for an endpoint, and eventual service after capacity becomes free. Record dispatch delay, run duration, attempt/retry counts, failure ratio, skipped-busy/capacity events, and startup interruptions. No throughput or sustained-load conclusion is supported by Stage 1.

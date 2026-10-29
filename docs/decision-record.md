# Automation decision record

Status: implemented for Module 13 after the user's instruction to complete all remaining stages. Date: 2026-10-30. The original design used the supplied brief/module/prototype; actual verification and retained failures are linked in [the evidence index](../evidence/evidence-index.md).

Decision question: how can a student demonstrate repeatable endpoint monitoring, bounded failure handling, and observable recovery with a small, explainable system?

## D1. Backend owns automation; use the requested stack

**Decision:** one Node.js + Express process, SQLite persistence, a controlled HTTP fixture, and a Flutter Web client. Separate API handling, validation, scheduler, check policy, fixture transport, storage, and logging responsibilities.

| Alternative | Functional/reliability fit | Security and performance | Effort, skills, ownership, and verification |
| --- | --- | --- | --- |
| Chosen single backend + SQLite | Persists outcomes; one place controls checks and incident rules | Loopback boundary; two concurrent checks bound work; one storage writer | Matches requested skills/stack; student owns one backend; transactions and HTTP traces are inspectable |
| Browser-only prototype | Good screen-flow reference; closing a tab loses automation and records | Client cannot protect trusted controls; work depends on open browser | Lowest effort, but cannot meet scheduler/persistence requirements |
| Separate worker/broker + server database | Better basis for multiple workers and durable queueing | More network and privilege boundaries; more capacity options | Extra services, setup, and recovery ownership are unjustified for this lab |

**Consequences:** the Node process must remain running, backups matter, and one process is a hard assumption. SQLite storage errors pause automation. Component separation requires a little more structure than placing all behavior in route handlers.

**Review condition:** revisit if multiple backend instances, significant write contention, or monitoring while the local application is off becomes a requirement. Verify transaction rollback and restart handling in focused backend checks.

Viva explanation: “The browser handles interaction; the backend owns work that must continue across page changes and must be recorded consistently.”

## D2. Hybrid of backend scheduling and manual requests

**Decision:** a one-second dispatcher starts due endpoints; manual Run check and Run all use the same worker. Scheduling is off at startup until an operator starts it. Each endpoint uses its own interval.

**Alternatives:** OS cron offers independent process scheduling but adds platform configuration and overlap/recovery ownership. Webhooks/queues need a producer and cannot alone detect a silent dependency. The full comparison is in the [pattern matrix](pattern-matrix.md).

**Consequences:** no checking while the process is off, no historical backfill, and some dispatch delay under capacity pressure. The operator owns starting/stopping the lab scheduler. UTC storage and elapsed-time waits avoid a dependence on the workstation's displayed timezone.

**Review condition:** verify interval handling, stop/start, capacity, and no duplicate running checks. Revisit if uninterrupted background operation is required.

Viva explanation: “Polling detects silence; manual requests support a controlled demonstration and verification after a repair.”

## D3. Three attempts with fixed delay; incidents retain human ownership

**Decision:** at most three total attempts, a 3,000 ms timeout per GET, and 700 ms between retryable failures. Preserve the prototype's fixed delay so demonstrations are easy to explain. A non-retryable response stops immediately. One failed completed run opens an incident; acknowledgement accepts responsibility; a later passing check verifies recovery.

**Alternatives:** exponential backoff with jitter would spread retries across many workers, but this lab limits concurrency to two and needs a repeatable sequence. Unlimited retries can hide permanent failure. A circuit breaker and a broker dead-letter queue add states and infrastructure without a demonstrated need; the persisted incident is the human-action record. Automatic repair lacks an approved repair action.

**Consequences:** fixed delay could synchronize requests at larger scale. The policy bounds one run, while the enabled scheduler deliberately continues future observations. Failure after retries does not prove a temporary HTTP error is permanently broken; describe it as “retry exhausted, human action required.”

**Review condition:** measure attempt counts, gaps, and timeouts using real logs. Revisit delay/backoff if concurrency or external integration grows.

Viva explanation: “The bound prevents one check from retrying forever. A new scheduled check is a new observation, not a fourth retry.”

## D4. Fictional labels map to a controlled HTTP fixture

**Decision:** accept only the fictional HTTPS namespace specified in the API contract; map its path to a fixed loopback HTTP fixture. Perform actual local HTTP GETs and measure them. Fixture modes are stable, transient, persistent outage, and non-retryable path failure.

**Alternatives:** returning invented outcomes directly inside the UI cannot prove backend dependency behavior. Calling public APIs or the fictional DNS host creates availability, permission, and data risks without helping the required demo.

**Consequences:** the check engine exercises HTTP failures and timeout handling, but does not prove DNS, internet routing, certificates, or the registered URL's real-world availability. The fixture requires its own loopback listener and failure controls. In Stage 4, record the fictional label and the actual local transport target separately; never present fixture responses as observations of a live external service.

**Review condition:** preserve fixture request records, injected mode/sequence, actual responses, and worker correlation IDs. Revisit only when an instructor-approved real sandbox is explicitly in scope.

Viva explanation: “The faults are deliberately injected; the backend requests, retries, database outcomes, and logs must still be real.”

## D5. Minimal server-side demo session; defer real identity integration

**Decision:** Login is labeled a local demo placeholder. An operator or viewer selection creates a server-held, in-memory session with an opaque HttpOnly cookie. No passwords are requested. The backend rejects no-session calls with 401 and viewer mutations with 403. Capabilities come from the server's session map, never a browser role header or mutation payload.

**Alternatives:** UI-only hidden buttons cannot demonstrate server denial. Accepting an `X-Role: operator` header trusts a caller's claim. Real accounts, password storage, JWT/OAuth, and role administration would start Module 14 and are deferred.

**Consequences:** anyone with access to the local demo can select operator. This proves a rejection branch, not identity security or protection against hostile users. Restart invalidates sessions; records and idempotency entries persist. Bind the lab to loopback and allow only the configured Flutter origin for browser requests. No production secret is required.

**Review condition:** test missing-session and viewer requests directly against the API; verify a forged role header does not grant writes. Replace the placeholder only in a separately approved later module.

Viva explanation: “The unauthorized path is observable, but the login does not authenticate a real person.”

## D6. Durable records, structured logs, and honest evidence

**Decision:** SQLite owns domain truth; final-result and incident/notice changes use one transaction. JSON-lines logs include correlation and run identifiers without payloads, cookies, response bodies, or stack traces in client errors. Preserve all attempt/failure records. Uptime is a completed-check ratio. Support notifications are durable in-app demo notices.

**Alternatives:** console messages alone cannot establish persisted state. Counting every failed retry as a failed check misstates the prototype's metric. External email/SMS would require accounts, credentials, and delivery evidence outside the agreed scope.

**Consequences:** logs and SQLite are separate sinks; a crash can leave a committed transaction without its final log line. Reconcile using run IDs and committed state; do not claim exactly-once file logging or external delivery. Storage and logs grow during the lab; preserve/export before any maintainer-led archival, and do not remove failures from submitted evidence.

**Review condition:** collect real requests, actual results, timestamps, logs, database counts, and timings in Stage 4. Investigate mismatches instead of replacing them with expected values.

Viva explanation: “A retry is an attempt inside one observation. The saved final observation drives uptime and the incident state.”

## Configuration and maintainability commitments

Stage 2 provides `.env.example` with nonsecret defaults: loopback API/fixture hosts, API port 3000, fixture port 4001, Flutter origin `http://localhost:8080`, SQLite/log paths, dispatcher tick 1,000 ms, concurrency 2, attempt timeout 3,000 ms, maximum attempts 3, retry delay 700 ms, and demo mode enabled. The registered interval defaults to 60 seconds. Invalid configuration prevents startup; attempts cannot be configured above three. No `.env` or source file contains a real secret.

Policy values are centralized. Routes call domain services rather than duplicate the retry loop. Persistence and fixture transport have clear interfaces. The maintainer must update these documents when behavior changes and rerun the affected acceptance cases. The Stage 4 maintainability note will discuss actual change impact, evidence, ownership, and limitations; no maintainability or performance result is claimed now.

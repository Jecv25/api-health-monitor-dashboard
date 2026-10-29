# Workflow boundary

Status: implemented Module 13 baseline, originally recorded in Stage 1. Observed coverage and limits are recorded in [the evidence index](../evidence/evidence-index.md).

## Problem, outcome, and actors

Developers and support personnel need to register approved fictional service endpoints, run repeatable availability checks, see outages, acknowledge responsibility, verify recovery, and inspect a check-based uptime summary.

The bounded path is: register endpoint → scheduled or manual check → bounded retry → saved outcome → incident when still failing → human acknowledgement and repair → new passing check → recorded recovery notification → report.

| Actor | Responsibility and boundary |
| --- | --- |
| Student developer/maintainer | Owns configuration, backend, fixture, Flutter UI, storage, evidence, and repairs to this prototype |
| Demo operator (fictional support user) | Registers endpoints, triggers checks, controls the scheduler, acknowledges incidents, and changes fixture behavior |
| Demo viewer (fictional supervisor) | Reads endpoints, results, incidents, notifications, summaries, and sanitized logs; cannot mutate them |
| Backend scheduler | Starts due checks while enabled; never acknowledges incidents or repairs dependencies |
| Controlled dependency fixture | Returns specified HTTP outcomes; owned by the student and isolated from real services |
| User reviewing this work | Approves each project stage; this does not assert instructor approval of an environment or service |

Demo personas are test capabilities, not verified identities. A freely selectable placeholder login cannot establish who a person is.

## System and trust boundaries

See the [boundary diagram](diagrams/workflow.md) and [API contract](api-contract.md).

- Flutter Web is an untrusted browser client. It displays state and performs helpful validation; Express repeats validation and decides whether a demo session may act.
- One Node.js + Express process owns scheduling, check execution, incident rules, and SQLite writes. It runs on loopback in the lab. Only one process may use the monitoring database.
- SQLite and a local JSON-lines log file persist lab records. The browser cannot access their paths directly. The maintainer owns filesystem access and preservation.
- A separate loopback HTTP fixture listener supplies real, controlled request/response failures. It is an external dependency of the check worker even when started by the same lab command.
- Registered URLs use fictional HTTPS identifiers on the exact host `api.sandbox.example`. The backend maps an approved path to the local fixture origin. It does not resolve or contact those fictional hosts, follow redirects, or fetch arbitrary user URLs.
- No dependency credentials or personal data are needed. No secrets enter Flutter, source documents, response bodies, or logs. A runtime demo-session identifier stays in an HttpOnly cookie and is never logged.

The local HTTP transport is a stated lab limitation. External HTTPS integration and identity-based access control belong to later modules and are not being built here.

## Inputs, preconditions, and outputs

| Item | Contract |
| --- | --- |
| Preconditions | User has approved the implementation stage; controlled environment is available; configuration and database open successfully; fixture is bound to loopback |
| Untrusted inputs | Browser JSON, URLs, names, intervals, persona selection, route parameters, idempotency keys, and dependency responses |
| Trusted control inputs | Validated backend configuration, fixed fixture origin/path mapping, server-held demo-session capabilities, and committed database state |
| Triggers | Operator request or scheduler due time; both use the same check service and concurrency rules |
| Processing | Validate → authorize → deduplicate/reserve → attempt GET up to three times → persist outcome and state changes → emit safe logs |
| Outputs | Endpoint status, attempt history, one final result per completed check, incidents, in-app support notices, structured logs, and check-based uptime |
| Human approval point | Operator acknowledges responsibility, examines the cause, and explicitly changes the fixture to simulate repair; only a subsequent successful check verifies recovery |

An unavailable fixture is an observed dependency failure. An unavailable database is a monitoring-system failure and must not be reported as a dependency outage or successful recovery.

## Planned records and invariants

| Record | Minimum data and invariant |
| --- | --- |
| Endpoint | ID, name, canonical fictional URL, interval, fixture behavior, status, next due time, creation time; canonical URL is unique |
| Check run | ID, endpoint ID, trigger, correlation ID, schedule key if applicable, start/end times, `RUNNING`, `COMPLETED`, or `INTERRUPTED`; at most one running check per endpoint |
| Attempt | Run ID, ordinal 1–3, start/end times, HTTP status or error category, measured latency; `(run ID, ordinal)` is unique; response bodies are discarded |
| Final result | Run ID, pass/fail, attempt count, final category, completion time; run ID is unique; interrupted runs have no final result |
| Incident | ID, endpoint ID, opening run, reason, state, acknowledgement actor/time, recovery run/time; at most one `OPEN` or `ACKNOWLEDGED` incident per endpoint |
| Support notice | Incident ID, event `opened` or `recovered`, audience `support`, creation time; `(incident ID, event)` is unique |
| Idempotency record | Demo actor, method, route, key, canonical payload hash, original response; retained for the lab dataset |

Database constraints and transactions enforce uniqueness alongside application guards. The final result, endpoint status, incident transition, support notice, and run completion commit together. A repeated failed check updates the visible result without opening a second active incident. A later outage after recovery may create a new incident.

Endpoint states are `UNKNOWN`, `UP`, and `DOWN`. `CHECKING` is a separate activity indicator, preserving the last confirmed status. Following an interrupted run, show `UNKNOWN` until a new complete check verifies the endpoint; retain its earlier results.

No endpoint editing/deletion, attempt rewriting, log clearing, or evidence deletion is provided. Fixture-behavior changes affect future runs only; each run snapshots its behavior to make injected sequences repeatable.

## Prototype behavior and deliberate clarifications

| Reference behavior | Proposed implementation |
| --- | --- |
| Library API: 200 | Real fixture GET returns 200 on attempt one |
| Enrollment API: 503, 503, 200 | Fixture uses run ID and ordinal; this sequence repeats per run |
| Payments sandbox: persistent 503 | Three attempts fail, one incident opens, support sees an in-app notice |
| Wrong path: 404 | First attempt fails without retry; route to a person |
| Simulate fix | Operator changes the behavior to `stable`; no status or incident changes until a new check passes |
| Three attempts, 700 ms wait | Three total attempts, at most two 700 ms waits; wording avoids interpreting this as three additional retries |
| Global scheduler every 20 seconds | Replace the prototype timer with per-endpoint intervals of 10–3600 seconds, default 60; the prototype stores but does not honor these intervals |
| In-memory results and incidents | Persist them across backend/browser restarts |
| Browser toast says support notified | Persist and display a notice labeled `In-app demo notification`; no email/SMS claim |
| Logs and evidence guide | Preserve log viewing/copying and a guide; omit destructive Clear; guide links to actual evidence only when it exists |

Seed examples are fictional: Library API at `https://api.sandbox.example/library/health`, Enrollment API at `/enroll/health`, and Payments sandbox at `/pay/health`. No seed executions or outcomes are assumed.

## Reporting and limits

Uptime here means **successful completed checks ÷ all completed checks × 100**, per endpoint across the current SQLite dataset. A success on attempt three contributes one passed check; it does not contribute two failed checks. In-progress and interrupted runs are excluded. Zero checks yields `null` and “No data,” never 100%. Display two decimal places. This sample ratio is not measured elapsed availability, an SLA, or a claim about unchecked periods.

Module 13 includes focused checks, safe configuration, validation, structured logs, basic denial behavior, and failure injection. Full authentication/RBAC, encryption/TLS deployment, the Module 15 hardening campaign, load benchmarking and deployment evaluation, formal UAT/OpenAPI completion, and final examination artifacts from Modules 14–18 remain outside this work. No mobile app, broker, external notification provider, distributed scheduler, or automatic dependency repair is included.

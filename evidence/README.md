# Week 13 / SA7 evidence map

Project: Pulsewatch API Health Monitoring Dashboard. Actual stack: Flutter Web, FastAPI, **MySQL 8.4.8**. Controlled fictional services only. Runtime versions are in [environment.json](environment.json) and [flutter-environment.json](flutter-environment.json). Exact submitted source is fingerprinted in [source-manifest.json](source-manifest.json).

## Observed verification

| Check | Observed result | Artifact |
| --- | --- | --- |
| MySQL-backed backend regression | 30 passed; one documented dependency deprecation warning | [original failures](backend-tests-01.txt), [passing rerun](backend-tests-02.txt), [JUnit](backend-tests-02.xml) |
| OpenAPI/auth dependency adjustment | 2 focused regression checks passed | [contract regression](backend-contract-regression.txt) |
| Flutter state/client regression | 10 passed, including open-dialog updates and in-dialog feedback | [final state tests](flutter-tests-05.txt); runs 01–04 retain earlier observations |
| Flutter Web compilation | Successful local-resource build | [final build](flutter-build-03.txt) |
| Real HTTP/API/MySQL demonstration | 11 expected/actual scenarios passed | [http-demo-20261030T153948Z](http-demo-20261030T153948Z/results.json), [structured logs](http-demo-20261030T153948Z/structured-logs.jsonl) |
| Independent worker and restart | 2 actual process scenarios passed | [worker-20261030T154704Z](worker-20261030T154704Z/results.json) |
| Edge / actual Flutter normal and adverse states | 6 recorded checks passed | [browser-20261030T153753Z](browser-20261030T153753Z/results.json) |
| Edge / actual incident and recovery workflow | 8 recorded checks passed | [browser-recovery-20261030T155840Z](browser-recovery-20261030T155840Z/results.json) |
| Local stop/start preserves MySQL records | Expected and actual endpoint counts match | [local lifecycle](local-lifecycle.json) |

The browser basic capture records whether its controlled service was newly registered or reused. Recovery capture explicitly records API-based baseline preparation when a previous demonstration incident existed. API-unavailable browser evidence uses controlled request interception; it does not claim the API process crashed.

## Requirement → implementation → evidence

| Requirement | Implementation and verification |
| --- | --- |
| SA7-01 registration | `main.py` registration + MySQL URL constraint; healthy/duplicate API tests; basic browser normal path |
| SA7-02 invalid/boundary inputs | `schemas.py`; invalid URL/origin/interval/timeout tests; basic browser invalid form |
| SA7-03 unauthorized action | API-key dependency; unauthorized API tests; real browser invalid-key state |
| SA7-04 normal check | Shared `HealthRunner`; persisted healthy test and actual HTTP/browser check |
| SA7-05 transient recovered | Two attempts 503→200; actual HTTP run and matching structured logs |
| SA7-06 persistent → human action | Three-attempt exhaustion; incident/notification deduplication tests; actual outage screenshot and HTTP records |
| SA7-07 acknowledgement | Protected support acknowledgement API and Flutter dialog; actual browser acknowledgement |
| SA7-08 recovery verification | Two successful cycles, failure resets streak; backend regression, open-dialog widget regression, actual recovery screenshots |
| SA7-09 duplicate/concurrent work | MySQL advisory lock + endpoint/idempotency unique key; overlap test and actual replayed HTTP request |
| SA7-10 scheduling/restart | Separate APScheduler worker, due-time checks and heartbeat; actual worker/restart results |
| SA7-11 uptime summary | SQL completed-cycle aggregates; unknown-without-samples test; actual reports |
| SA7-12 responsive workflow/states | Flutter state tests; actual 1440px and 390px captures, unavailable/reconnect capture |

## Review and fallback

Open [gallery.html](gallery.html) for the final verified screenshots. Read [workflow and decisions](../docs/week13-design.md), [API contract](../docs/api-contract.md), [architecture](../docs/architecture.md), [recovery runbook](../docs/recovery-runbook.md), [issue record](../docs/issue-record.md), and [maintainability/risks](../docs/maintainability.md).

Earlier browser directories preserve MIME/locator interruptions and the real stale-dialog observation. A partial/interrupted directory is **not** used as proof of a completed walkthrough. Failure artifacts are normalized to UTF-8 and credential diagnostics are redacted; they are not represented as untouched originals. The issue record identifies fixes and regression evidence.

Screenshots support source, structured logs and machine-readable expected/actual observations. They do not establish production readiness, Week 14–18 completion, stakeholder UAT, student viva or individual contributions. Complete the personal contribution record after reproducing the work.

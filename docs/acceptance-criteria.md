# Acceptance criteria and planned verification

Status: criteria recorded before implementation; the core cases have now been executed. The tables below retain expected outcomes. [The evidence index](../evidence/evidence-index.md) links actual results and precise execution timestamps; preparation dates are not substituted for execution times.

## Execution coverage

| Criteria | Observed coverage |
| --- | --- |
| N01, I01, U01, U02, D01, D02, D03, R01 | Individual real HTTP request/response, saved-state, log, expected/actual and timestamp records in the latest API run |
| X01, X02 | API replay record plus focused backend replay/conflict/overlap/capacity tests |
| S01 | Backend test observes 10- and 60-second intervals, second short-interval completion, and stop; closed test databases/logs retained with final validation |
| C01 | Actual child process killed and restarted on its saved database; dedicated restart evidence |
| F01, F02 | Actual 3-second HTTP timeout and controlled SQLite finalization rollback; attempt/result/incident/notice evidence preserved |
| O01, M01 | Real structured logs, notices, check ratios, no-data and interrupted-run exclusions inspected by automation |
| W01, W02 | Widget tests and actual Chrome walkthrough at 1280/768/390 pixels; screenshots and explicitly labeled UI-only fault injection |
| V01 | Focused server boundary vectors executed; the full enumerated cross-product is not claimed |
| S02 | Busy/capacity bounds tested; prolonged multi-cycle starvation/fairness stress is NOT RUN |

Earlier failed runs remain visible. This is focused Module 13 verification, not a complete security, accessibility, browser, or performance certification.

Use a fresh, separately identified fictional dataset when deterministic counts are needed, preserving any earlier dataset/evidence first. Scheduler is off unless the case tests it. Establish an operator/viewer session as specified. Use unique fictional paths and new UUID mutation keys unless testing replay. Record initial counts so fixtures or prior observations cannot silently change the expected denominator.

## Required normal, invalid, unauthorized, dependency, and recovery paths

| ID / path | Planned request or action | Measurable expected result | Evidence to retain later |
| --- | --- | --- | --- |
| N01 Normal | Operator registers `Library Demo`, URL `https://api.sandbox.example/library-demo/health`, interval 60, behavior stable; trigger one check and poll returned run | Registration 201 UNKNOWN; check trigger 202; exactly one actual fixture GET returns 200; one saved attempt and one passed final result; endpoint UP; no new incident; report delta total +1, passed +1, failed +0 | Exact requests/responses, fixture request record, run/attempt/result IDs, JSON logs, before/after summary and UI |
| I01 Invalid input | Direct operator `POST /endpoints` with blank name, `http://api.sandbox.example/bad/health`, interval 5, behavior stable; separately try fractional interval and unknown behavior | 422 with correct field errors; no endpoint/run/result/incident/notice added; no dependency call; client mirrors errors and retains typed input | Request, field errors, unchanged counts, validation log and UI |
| U01 Unauthorized | Without cookie, submit a well-formed `POST /endpoints/:id/checks` for an existing endpoint, with valid key | 401; zero new runs/attempts/results/incidents/notices and zero fixture calls; authorization-denied log has correlation ID; UI leads to demo login | Sanitized request/response, count comparison, denial log, UI |
| U02 Forbidden | Viewer attempts registration and incident acknowledgement, including a forged operator role header | 403; endpoint/incident unchanged; no side effect; server does not trust the header | Request/response without cookie value, unchanged records, denial events |
| D01 Transient dependency failure | On a fresh endpoint with flaky behavior, run one check | Actual sequence 503, 503, 200; exactly three saved attempts and two retry waits of at least 700 ms; one passed result; UP; `transient_recovered`; no active incident created when none existed; report counts one passed check | Injection mode/run metadata, three fixture responses, attempt times/logs, final state and summary |
| D02 Persistent dependency failure | Run dead behavior, acknowledge resulting incident, then run dead behavior again | Each run has three 503 attempts/two waits and one failed result; exactly one active incident and one opening notice across both runs; acknowledgement leaves DOWN; second failure preserves ACKNOWLEDGED and logs existing incident | Both run records, fixture responses, incident/notice counts, acknowledgement request, logs/UI |
| D03 Non-retryable dependency failure | Register broken behavior and run once | One 404 attempt, zero retry events, one failed result, DOWN, one OPEN incident routed to human; category non-retryable HTTP | Fixture request/response, single attempt, logs and incident record |
| R01 Recovery | Starting with D02's acknowledged incident, PATCH behavior to stable, inspect state, then trigger a new check | Immediately after PATCH: still DOWN/ACKNOWLEDGED, no recovery notice; after one real 200 and committed passing result: UP, same incident RECOVERED with run/time, one recovery notice; earlier two failed results preserved; for that isolated three-run sequence total 3, passed 1, failed 2, ratio 33.33% | Before/after behavior and incident reads, repair/check requests, passing fixture response, notice and recovery logs, report |

For D01, a final success does not erase its two failed attempts. For D02, “persistent” describes the injected outage through the run, not a proof that 503 is intrinsically permanent. R01 is a separate verification step after an injected repair.

## Focused reliability and UI criteria

| ID | Planned action | Measurable expected result |
| --- | --- | --- |
| V01 Server boundary | Try name lengths 2/3/40/41, intervals 9/10/3600/3601, wrong JSON types, malformed JSON, non-JSON body, arbitrary host/userinfo/query/fragment/path, and duplicate canonical URL | Accepted boundaries match contract; 400/415/422 or 409 as specified; no invalid endpoint stored or external URL fetched |
| X01 Accepted-request replay | Repeat accepted registration/check/ack/fixture-change request with identical scope/key/payload; repeat key with changed payload | Same original response/IDs and replay marker; no duplicate side effects or notice; changed payload 409 |
| X02 Overlap and capacity | Send different-key checks to one endpoint while running, then checks across three endpoints | One running check per endpoint; duplicate 409; at most two accepted/running globally; excess 503 without a queued run; Run all reports each admission outcome |
| S01 Scheduler | Register interval 10 and interval 60 endpoints, start scheduler with idle capacity, observe completions/next dispatch, stop it | First due dispatch within the lab's two-second observation target; next scheduled run starts no earlier than completion plus its own interval; intervals are not replaced by the prototype's 20-second timer; stop prevents new automatic reservations, existing work finishes |
| S02 Capacity deferral | Make more endpoints due than slots; observe after slots free | Due work stays due without duplicate tick jobs; active count ≤2; endpoint order follows due time/ID and deferred endpoints eventually run; record actual delay |
| C01 Crash and recovery | Terminate during a run, preserve files, restart and inspect; replay original key; submit a new-key run | Old run INTERRUPTED, saved attempts retained, no invented final result, affected endpoint UNKNOWN; scheduler off; session reselection needed; replay points to old run; new observation works and does not duplicate active incident |
| F01 Fixture transport failure | Stop fixture listener or inject a >3-second response delay | Refusal/timeout recorded with measured duration; at most three attempts; no endless retry; failed completed check creates/reuses incident; restored fixture requires a new passing check |
| F02 Storage failure | Inject controlled result-transaction failure in a disposable identified dataset | No partial result/status/incident/recovery-notice transaction; dispatch pauses, safe error and log; unfinished run reconciled without deleting saved attempts; no false dependency diagnosis |
| O01 Observability | Follow one check, one denial, acknowledgement, and recovery across API/logs/storage | Valid JSON lines with UTC timestamps, server correlations and relevant IDs; real latency/duration; no cookies, credentials, bodies, or personal records; stored notice rather than unsupported external delivery claim |
| M01 Metric semantics | Compare isolated D01/D02/R01 runs, a zero-result endpoint, and an interrupted run | Attempts do not inflate denominator; zero→null/No data; interrupted/in-progress excluded; failed completed history remains |
| W01 Flutter states | Exercise normal/empty/loading/invalid/no-session/viewer/offline/500/503/interrupted states | Clear relevant feedback; retained input/confirmed data; no fabricated success; correct next action; server errors include correlation if available |
| W02 Responsive and accessible flow | Register, run, inspect, acknowledge, and read report at 1280/768/390 CSS pixels using keyboard | Core tasks usable without page-wide horizontal scroll; readable labels/status text, visible focus, logical order, no color-only meaning; copy logs preserves sanitized content |

These focused cases establish Module 13's bounded automation claims. They do not substitute for the broader Module 15 security/integration campaign or Module 16 performance/deployment evaluation. Record a failure if a timing target is missed; investigate and preserve it rather than weakening or silently rewriting the expected result.

## Stage 4 minimum evidence set and recording format

The three demos are N01 successful execution, D01 recovered transient failure, and D02 persistent failure routed to a person followed by R01 recovery verification. The minimum one-success-plus-four-adverse execution records are N01, I01, U01, D01, and D02. U02, D03, R01, and the focused checks provide evidence for additional contract claims. Keep test records and demo records linked, even when the same identified execution supports both.

Each execution record must include:

1. Case/run ID, build/revision or exact source snapshot identity, OS/runtime versions, effective configuration, dataset/fixture setup, initial state/counts, and operator persona label.
2. Expected result written before execution, exact method/path/nonsecret headers/body (never cookie/token values), and command or UI steps.
3. Actual response/status, persisted state/counts, actual log/fixture artifact paths and correlation/run/incident IDs, measured timings, and execution timestamp with timezone.
4. PASS/FAIL/BLOCKED/NOT RUN, the comparison and limitation, and an issue/follow-up when actual differs. An unexecuted case has no invented actual value or execution timestamp.
5. For an improvement, the reason, changed build identity, new rerun record, and relevant regression checks; preserve the original failed record.

Stage 4 has created `evidence/`, its index, lab log, actual JSON logs, requests/responses, injection proof, demos, and interpretations. README setup, maintainability note, and limitations describe the implemented build. Screenshots support the chain but do not replace requests, logs, or stored outcomes. Detailed execution records, rather than this criteria table, establish each observed result.

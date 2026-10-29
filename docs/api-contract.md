# API contract

Status: implemented Node.js + Express contract, first recorded in Stage 1. Base path: `/api/v1`. Fields here specify the interface; actual requests/results are separately preserved in [the evidence index](../evidence/evidence-index.md). Formal OpenAPI completion is deferred with Module 17.

## Common contract and demo access

Domain API requests use JSON, an optional server-issued demo-session cookie, and a required UUID `Idempotency-Key` for all domain POST/PATCH mutations. Do not send identity/role fields with those mutations. The backend generates `X-Correlation-ID` for every request; it does not trust a client value as its log identifier.

Successful responses use `data` plus `correlation_id`. Errors use `error: {code, message, fields?}` plus `correlation_id`. A field map names invalid inputs without echoing raw payloads. Malformed JSON is 400; wrong content type is 415; schema/range/unknown-field errors are 422. Well-formed requests to protected routes without a session are 401; authenticated demo viewers requesting mutations are 403, before domain validation or side effects. Unknown resource IDs are 404; duplicate/active-state/idempotency conflicts are 409. Storage errors are 503. Unexpected server errors are safe 500 responses. No stack traces or filesystem paths are returned.

| Demo route | Input/output | Access |
| --- | --- | --- |
| `POST /demo/session` | Body `persona` is exactly `operator` or `viewer`; returns persona/capabilities and sets opaque HttpOnly, SameSite=Lax cookie | Public local placeholder; no credentials; invalid selection is 422 |
| `GET /demo/session` | Current persona and capabilities | Session required; 401 when absent/invalid |
| `DELETE /demo/session` | Discard session/cookie, 204 with no JSON body | Local logout; safe when already logged out |

Sessions live in backend memory and expire on restart/logout. Cookies are not placed in local storage or logged. Local HTTP means no Secure-cookie claim. CORS allows only the configured local Flutter origin with credentials; the client uses one consistent loopback hostname. The ability to select operator is an explicit security limitation, not real authentication/RBAC. No browser role header grants a capability.

## Domain routes

All reads below require a demo session. All mutations require an operator session and an idempotency key. IDs are positive integers; invalid ID syntax is 422.

| Method and path | Request | Accepted result and important errors |
| --- | --- | --- |
| `GET /endpoints` | No body | 200 list with health, checking flag, last completion, active incident ID; empty is `[]` |
| `POST /endpoints` | `name`, `url`, `interval_seconds`, `demo_behavior` | 201 endpoint and Location header; unique canonical URL conflict 409 |
| `GET /endpoints/:id` | No body | 200 endpoint metadata, current state, active run/incident references |
| `POST /endpoints/:id/checks` | Empty object | 202 with check ID, run correlation ID, `RUNNING`, and status URL; busy 409; capacity 503 |
| `POST /checks/run-all` | Empty object | 202 with accepted run IDs and per-endpoint busy/capacity outcomes; no hidden queued jobs |
| `GET /checks/:id` | No body | 200 run state, ordered attempts, final result or null, and linked incident ID if any |
| `GET /endpoints/:id/results?limit=50` | Limit integer 1–100 | 200 newest completed results, IDs/times/attempt counts/outcomes; interrupted runs available through run lookup and recent-run metadata, excluded from this list |
| `GET /scheduler` | No body | 200 enabled flag, configured tick/capacity, active count, last dispatch/storage error if any |
| `POST /scheduler/start` | Empty object | 200 enabled; dispatch occurs after state commit |
| `POST /scheduler/stop` | Empty object | 200 disabled; already-running checks finish |
| `GET /incidents?state=active` | State optional: `active`, `OPEN`, `ACKNOWLEDGED`, `RECOVERED`; omitted means all | 200 newest-first incident list; `active` includes OPEN and ACKNOWLEDGED |
| `POST /incidents/:id/acknowledge` | Empty object; actor is server-derived | 200 ACKNOWLEDGED with actor/time; repeat preserves original acknowledgement; recovered 409 |
| `PATCH /endpoints/:id/demo-behavior` | `demo_behavior` | 200 updated behavior for future runs; no direct health/recovery changes |
| `GET /notifications?limit=50` | Limit integer 1–100 | 200 newest persisted opening/recovery notices labeled `in_app_demo`, audience support |
| `GET /reports/uptime` | No body | 200 per-endpoint total/passed/failed completed checks, percentage or null, metric basis, dataset start and as-of time |
| `GET /logs?limit=100&correlation_id=...` | Limit integer 1–200; optional valid server correlation ID | 200 recent sanitized events, read from retained local log; empty is `[]`; no clear/delete route |

Run-all admission is deliberately limited by two slots. With three idle seeded endpoints and no active work, the first two IDs are accepted and the third reports capacity blocked. This visible limit keeps work bounded; the evidence guide runs the three demos individually. In scheduler mode, due-but-unaccepted endpoints remain due and are considered again as capacity frees.

Endpoint detail includes recent run metadata, including interrupted runs, separately from completed results so interruption is visible. Reads of `GET /checks/:id` never start work. Polling its state is safe and does not need a mutation key.

## Authoritative registration rules

| Field | Rule and failure |
| --- | --- |
| `name` | JSON string; trim surrounding whitespace; 3–40 Unicode code points; reject control characters; missing/bad value 422 |
| `url` | Trimmed absolute HTTPS URL, at most 200 characters; exact hostname `api.sandbox.example`; no user info, nondefault port, query, fragment, percent escapes, or dot segments; path must match `/[a-z][a-z0-9-]{0,39}/health`; invalid 422 |
| URL uniqueness | Canonical parser output, lowercase host and omitted default HTTPS port; reject duplicate canonical URL with 409 `DUPLICATE_ENDPOINT` |
| `interval_seconds` | JSON integer 10–3600 inclusive; default 60 when omitted; reject strings, floats, null, and booleans with 422 |
| `demo_behavior` | Exactly `stable`, `flaky`, `dead`, or `broken`; default `stable` when omitted; unknown values 422 |
| Other fields | Reject unknown fields, including client-supplied status, results, actor, and incident state, with 422 |

The Flutter form mirrors these rules, but direct API calls remain independently validated. The restricted URL namespace deliberately narrows the prototype's general HTTPS input to the approved fictional lab. Backend transport uses the configured loopback fixture origin plus the accepted path; it never connects to the submitted URL. Fixture control passes run/attempt metadata internally to support deterministic sequences; browser input cannot override attempt counters or run snapshots.

## Representative response fields

An endpoint has `id`, `name`, `url`, `interval_seconds`, `demo_behavior`, `status`, `checking`, `active_check_id`, `last_completed_at`, `next_due_at`, and `active_incident_id`. A new endpoint is UNKNOWN with no result. A run has `id`, `endpoint_id`, `trigger`, `state`, `correlation_id`, `started_at`, `finished_at`, `attempts`, `result`, and `interruption_reason` when relevant.

Each attempt has `ordinal`, `started_at`, `finished_at`, `status_code` or null, `error_category` or null, and measured `latency_ms`. A completed result has `check_id`, `ok`, `attempt_count`, `final_category`, and `completed_at`. An interrupted run has a reason and saved attempts but `result: null`.

An incident has `id`, `endpoint_id`, `state`, `reason`, `opening_check_id`, `opened_at`, nullable `acknowledged_by`/`acknowledged_at`, and nullable `recovery_check_id`/`recovered_at`. A support notice has `id`, `incident_id`, `check_id`, `event`, `audience`, `channel: in_app_demo`, and `created_at`.

Each uptime row has `endpoint_id`, `total_checks`, `passed_checks`, `failed_checks`, and `uptime_percent`. The response declares `basis: completed_check_ratio` and `window: current_dataset`. Percent is rounded to two decimals; zero checks yields null. Filters/limits on recent-result screens do not change these all-dataset counts.

## Client recovery contract

On a lost mutation response, retry the identical request with its original key and inspect the referenced resource. A replay has the original accepted body/status and `Idempotency-Replayed: true`; the current HTTP request still has its own `X-Correlation-ID`. If the original body contains its trigger correlation ID, retain it rather than rewriting stored evidence. Same-key/different-payload is 409. No resource is created for validation, denial, busy, or capacity errors.

On 401, return to the labeled demo login. On 403, retain the screen and explain the missing demo capability. On a network error or safe 500/503, preserve form data, show a retry action and correlation ID if received, and do not display a fabricated success. An accepted check is asynchronous: show its returned run, poll while running, and stop polling at COMPLETED/INTERRUPTED or on navigation. Backend execution continues independently of the browser.

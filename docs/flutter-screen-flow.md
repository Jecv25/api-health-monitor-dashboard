# Flutter Web screen-flow design

Status: implemented Flutter Web flow, first sketched in Stage 1. The original HTML prototype supplied navigation, labels, behavior, status pills, and feedback; its [behavior mapping](module13-submission.md#prototype-behavior-reference) is included in this submission. See the [navigation diagram](diagrams/screen-flow.md), [API contract](api-contract.md), and [actual Chrome evidence](../evidence/evidence-index.md).

## Navigation and prototype mapping

| Screen or view | Primary content and actions | Prototype relationship / API |
| --- | --- | --- |
| Login placeholder | Persistent “Local demo only; no real authentication” label, operator/viewer selector, Enter demo; no password field | Added to meet the requested Login and denial states; demo-session routes |
| Endpoint List | Name, fictional URL, last confirmed status, separate CHECKING indicator, behavior, last completion; Register, Run check, Run all, scheduler start/stop | Preserves Endpoints; `/endpoints`, `/scheduler`, check-trigger routes |
| Register endpoint | Name, fictional HTTPS URL, interval default 60, behavior selector; inline validation and submit progress | Preserves Register; `POST /endpoints`; remains a route/form within endpoint navigation |
| Endpoint Detail / Results | Endpoint summary, last confirmed health, active run and attempt timeline, completed results, interrupted-run notice, linked incident, Run check and Simulate fix | Added drill-down from list to make persisted results and retry/recovery observable; endpoint/results/check routes |
| Incidents | OPEN / ACKNOWLEDGED / RECOVERED, reason, opened/ack/recovery times, endpoint link, Acknowledge; persisted in-app support notices | Preserves Incidents; incident/notification routes; no manual recover action |
| Uptime Report | Total completed, passed, failed, ratio, labeled dataset window; “No data” when zero | Preserves report with persisted data and explicit sample-ratio meaning; `/reports/uptime` |
| Structured logs | Recent sanitized JSON lines, correlation filter, Copy logs, refresh | Preserves diagnostic view; `/logs`; omit prototype Clear action to preserve failures |
| Evidence guide | Three demo steps and what to preserve; references to approved docs; evidence links only after files exist | Preserves guide; no invented screenshots/logs or false completed status |

The five required primary screens are Login, Endpoint List, Endpoint Detail/Results, Incidents, and Uptime Report. Register, logs, and guide preserve useful reference behavior without adding new business workflows.

## Sketches and key interactions

At desktop width, use a left navigation rail and a main content area. Endpoint List begins with a heading, demo/environment label, scheduler state, and action bar above the endpoint rows. Selecting an endpoint opens Detail; its summary stays above the attempt/results sections. Incidents shows active state and acknowledgement alongside dates, with support notices below. The report explains its denominator before its table/cards.

At tablet width, navigation may collapse while actions wrap. At narrow width, use a drawer or compact navigation and endpoint/incident cards; keep primary actions visible and labels readable. Diagnostic JSON can scroll inside its panel. Do not require page-wide horizontal scrolling to register, check, acknowledge, or read a status. The chosen acceptance widths are 1280, 768, and 390 CSS pixels, not a device-compatibility claim.

Register validates locally before submission and displays authoritative server field errors beside the same fields. Trim names/URLs consistently; preserve typed values during navigation-safe refresh and errors. Disable duplicate submission while its request is pending. Keep the same mutation key across a lost-response retry; create a new one for a deliberate new submission. A duplicate URL error stays attached to URL.

After an accepted check, show the returned run ID and CHECKING state, then poll that run about once a second until completion/interruption. Attempts and retries appear as they are saved. Stop polling on navigation/disposal; server work continues. Refresh relevant list/detail/incident/report data after completion, acknowledgement, fixture change, or explicit refresh. There is no UI timer that independently performs health checks.

Simulate fix is visible as a demo control to the operator. Explain that it changes future fixture responses, then prompt the user to run a check. Keep DOWN/active incident visible until a passing result commits. Acknowledge records responsibility; success feedback must not say “fixed.” An incident badge counts OPEN, unacknowledged incidents and is labeled accordingly; ACKNOWLEDGED remains active in the incident view.

Run all displays an admission summary: accepted runs, already-busy endpoints, and capacity-blocked endpoints. With two worker slots it may not start every endpoint immediately. Do not silently report “all passed” or invent a queue. The three evidence demos use individual Run check actions.

## Required visible states

| State | Expected UI behavior |
| --- | --- |
| Loading | Labeled progress indicator/skeleton; relevant action disabled; preserve existing content during refresh |
| Success | Render committed API state; polite status announcement for registration, acknowledgement, and verified recovery |
| Empty | Endpoint list: Register action; results/report: No checks/No data; incidents/logs: no records yet with next step |
| Validation | Inline field errors, focus first invalid field, retain all input, no success notification |
| Authentication placeholder | Missing/expired demo session returns to labeled login; explain that restart may require a new selection |
| Forbidden | Safe 403 message and retained read view; operator actions disabled/hidden for viewer as a convenience, with server denial still authoritative |
| Network failure | Explain that the backend could not be reached; retain inputs/last confirmed data, offer retry, show uncertainty for a lost mutation response |
| Server/storage error | Show safe message and correlation ID; keep previous confirmed content; no fabricated result, incident transition, or recovery |
| Dependency failure | Saved failed attempts/result, DOWN status, linked active incident and next human step |
| Interrupted run | Explicit interruption notice with run ID; UNKNOWN current health until verified; older results remain visible |
| Stale view | Label last refreshed/completed time and offer refresh; old confirmed status is not presented as a current successful check |

## Reusable components and accessibility

Plan an API client that consistently handles cookie credentials, safe errors, correlation IDs, and mutation keys. Reuse the navigation shell, status chip with text, labeled form fields, loading/empty/error panel, endpoint card/row, attempt timeline, incident card/row, and timestamp formatter. Domain state and async calls stay separate from widget layout.

Use keyboard-operable navigation/actions, readable labels, logical focus order, visible focus, semantic status text, sufficient text/background contrast, and polite live announcements. Do not communicate UP/DOWN only through color. Display timestamps with timezone; preserved evidence uses UTC or an explicit offset. No internal stack trace, filesystem path, cookie, or secret belongs in a user-facing error or log panel.

Stage 3 verification covers the normal path, local/server validation agreement, empty/loading/error states, viewer restrictions, attempt/recovery visibility, and the three widths. Stage 4 preserves actual screenshots with matching API and backend evidence. The original Stage 1 had no browser execution; the implemented client has now been checked in installed Chrome. This does not establish cross-browser or full accessibility certification.

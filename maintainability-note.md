# Maintainability note — Module 13

The design keeps automation policy in one backend service and leaves Flutter responsible for presentation. This makes the three-attempt rule and incident lifecycle explainable without tracing duplicate logic through every screen.

| Change or concern | Owner/location | Reason and verification |
| --- | --- | --- |
| Timeout, retry delay, capacity | `backend/src/config.js`, `monitor.js`, `.env.example` | Centralized bounded settings; startup validation and real retry/timeout tests |
| Input contract | `backend/src/errors.js`, `flutter_web/lib/validation.dart`, `docs/api-contract.md` | Client gives quick feedback; server rejects direct invalid calls independently |
| Persistence/idempotency | `storage.js`, mutation transaction in `app.js` | Unique running-check/active-incident/result/key constraints and atomic finalization prevent duplicate outcomes |
| Dependency integration | `fixture.js` and GET portion of `monitor.js` | Controlled real HTTP permits repeatable transient/permanent/timeout injection without public APIs |
| UI states/navigation | `flutter_web/lib/main.dart`, `api.dart` | Shared panels/status chips/API errors; responsive evidence and widget tests |
| Operations/evidence | Runbook and `backend/scripts/` | Repeatable timestamped runs, retained failures, source identity, actual request/log/database links |

Two actual improvements illustrate the maintenance boundary. A failing Flutter dropdown layout was fixed in the reusable login control and its surrounding wrapping layout; the original three failed widget cases passed on rerun. Browser selectors were then corrected to use Flutter accessibility labels and accommodate the incident badge. Those were test-driver failures, not an excuse to replace the actual Flutter screens. The failed runs remain available through [the evidence index](evidence/evidence-index.md).

Idempotency reconciliation was also made readable during an automation pause when SQLite is still accessible: the accepted replay lookup precedes the new-operation pause guard. A focused assertion checks that the same accepted run ID is returned without another execution after a controlled finalization failure. The final transaction fault demonstration uses an actual 200 response before rolling back, showing that an observed HTTP success alone cannot recover an incident when its result was not committed.

The evidence index/metrics give observed attempt counts, retry gaps, durations, interruption behavior, and scenario outcomes. Those observations support bounded local reliability, not sustained performance. The one-second dispatcher, synchronous small SQLite transactions, two worker slots, and absence of a waiting queue keep ownership small, but become limitations as volume grows. No benchmark or change-effort score is invented.

Current debt is explicit: the main Flutter screen/state file should be split into view files if it grows; there is no schema migration runner beyond the initial schema; logs/data need a deliberate archival policy; recovery uses one passing observation; identity remains a demo. Adding brokers, external alerts, or a full identity stack now would increase operational ownership beyond Module 13.

For a policy change, update the centralized value and contract first, run the affected automation case plus the normal/transient/permanent regression set, preserve any failure and rerun, and refresh the decision/runbook/evidence map. The student maintainer owns this sequence. A dependency upgrade requires reviewing official version documentation and lockfile changes before rerunning these checks.

Viva explanation: “I separated interaction, policy, transport, and saved state so I can change one concern and use the same evidence cases to detect unintended effects. The evidence states exactly which local behaviors were observed and which limits remain.”

# Maintainability, limits and residual risks

## Separation and ownership

The Flutter API client is separate from forms and shared presentation widgets. Backend configuration, data model, safe serialization, monitoring policy, HTTP routes, worker and controlled dependencies are separate modules. Manual and scheduled checks use the same `HealthRunner`; fixes to retry/recovery behavior do not require two implementations.

Support owns incident triage and service repair. Developers maintain endpoint approvals, code, automated checks, schema and dependencies. Supervisors review availability reports and exceptions. These describe workflow responsibilities; Week 13's shared operator capability does not implement individual roles.

## Routine maintenance

| Cadence / trigger | Task and verification |
| --- | --- |
| Before each demonstration | Start all components, check `/healthz`, verify a healthy sample and the current operator key |
| After policy changes | Run the original transient, permanent and recovery tests; update policy and evidence map |
| After model changes | Review an explicit schema migration; export DDL/OpenAPI and preserve existing incident records |
| After Dart changes | Run state tests and rebuild web without `-SkipBuild`; verify desktop/narrow layouts |
| Each dependency update | Review release/security notices, update lock files deliberately, rerun regression tests |
| Each laboratory session | Review the heartbeat and error logs; keep generated credentials out of submissions |
| Before handing over | Export source/evidence ZIP; verify no secrets; have the student reproduce one failure and recovery |

## Limitations and residual risks

- Local, controlled Week 13 prototype. Full user authentication, individual RBAC, HTTPS deployment, session lifecycle and stronger secret storage are Week 14 work. Read-only lab data is accessible to anyone who can reach the loopback API; the shared operator key provides no individual attribution.
- Loopback is the default bind for every local service. The prototype must not be exposed publicly with its lab settings.
- One scheduler worker is assumed. MySQL per-endpoint locks still prevent simultaneous checks if another process is accidentally started, but there is no distributed queue, fairness guarantee or catch-up SLA.
- Checks are processed sequentially by the worker. Total sweep time grows with endpoint count and timeout/retry duration. The 50-endpoint registration cap is a classroom guard, not a tested production capacity claim or atomic multiwriter quota.
- Pause stops future checks; an already running request may finish. A changed allowlist is enforced at execution, and rejected scheduled work is logged for maintenance; it is not silently sent to a new destination.
- Health requests inspect status only. Application semantics, payload correctness, endpoint authentication, DNS rebinding protections and generalized private-network egress rules require further design before adding external targets. Only explicitly approved classroom origins are configured by default.
- TLS validation remains enabled for HTTPS targets, but the supplied local demo transport is HTTP. The allowlist must be reviewed server-side; never allow arbitrary user-selected hosts.
- In-app notifications are persisted transactionally with incident changes. Email/SMS delivery and notification escalation deadlines are outside this increment.
- Uptime is **sampled completed-cycle success**, not time-based downtime or SLA availability. Manual checks also contribute. Unknown/no samples is displayed honestly.
- An abrupt worker exit can leave a `running` row until that endpoint is checked again. Reconciliation records `interrupted`, and history/reporting retains the evidence. A watchdog and independent crash notification are future improvements. Idempotency records currently have no automatic expiry.
- Heartbeat staleness threshold is 90 seconds; an abruptly terminated worker can appear online until it expires.
- History/incident/notification endpoints return bounded recent records, not complete paginated archival exports. Log rotation, retention, database backups and restore testing remain maintenance tasks; raw local logs can grow.
- `create_all` initializes a new database but is not a migration system. Use reviewed migrations for future schema changes; the initial timestamp-precision fix is documented in the issue record.
- The portable lab runtime uses Python 3.12.10 and MySQL 8.4.8 for reproducibility, not a current production patch certification. Review supported patched releases before any deployment. The installed HTTP test stack emits a Starlette/httpx deprecation warning; recorded tests pass, and migration should accompany a deliberate dependency update.
- Running database files must remain local; OneDrive synchronization is unsuitable for a live MySQL data directory. Stop and back up before moving the project.
- No actual stakeholder UAT, peak-load evidence, environment comparison, HTTPS deployment, rollback certification or individual viva is claimed. Those belong to Weeks 14–18.

## Conditional recommendation

Suitable for controlled Week 13 laboratory demonstration when the saved acceptance checks pass and only the fictional allowlisted services are enabled. The recommendation is conditional on local-only operation and student reproduction of the evidence. Reassess after security integration, capacity measurement, backup/restore rehearsal and stakeholder UAT.

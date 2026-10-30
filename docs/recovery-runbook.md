# Recovery runbook — controlled Week 13 environment

## Failure taxonomy

| Failure | Retry | Safe outcome / ownership |
| --- | --- | --- |
| HTTP 408/429/5xx | Up to 2 retries | Exhaustion opens/reuses incident, notifies support |
| Timeout/network connection | Up to 2 retries | Bounded error code; no raw diagnostics shown to browser |
| Other unexpected status including redirects | No retry | Failed cycle; support investigates configuration/dependency |
| Invalid/unapproved endpoint | No outbound request | 422 and no registration |
| Missing/invalid operator capability | No mutation | 401; reconnect with local key |
| Duplicate manual submission | No repeated execution | Return stored run for original idempotency key |
| Concurrent check | No overlapping execution | 409; wait and refresh |
| Worker interruption | Resume due work on restart | Connection-scoped lock is released; next run reconciles unfinished records |
| MySQL unavailable | No invented success | API returns safe 503; inspect local logs and restart database |

## Controlled transient case

Check Orders API. The controlled service returns 503 when `X-Check-Attempt` is 1 and 200 on the next attempt. Expect `transient_recovered`, two persisted attempts, no incident if the service had no active outage. Inspect history plus matching `run_id`/`correlation_id` in the evidence logs.

## Persistent outage routed for human action

Billing details → Reset demo outage → Check now. Expect exactly three attempts, a failed cycle, one active incident assigned to support and an in-app human-action notification. Further failed cycles reuse the incident. Support acknowledges using a fictional alias and a bounded note. Acknowledgement means ownership; it does not mean repair or recovery.

## Verify recovery

Billing details → Repair demo service. Run one check: endpoint becomes `recovering` and the active incident remains. Run the second successful check: incident becomes `recovered`; exactly one recovery notification is created. If a failed cycle occurs between successes, the streak resets to zero. The service never repairs a production dependency automatically.

## Worker restart

Stop this project's application processes while preserving MySQL using `stop-local.ps1 -KeepDatabase`. Restart with `start-local.ps1 -SkipBuild`. Registrations, incidents and due times persist. The worker checks due enabled services once, schedules the next cycle from completion time, and does not replay every missed interval. `scripts/verify_worker.py` captures actual independent-process and restart evidence using explicit controlled due-time injection.

## Local storage restart / fallback

Use the supplied stop/start scripts to stop MySQL cleanly and restart it with the same `.runtime/mysql-data`. Never delete that directory as a troubleshooting shortcut. A backup/restore or deployment rollback rehearsal beyond this local restart remains Week 16 work.

If live demonstration is unavailable, open the saved browser screenshots, HTTP request/result evidence and structured logs under `evidence`, then walk through the matching source and API contract. These are historical observed results, not a substitute claim that an unavailable service is currently running.

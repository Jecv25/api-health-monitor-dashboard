# Module 13 automation/configuration checklist

This checklist addresses Topic 4's bounded automation controls. Real identity, account administration, deployed TLS, and Module 14 cryptography are deferred.

| Check | Submitted control / evidence | Limit |
| --- | --- | --- |
| Fictional inputs and approved boundary | Fixed fictional namespace, fixed loopback fixture origin; direct invalid URL/type/field tests | Does not verify an internet HTTPS endpoint |
| Server authority | Express rejects invalid direct requests, missing sessions, and viewer mutations; I01/U01/U02 records | Selectable demo identity is not trustworthy real authentication |
| Configuration outside source logic | `backend/.env.example`, centralized `config.js`, optional ignored `.env` | Current lab needs no confidential dependency credential |
| Startup bounds | Loopback/demo-mode check, maximum three attempts and two workers, validated numeric settings | Single-process local operation only |
| Client data minimization | No password prompt or embedded secret; HttpOnly in-memory-session cookie; no cookie persistence in evidence | Cookie transport is local HTTP, not a production security claim |
| Safe logs | JSONL events with UTC/server correlations and IDs; no cookie/token/raw body fields in actual logs | DB/file logs have separate commit boundaries |
| Repeatable failure controls | Controlled fixture response sequences, actual timeout, internal transaction fault, actual child-process crash | Fault hooks are lab/test tools, not public repair/fault APIs |
| Duplicate control | Accepted response and domain write commit together; uniqueness constraints; replay/conflict/overlap tests | Does not guarantee exactly-once external delivery |
| Dependency control | npm/pub lockfiles and recorded toolchain; only Express plus browser-test driver on Node side | Dependency review/upgrade work remains maintainer-owned |
| Preservation and ownership | Failed runs retained; runbook names operator and maintainer; actual source snapshots/feature branch | No automatic archival or disk-capacity management |

See [configuration audit](../evidence/configuration-audit.json), [the evidence index](../evidence/evidence-index.md), [recovery runbook](recovery-runbook.md), and [limitations](../limitations.md). Do not treat an example configuration as evidence that a real secret was protected; none is required or used.

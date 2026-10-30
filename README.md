# Pulsewatch — API Health Monitoring Dashboard

**Week 13 / SA7 student prototype.** Flutter Web (Dart), FastAPI (Python), MySQL 8.4, SQLAlchemy/PyMySQL, APScheduler and HTTPX. All bundled demonstration services and operator aliases are fictional. Primary academic reference: `PFEBSIT_002_Weeks_13-18_Student_Module_Flutter_Web.docx`, Module 13. The user's project brief supplies the service-monitoring scenario and MySQL decision.

## Para sa baguhan: paano patakbuhin

Buksan ang terminal sa mismong project folder. Available na sa kasalukuyang computer ang project-local Python, MySQL, backend dependencies, at Flutter build. Walang kailangang baguhin sa XAMPP database.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local.ps1 -SkipBuild
```

Buksan ang **http://localhost:8080**. Para makapag-register, mag-check, at mag-acknowledge:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\copy-operator-key.ps1
```

I-click ang **Connect operator**, i-paste ang nakopyang key, at i-click ang **Connect**. Session memory lang ang key; kailangang kumonekta ulit pagkatapos mag-refresh ng browser. Huwag isama ang key o `backend/.env` sa screenshots o submission.

API documentation: **http://127.0.0.1:8000/docs**. MySQL: `127.0.0.1:3307`, database `pulsewatch`. Ang `pulsewatch_test` ay hiwalay na database para sa automated tests.

Para ihinto ang project at ma-preserve ang database:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
```

## Setup sa ibang Windows computer

Prerequisites: installed Flutter SDK with web support on `PATH`, Microsoft Edge or Chrome, internet for dependency downloads, and ports 3307, 8000, 8080, 9001 available. Portable MySQL may also need the Microsoft Visual C++ x64 runtime if it is not already installed. The scripts download Python and MySQL into `.tools`; they do not register a Windows database service or edit your XAMPP installation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local.ps1
```

Setup generates fresh local secrets and the two databases. First startup builds Flutter; after Dart source changes, run startup **without** `-SkipBuild` to rebuild. Stop an existing run before starting another. Keep the `.runtime/mysql-data` directory on a local filesystem; do not sync or copy a running database through OneDrive. Use MySQL backup tooling for transport.

## Ano ang gumagana

- Register allowlisted endpoints with validated interval (15–3600 seconds), timeout (1–10 seconds), and support ownership; duplicate URLs are rejected.
- A separate worker schedules checks from MySQL due times, with heartbeat and no dependency on an open browser.
- A manual or scheduled check has at most three attempts, with bounded exponential delays, outer request deadlines and recorded attempts.
- Persistent failure opens one incident and a durable human-action notification. Support acknowledges it; two consecutive successful cycles verify recovery and publish one recovery notification.
- MySQL advisory locks exclude overlapping runs. An `Idempotency-Key` deduplicates resubmitted checks. Interrupted runs become visible failed/interrupted records on the next check.
- Responsive Flutter overview, registration, endpoint history, incident acknowledgement, notifications and sampled-uptime reports.
- Safe errors, structured JSON logs and a generated local operator capability provide Week 13 boundary controls. Full accounts, individual roles and HTTPS are **Week 14 work**.

## Quick demonstration

1. Connect the operator and click **Add demo services** in the empty state. If services already exist, inspect the controlled service rows.
2. **Gateway API**: check succeeds in one attempt.
3. **Orders API**: first attempt is 503, second is 200; open details to inspect both attempts.
4. **Billing API**: open details → **Reset demo outage** → **Check now**. Three 503 attempts create an incident and a human-action notification.
5. Open **Incidents** → **Acknowledge**. Use the fictional `support-demo` alias. This does not close the outage.
6. Billing details → **Repair demo service** → **Check now**. One successful cycle shows `recovering`; a second successful cycle marks the incident `recovered`.
7. Open **Notifications** and **Reports**. Reports label observed check availability, not time-based SLA uptime.

Scheduled checks may advance these scenarios while you demonstrate. For a strictly manual, repeatable recording, stop the app and start with `-SkipBuild -NoWorker`; then demonstrate the worker separately.

The fictional Billing service starts unavailable whenever the demo-service process restarts. Its repair switch is in memory; monitoring history and incidents remain persisted in MySQL.

## Reproduce verification

These backend tests modify **only `pulsewatch_test`**. They use real MySQL and an HTTPX-controlled service transport. The HTTP and worker demonstrations use actual loopback services and `pulsewatch` fictional records.

```powershell
.\.tools\python\python.exe -m pytest backend/tests -q
Set-Location frontend
flutter test
Set-Location ..
.\.tools\python\python.exe scripts/export_contract.py
```

With local services running using `-NoWorker`:

```powershell
.\.tools\python\python.exe scripts/demo_week13.py
.\.tools\python\python.exe scripts/verify_worker.py
```

For optional browser capture, install `backend/requirements-qa.txt` into the same Python runtime and run `scripts/capture_browser.py`. It uses installed Edge, registers the controlled `healthy-ui` service on its first run, and explicitly records service reuse on later runs. After the HTTP demo, `scripts/capture_recovery.py` captures the actual Flutter acknowledgement/recovery flow and an intercepted API-unavailable/reconnect scenario. Existing screenshots and expected/actual records remain available as a fallback.

## Project map

| Location | Purpose |
| --- | --- |
| `frontend/lib` | Flutter presentation, forms, shared widgets and API client |
| `frontend/test` | Widget/state and API-client tests |
| `backend/app/main.py` | Versioned API implementation and safe errors |
| `backend/app/monitor.py` | Shared check/retry/incident/recovery service |
| `backend/app/worker.py` | Independent scheduled worker |
| `backend/app/demo_service.py` | Controlled fictional dependencies and repair controls |
| `backend/app/models.py` | MySQL data model, including microsecond UTC timestamps |
| `backend/tests` | Reproducible functional and adverse-case checks |
| `backend/.env.example` | Configuration names without credentials |
| `database/schema.sql` | MySQL DDL generated from the models |
| `docs/openapi.json` | Exported OpenAPI contract; live Swagger is at `/docs` |
| `docs/week13-design.md` | Workflow boundary, trigger/retry decisions, criteria and screen flow |
| `docs/architecture.md` | Architecture, ER and sequence diagrams |
| `docs/recovery-runbook.md` | Controlled failure and recovery instructions |
| `docs/maintainability.md` | Ownership, maintenance, limitations and residual risks |
| `evidence` | Expected/actual results, original failures, reruns and screenshots |

## Troubleshooting

- **Cannot reach API**: use startup, inspect `.runtime/api.stderr.log`, and open `/healthz`. The dashboard keeps a visibly stale view after a failed refresh.
- **Worker offline**: start without `-NoWorker`; check `.runtime/worker.stderr.log`. Heartbeat becomes stale after 90 seconds, so abrupt exit detection is delayed.
- **401**: copy the current local key and reconnect. Full JWT login is not part of this SA7 increment.
- **409 check in progress**: another worker/request owns this endpoint's lock. Wait and refresh; avoid repeated clicks.
- **MySQL stopped**: rerun startup. Database files and recorded incidents are preserved; no automatic delete/reset is performed.
- **Port already used**: stop only this project's processes with the stop script. Resolve unrelated port conflicts before restarting; the database provisioner checks the actual data-directory identity.
- **Flutter not found**: reopen the terminal after adding the installed Flutter `bin` directory to your `PATH`.
- **Execution policy**: the shown commands set policy only for the launched PowerShell process.

## Submission and honesty

Run `.\.tools\python\python.exe scripts/package_submission.py` to produce a source-and-evidence ZIP that excludes `.env`, portable tools, runtime database files and raw local logs. Build artifacts can be regenerated from source. Read `evidence/README.md` and `docs/contribution-record.md` before submitting. Student review, institutional approval, individual viva and personal contribution reflection remain the student's responsibility.

This is a controlled Week 13 prototype, not a production-readiness claim. Remaining Week 14–18 work and current limits are documented in `docs/maintainability.md`.

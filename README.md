# API Health Monitoring Dashboard — Module 13

Pulseboard is a **local student prototype** for Advanced Automation and Scripting (SA7). It registers fictional endpoints, schedules real local HTTP checks, retries at most three total attempts, saves results in SQLite, routes failures to a human through incidents, verifies recovery, and reports completed-check success ratios.

Only the Module 13 (SA7) submission is included. Requirements were checked against the Module 13 section of `PFEBSIT_002_Weeks_13-18_Student_Module_Flutter_Web.docx` and the Week 13 scope in `My_Project.md`. See [the submission scope and requirement map](docs/module13-submission.md). Modules 14–18 are deferred. The selectable operator/viewer login is a demo placeholder, not real authentication. This submission makes no broader operational-readiness claim.

## Run the dashboard

Requirements: Node.js **24.x**, npm, Flutter with Web support, and Chrome/Edge. The verified toolchain and dependency versions are recorded in [the evidence index](evidence/evidence-index.md). Keep this project on the local machine; no cloud account or secret is needed.

Clone the repository, then prepare the Flutter build and backend dependencies:

```powershell
git clone https://github.com/Jecv25/api-health-monitor-dashboard.git
Set-Location api-health-monitor-dashboard
Set-Location flutter_web
flutter.bat pub get
flutter.bat build web --release --no-web-resources-cdn
Set-Location ../backend
npm.cmd ci
npm.cmd start
```

Open **http://localhost:3000** and choose **Operator**. The backend serves the compiled Flutter app and the API from the same origin. Build output and dependencies are generated locally; they are excluded from Git. After the initial setup, `npm.cmd start` in `backend/` is sufficient. Stop with Ctrl+C. The scheduler starts OFF on every process start.

`npm.cmd` avoids PowerShell's unsigned `npm.ps1` execution-policy error. Do not change the machine's execution policy for this project. If port 3000 or fixture port 4001 is occupied, copy `backend/.env.example` to `backend/.env` and select unused ports. Read [backend setup](backend/README.md) before changing policy values. Use only nonsecret lab settings.

For Flutter development with hot reload, run the backend in one terminal and this command in `flutter_web/` in another:

```powershell
flutter.bat run -d chrome --web-hostname localhost --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

Use the same hostname (`localhost`) for browser API/client URLs so the demo cookie behaves consistently. [Flutter client notes](flutter_web/README.md) explain the screen states and limitations.

## Demonstrate the workflow

1. **Success:** Library API → View results → Run check. Expect one real HTTP 200 attempt and one passed observation.
2. **Transient recovery:** Enrollment API → Run check. Expect 503, 503, 200 with two 700 ms waits; the completed check passes without opening a new incident.
3. **Persistent failure / human action:** Payments sandbox → Run check. Three 503s open one incident. In Incidents, Acknowledge; return to the endpoint, Simulate fix, then Run check. Only the new passing check recovers the incident and records an in-app support notice.

Run all admits up to two simultaneous checks and reports the endpoints it could not admit. It creates no hidden queue. An enabled scheduler checks due endpoints later, honoring each endpoint's 10–3600 second interval (default 60). Acknowledgement accepts responsibility; it does not mark a dependency healthy.

The displayed `https://api.sandbox.example/.../health` URLs are fictional labels. Backend checks actually GET a fixed loopback HTTP fixture. They never contact that fictional host or arbitrary internet services. Fixture failures are injected; HTTP requests, measured latencies, attempts, database outcomes, screenshots, and logs are real. Notifications are saved in-app demo notices, not email/SMS.

## Verify and reproduce evidence

Run these commands from `backend/`:

```powershell
npm.cmd test
npm.cmd run evidence
npm.cmd run evidence:restart
npm.cmd run evidence:browser
npm.cmd run verify
node scripts/summarize-evidence.js
```

The browser evidence command uses installed Chrome; set `CHROME_PATH` to its executable if needed. `verify` also requires Flutter on PATH. Commands write new timestamped directories and retain failures. They do not delete or reset earlier evidence. Scripts start isolated loopback servers and close them after each run. Default-policy demonstrations use 3 attempts, 700 ms waits, and 3,000 ms timeouts; a focused unit/integration test explicitly uses a shorter timeout and labels its configuration.

Read [evidence-index.md](evidence/evidence-index.md), [lab-log.md](evidence/lab-log.md), [maintainability-note.md](maintainability-note.md), and [limitations.md](limitations.md). Acceptance criteria are in [docs/acceptance-criteria.md](docs/acceptance-criteria.md); the design map is [docs/README.md](docs/README.md). Failed Flutter and browser automation runs remain alongside corrected reruns.

## Files and ownership

| Location | Responsibility |
| --- | --- |
| `backend/src/` | Validation/access boundaries, Express API, SQLite, scheduler, retry, fixture, logging |
| `backend/test/` | Focused Module 13 automation checks |
| `backend/scripts/` | Repeatable API/browser/restart evidence and validation capture |
| `flutter_web/` | Actual Flutter Web source, configuration, and widget tests; release output is generated locally |
| `docs/` | Workflow, decisions, pattern comparison, policy, API/screen contracts, diagrams, criteria |
| `evidence/` | Actual requests/results/timestamps/logs/databases/screenshots, including failures |

The student maintainer owns configuration, fixture behavior, evidence preservation, and recovery. The demo operator acknowledges and investigates incidents. No real personal records or production credentials belong here. The [issue record](docs/issue-record.md) links observed failures to their fixes and reruns.

## Technical basis and acknowledgement

The implementation uses Node's built-in SQLite interface ([Node 24 SQLite documentation](https://nodejs.org/docs/latest-v24.x/api/sqlite.html)), Express JSON middleware and centralized safe errors ([Express API](https://expressjs.com/en/api/), [error-handling guide](https://expressjs.com/en/5x/guide/error-handling/)), and Flutter's async HTTP approach ([Flutter networking guide](https://docs.flutter.dev/cookbook/networking/fetch-data)). Exact package versions are locked in `backend/package-lock.json` and `flutter_web/pubspec.lock`. Existing installed Flutter/Chrome were used; monitoring remained within the controlled loopback fixtures.

Codex assisted with design, implementation, verification scripts, and documentation. The student must review the source/evidence, acknowledge assistance under institutional policy, and be able to explain and modify the work independently. Institution-provided module files and the prototype remain the source requirements.

# Module 13 submission scope and requirement map

This repository contains the API Health Monitoring Dashboard submission for **Module 13: Advanced Automation and Scripting (SA7)**. The requirements were checked against the Module 13 section of `PFEBSIT_002_Weeks_13-18_Student_Module_Flutter_Web.docx` and the Week 13 portion of `My_Project.md` supplied by the student. The full course documents are references, not repository deliverables.

## Included deliverables

| Module 13 requirement | Submitted artifact |
| --- | --- |
| Bounded problem, actors, ownership, dependencies, non-goals | [Workflow boundary](workflow-boundary.md), [boundary diagram](diagrams/workflow.md) |
| Alternatives and justified automation decision | [Decision record](decision-record.md) |
| Scheduled/event-driven comparison and trigger contract | [Pattern matrix](pattern-matrix.md) |
| Failure categories, three-attempt bound, recovery and human action | [Retry/recovery policy](retry-and-recovery-policy.md), [runbook](recovery-runbook.md), [incident lifecycle](diagrams/incident-state.md) |
| Flutter Web screen flow and API contract | [Screen flow](flutter-screen-flow.md), [navigation diagram](diagrams/screen-flow.md), [API contract](api-contract.md) |
| Working bounded automation and result persistence | `backend/src/`, `backend/package.json`, `backend/package-lock.json` |
| Flutter Web source, responsive workflow and feedback | `flutter_web/lib/`, `flutter_web/web/`, widget tests and [Chrome evidence](../evidence/evidence-index.md#actual-browser-walkthrough) |
| Protected configuration, authoritative validation, safe correlation logs | `backend/.env.example`, configuration/validation/logging source, [configuration checklist](automation-configuration-checklist.md) |
| Normal, invalid, unauthorized, dependency failure and recovery criteria | [Acceptance criteria](acceptance-criteria.md) |
| One success plus at least four adverse executions | [Evidence index](../evidence/evidence-index.md): N01, I01, U01, D01, D02 and supporting cases |
| Three demonstrations: success, retry recovery, persistent failure routed to a person | [Three captured demos](../evidence/evidence-index.md#latest-api-cases), actual browser screenshots and mutation records |
| Controlled failure, prediction, actual outcome, improvement and rerun | `evidence/runs/`, `evidence/validation/`, `evidence/browser/`, `evidence/restart/`, [issue record](issue-record.md) |
| Observable counts/timings, honest interpretation, maintainability | [Metrics](../evidence/metrics.json), [interpretation](../evidence/interpretation.md), [maintainability note](../maintainability-note.md) |
| Reproducible setup, lab log, index, limitations and technical explanation | [README](../README.md), [lab log](../evidence/lab-log.md), [evidence index](../evidence/evidence-index.md), [limitations](../limitations.md), [viva notes](viva-guide.md) |

The workflow is endpoint registration → manual/scheduled check → bounded retries → saved result → incident/acknowledgement → repair → passing recovery verification → check-based uptime report. Developers, fictional support operators, and read-only demo viewers are the intended actors.

## Prototype behavior reference

The original `api-health-monitor-prototype.html` was a screen/behavior reference. The actual submitted client is Flutter Web. The required behaviors are preserved here without publishing a second browser-only implementation:

- Library API: one healthy HTTP 200 attempt.
- Enrollment API: HTTP 503, 503, then 200 within one three-attempt check.
- Payments sandbox: persistent 503, one active incident, human acknowledgement, simulated repair, then a new check to verify recovery.
- Broken-path behavior: HTTP 404 stops immediately without retry.
- Registration, endpoint/results views, incidents, uptime report, structured logs, and demo guide are available in the Flutter client.
- The backend honors each endpoint's interval and persists records, replacing the prototype's global timer and in-memory browser state.

Registered HTTPS URLs are fictional labels. Actual backend GET requests go only to the fixed local HTTP fixture; the application does not claim to monitor a real external API. Support notifications are stored in-app demo notices.

## Excluded from publication

The original full course DOCX, combined Module 13–18 notes, raw teaching/reference Markdown, full project-brief copy, and original HTML prototype are not published. Their Module 13 requirements and provenance are represented by this requirement map and the original-file fingerprints in `evidence/publication-audit.json`.

The repository also excludes Node/Flutter dependency caches, SDKs, compiled Web output, editor state, private `.env`, and working backend databases/logs. The SQLite/log files under `evidence/` are identified fictional test snapshots, including interruption evidence; they are retained intentionally. Failed observations and their reruns are preserved unchanged.

There is no Module 14 real authentication/encryption implementation, Module 15 broad hardening campaign, Module 16 deployment/load evaluation, Module 17 UAT/formal OpenAPI completion, or Module 18 final-examination submission. Minimal validation, demo denial paths, logs, and focused adverse checks are included because Module 13 already requires them.

## Publication and evidence provenance

The original working directory already had a local baseline commit containing the full teaching references. This GitHub submission is prepared from a separate empty-repository checkout so those reference files are absent from the published commit history as well as the latest file tree. The original local branches and all local evidence remain intact.

Historical artifacts such as `evidence/source-control.json` describe the original local working copy. Those local commit IDs need not exist in the clean GitHub publication history. Per-run source hashes, requests, expected/actual outcomes, logs, screenshots, and timestamps are retained as captured. Publication checks are recorded separately and do not rewrite old test results.

The app is a local student prototype with a selectable demo login. The student must still review the evidence, acknowledge assistance under institutional policy, and provide truthful personal reflection and viva answers.

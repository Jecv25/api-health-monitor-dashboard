# Module 13 design and implementation map

Status: implemented as a local student prototype. Scope: Module 13, Advanced Automation and Scripting (SA7), only. Prepared and verified: 2026-10-30, Asia/Manila.

These documents began as the Stage 1 design. The user's later instruction to complete the whole Module 13 authorized Stages 2–4 together. The backend, actual Flutter Web client, and captured execution evidence now exist. Start with [the project README](../README.md) and [the evidence index](../evidence/evidence-index.md). Broader operational readiness has not been evaluated.

## Review map

| Artifact | Purpose |
| --- | --- |
| [Workflow boundary](workflow-boundary.md) | Actors, scope, data, trust boundaries, responsibilities, and non-goals |
| [Decision record](decision-record.md) | Choices, alternatives, tradeoffs, evidence needed, and viva explanations |
| [Pattern matrix and trigger contract](pattern-matrix.md) | Scheduled and event-driven alternatives; exact dispatch rules |
| [Retry and recovery policy](retry-and-recovery-policy.md) | Failure categories, three-attempt bound, idempotency, persistence, and observability |
| [Recovery runbook](recovery-runbook.md) | Human actions for outages, interruption, storage failure, and recovery |
| [API contract](api-contract.md) | Proposed routes, validation, response shapes, and error behavior |
| [Flutter screen flow](flutter-screen-flow.md) | Prototype mapping, reusable widgets, responsive behavior, and UI states |
| [Acceptance criteria](acceptance-criteria.md) | Measurable normal, invalid, unauthorized, dependency, and recovery cases |
| [Automation configuration checklist](automation-configuration-checklist.md) | Topic 4 controls and actual configuration/log audit |
| [Viva practice guide](viva-guide.md) | Brief explanations tied to implementation and evidence |
| [Boundary/data-flow diagram](diagrams/workflow.md) | Controlled services, trust boundaries, logs, and human ownership |
| [Check sequence](diagrams/check-sequence.md) | Retry, persistence, incident, and recovery paths |
| [Incident state diagram](diagrams/incident-state.md) | Acknowledgement and verified recovery rules |
| [Screen navigation diagram](diagrams/screen-flow.md) | Login placeholder through endpoint, incident, and report views |

## Source and scope traceability

The requirements were checked against the Module 13 section of the original course DOCX and the Week 13 portion of `My_Project.md`. The original introduction and HTML prototype informed the design. The [submission scope and requirement map](module13-submission.md) records that provenance and the included deliverables. Original teaching files and the full Weeks 13–18 documents are kept outside this GitHub submission; later-week requirements are not implemented here.

| Module 13 requirement | Stage 1 location | Later verification within this project |
| --- | --- | --- |
| Topic 1: boundary and decision | Workflow boundary, decision record, workflow diagram | Stage 2 backend path; Stage 3 browser path |
| Topic 2: pattern comparison and trigger | Pattern matrix | Scheduler timestamps and duplicate-trigger checks |
| Topic 3: failure taxonomy, retry, recovery | Retry policy, runbook, incident diagram | Three demos and interruption/recovery checks |
| Topic 4: protected configuration and safe boundaries | Workflow boundary, API contract, decision D5 | Stage 2 `.env.example`, authoritative validation, denial/log checks |
| Topic 5: observability and maintainability | Retry policy, decision D6, acceptance criteria | Actual counts/timings/logs and maintainability note in Stage 4 |
| Hands-on Part 1: Flutter sketch and acceptance | Flutter screen flow, acceptance criteria | Stage 3 browser states and Stage 4 recorded evidence |
| Hands-on Parts 2–3: working output and honest evidence | Acceptance/evidence recording plan | Stages 2–4 after separate approvals |

## Stage disposition

1. Stage 1: design documents completed; the requested approval pause was observed.
2. Stage 2: Express + SQLite backend, controlled fixture, configuration example, and focused backend tests implemented.
3. Stage 3: actual Flutter Web client implemented and release-built; widget and Chrome workflow checks captured.
4. Stage 4: actual requests/results/timestamps/logs, three demos, adverse cases, injection/restart proof, and portfolio notes captured. Failed runs remain preserved.

Implementation is in `backend/` and `flutter_web/`; actual execution artifacts are in `evidence/`. The folder originally had no Git repository. A local baseline/feature branch is prepared for handoff after implementation; this does not invent earlier development history. Per-run SHA-256 inventories, runtime versions, commands, and actual timestamps identify the captured builds independently of Git.

The implemented choices are a single-process scheduler that honors each registered interval; three total attempts with a fixed 700 ms retry delay; controlled local HTTP fixtures behind fictional HTTPS labels; and a freely selectable demo session for denial-path demonstration. Each choice and its limitation is explained in the decision record.

AI assistance: these design documents were drafted with Codex. The student must review them, verify later implementation and evidence, and acknowledge assistance under the institution's policy.

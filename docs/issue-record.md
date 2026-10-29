# Module 13 issue record

These entries summarize observed issues already preserved in the laboratory evidence. Resolution does not delete or replace the original failure.

| ID | Actual issue | Disposition | Evidence |
| --- | --- | --- | --- |
| M13-01 | Flutter login dropdown/layout overflow caused the initial three widget cases to fail | Expanded/ellipsized options and wrapping layout; original cases passed on rerun | [Failed reproduction](../evidence/validation/2026-10-29T17-41-33-306Z-reproduced-layout-failure/results.json), [passing rerun](../evidence/validation/2026-10-29T17-42-48-674Z-layout-fix/results.json) |
| M13-02 | Browser driver could not locate rendered Flutter content through ordinary DOM text | Driver uses Flutter accessibility labels; final actual-client walkthrough passed | [Initial failure](../evidence/browser/2026-10-29T17-45-53-406Z/summary.json), [final walkthrough](../evidence/browser/2026-10-29T18-00-44-208Z/summary.json) |
| M13-03 | Incident badge altered a navigation accessible name; a submit selector selected navigation instead of the form action | Corrected selectors and reran affected/dependent browser cases | [Failed walkthrough](../evidence/browser/2026-10-29T17-48-15-119Z/summary.json), [passing walkthrough](../evidence/browser/2026-10-29T18-00-44-208Z/summary.json) |
| M13-04 | Initial npm/Flutter/smoke setup commands encountered environment restrictions or a missing temporary-data parent | Used the Windows npm executable, approved SDK/network execution, and explicit test-directory creation | [Setup record](../evidence/setup-issues.md), [final validation](../evidence/validation/2026-10-29T17-57-09-358Z-final-verification/results.json) |
| M13-05 | HTTP success must not imply recovered state when the result transaction fails | Controlled pre-commit fault verifies rollback, preserved attempt, interrupted run, paused automation, and no false recovery notice | [Actual F02](../evidence/runs/2026-10-29T18-00-20-548Z/F02.json) |

Open limitations include selectable demo identities, one-process SQLite ownership, one-check recovery threshold, and deliberate log/data archival. These are stated in [limitations](../limitations.md), with a realistic improvement in the [maintainability note](../maintainability-note.md). Later-module work is not silently treated as completed here.

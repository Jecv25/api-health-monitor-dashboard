# Module 13 laboratory log

Scope: local API Health Monitoring Dashboard, Module 13 only. All services/data are fictional. The user first requested Stage 1 only, then explicitly authorized completing the whole Module 13; later stages therefore proceeded without another approval pause.

## Environment and identity

Node.js 24.x, installed Flutter 3.47.8 / Dart 3.13.7, Windows, installed Chrome, locked npm/pub dependencies. Exact runtime/OS/source hashes accompany each execution; the latest validation includes raw Flutter toolchain output. UTC timestamps are real execution-clock readings; add eight hours for Asia/Manila. No commit/revision timestamp is invented.

## Observations and improvements

1. Read the brief, introduction, Module 13, and HTML reference. Wrote the boundary, decisions, pattern comparison, retry/recovery policy, runbook, API/screen contracts, diagrams, and acceptance criteria before application code.
2. Implemented Express + SQLite + a real loopback HTTP fixture, then Flutter Web. Initial setup hit PowerShell npm.ps1 execution policy, restricted npm network access, and an unprivileged Flutter-cache lock loop. Used npm.cmd and approved SDK/network execution; did not change machine execution policy. One smoke command initially failed because its temporary-data parent did not exist. See setup-issues.md; no application check was claimed from that failed command.
3. Ten backend checks passed on the first test suite run, including actual retry gaps, 10/60-second scheduler behavior, duplicate/capacity control, timeout handling, and rollback. Raw final reruns and closed test databases are retained in validation/.
4. Initial Flutter widget tests failed on dropdown/layout overflow. Preserved a complete reproduction in the timestamped reproduced-layout-failure directory. Added expanded/ellipsized dropdown options and wrapping scheduler status; the same three tests then passed. Later added first-invalid-field focus and removal of the boot status after first frame.
5. The first browser automation run could not locate rendered Flutter text using plain DOM text. The saved screenshot shows the real login; the run remains FAIL. Updated the driver to use Flutter accessibility labels. The next run exposed the incident-badge name mismatch and a registration submit selector that clicked navigation; preserved those failures and corrected the driver. Subsequent complete walkthroughs passed the actual success/transient/persistent-recovery/report/responsive/invalid/network/server-error cases.
6. Strengthened rollback evidence: after changing a failed endpoint to healthy behavior, injected a transaction fault after the actual HTTP 200 result insertion but before commit. No final result/recovery notice was committed and the active incident stayed OPEN. Retained the earlier result-rollback run too. Idempotent accepted-response lookup is allowed while automation is paused, and a focused test verifies it.
7. Captured actual process interruption by killing only a backend child created by the restart script, then restarting on its same database. The previous session failed, the old attempt survived as INTERRUPTED, no result was invented, original-key replay referenced the old run, and a new-key run completed normally.

## Latest execution references

- API demos/adverse cases: [summary](runs/2026-10-29T18-00-20-548Z/summary.json).
- Actual Flutter walkthrough/screenshots: [summary](browser/2026-10-29T18-00-44-208Z/summary.json).
- Actual process recovery: [C01](restart/2026-10-29T18-00-20-589Z/C01.json).
- Complete checks/build and exact execution times: [results](validation/2026-10-29T17-57-09-358Z-final-verification/results.json).

## Interpretation and remaining limits

Observed outcomes support this controlled local automation workflow. They do not establish internet-service availability, secure real identity, sustained-load capacity, external notification delivery, cross-browser certification, or production deployment. The full limitation list and maintainability discussion are linked from the evidence index. Failed observations are retained with their disposition; a passing rerun does not rewrite them.

AI assistance: Codex assisted with implementation, tests, and documentation. The student must verify the artifacts, acknowledge assistance, and provide their own individual contribution/reflection under the institution’s policy.

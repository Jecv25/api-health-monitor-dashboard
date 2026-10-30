# Preserved setup issues

These issues were actually observed during this session. Exact timestamps of the first exploratory commands were not captured; this file does not invent them. Subsequent validation/evidence runs have precise UTC timestamps in their records.

| Command / situation | Actual observation | Disposition |
| --- | --- | --- |
| `npm --version` in PowerShell | `npm.ps1 cannot be loaded because running scripts is disabled on this system` | Used `npm.cmd`; did not alter execution policy |
| Initial unprivileged `flutter.bat --version` | No version output; installed SDK's batch cache-lock loop could not write its normal cache under restricted execution | Approved installed-SDK invocation succeeded: Flutter 3.47.8, Dart 3.13.7 |
| First `npm.cmd install --no-audit --no-fund --cache .npm-cache` | Exit 1, `EACCES`; request to npm's Express registry endpoint failed | Approved network invocation installed dependencies successfully; lockfile retained |
| First ad hoc backend smoke command | Exit 1, `ENOENT` when `mkdtemp` was called under a not-yet-created `backend/data/` directory | Test harness explicitly creates the parent before its temporary dataset; no successful runtime claim came from that smoke command |
| First Flutter widget tests | Three failures, including `A RenderFlex overflowed by 127 pixels on the right` and narrow layout overflow | Full reproduced failure is preserved in `validation/2026-10-29T17-41-33-306Z-reproduced-layout-failure/`; layout fix and passing rerun are separate records |
| First browser walkthrough | Actual Flutter login rendered, but plain DOM text locator timed out | Saved FAIL record and screenshot retained; corrected driver uses Flutter semantics |
| Second browser walkthrough | Incident-badge accessible name prevented exact nav matching; dependent report/responsive steps and incorrect submit selector failed | Full failed run retained; corrected driver passed later walkthroughs |

The [evidence index](evidence-index.md) links all retained executions and dispositions. No failed run was converted to a pass or deleted.

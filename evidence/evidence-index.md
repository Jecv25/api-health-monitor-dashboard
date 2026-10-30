# Module 13 evidence index

Generated from retained execution artifacts at 2026-10-29T18:06:32.513Z (UTC). Display timezone: Asia/Manila. No expected value was substituted for an actual result.

## Latest API cases

Dataset: [summary](runs/2026-10-29T18-00-20-548Z/summary.json), [source/environment identity](runs/2026-10-29T18-00-20-548Z/environment.json), [actual JSONL logs](runs/2026-10-29T18-00-20-548Z/runtime.jsonl), [SQLite](runs/2026-10-29T18-00-20-548Z/monitor.sqlite), [failure-injection proof](runs/2026-10-29T18-00-20-548Z/failure-injection-proof.json).

| Case | Actual status | Started (UTC) | Request / expected / actual / timestamps |
| --- | --- | --- | --- |
| N01: Successful execution | PASS | 2026-10-29T18:00:20.684Z | [record](runs/2026-10-29T18-00-20-548Z/N01.json) |
| I01: Invalid input rejected server-side | PASS | 2026-10-29T18:00:20.764Z | [record](runs/2026-10-29T18-00-20-548Z/I01.json) |
| U01: Unauthorized mutation rejected | PASS | 2026-10-29T18:00:20.778Z | [record](runs/2026-10-29T18-00-20-548Z/U01.json) |
| U02: Viewer mutation and forged role rejected | PASS | 2026-10-29T18:00:20.785Z | [record](runs/2026-10-29T18-00-20-548Z/U02.json) |
| D01: Transient failure recovered by retry | PASS | 2026-10-29T18:00:20.790Z | [record](runs/2026-10-29T18-00-20-548Z/D01.json) |
| D02: Persistent failure routed to a person and deduplicated | PASS | 2026-10-29T18:00:22.289Z | [record](runs/2026-10-29T18-00-20-548Z/D02.json) |
| R01: Human repair followed by verified recovery | PASS | 2026-10-29T18:00:25.240Z | [record](runs/2026-10-29T18-00-20-548Z/R01.json) |
| D03: Non-retryable HTTP failure | PASS | 2026-10-29T18:00:25.260Z | [record](runs/2026-10-29T18-00-20-548Z/D03.json) |
| X01: Idempotent accepted request replay | PASS | 2026-10-29T18:00:25.276Z | [record](runs/2026-10-29T18-00-20-548Z/X01.json) |
| F01: Actual HTTP timeout injection | PASS | 2026-10-29T18:00:25.278Z | [record](runs/2026-10-29T18-00-20-548Z/F01.json) |
| F02: Atomic result/recovery rollback on controlled storage fault | PASS | 2026-10-29T18:00:35.802Z | [record](runs/2026-10-29T18-00-20-548Z/F02.json) |

Three preserved demos:

1. [Successful execution](runs/2026-10-29T18-00-20-548Z/01-success.md).
2. [Transient recovered by retry](runs/2026-10-29T18-00-20-548Z/02-transient-recovered.md).
3. [Persistent failure, human acknowledgement, and verified recovery](runs/2026-10-29T18-00-20-548Z/03-persistent-human-recovery.md).

## Actual browser walkthrough

[Browser summary](browser/2026-10-29T18-00-44-208Z/summary.json), [browser version](browser/2026-10-29T18-00-44-208Z/browser-version.json), [actual mutation responses](browser/2026-10-29T18-00-44-208Z/mutations.json), [backend logs](browser/2026-10-29T18-00-44-208Z/runtime.jsonl).

| Case | Actual status | Detailed record |
| --- | --- | --- |
| B01-login | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B01-login.json) |
| B02-success-demo | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B02-success-demo.json) |
| B03-transient-demo | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B03-transient-demo.json) |
| B04-persistent-human-recovery-demo | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B04-persistent-human-recovery-demo.json) |
| B05-report | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B05-report.json) |
| B06-responsive | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B06-responsive.json) |
| B07-invalid-form | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B07-invalid-form.json) |
| B08-network-error | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B08-network-error.json) |
| B09-server-error-state | PASS | [expected / actual](browser/2026-10-29T18-00-44-208Z/B09-server-error-state.json) |

Actual screenshots (compiled Flutter Web):

- [01-login-desktop.png](browser/2026-10-29T18-00-44-208Z/01-login-desktop.png) — 1280×1000, captured 2026-10-29T18:00:45.979Z.
- [02-endpoints-desktop.png](browser/2026-10-29T18-00-44-208Z/02-endpoints-desktop.png) — 1280×1000, captured 2026-10-29T18:00:46.416Z.
- [03-success-demo.png](browser/2026-10-29T18-00-44-208Z/03-success-demo.png) — 1280×1000, captured 2026-10-29T18:00:46.962Z.
- [04-transient-demo.png](browser/2026-10-29T18-00-44-208Z/04-transient-demo.png) — 1280×1000, captured 2026-10-29T18:00:49.343Z.
- [05-persistent-demo.png](browser/2026-10-29T18-00-44-208Z/05-persistent-demo.png) — 1280×1000, captured 2026-10-29T18:00:51.551Z.
- [06-acknowledged.png](browser/2026-10-29T18-00-44-208Z/06-acknowledged.png) — 1280×1000, captured 2026-10-29T18:00:51.861Z.
- [07-repair-awaiting-verification.png](browser/2026-10-29T18-00-44-208Z/07-repair-awaiting-verification.png) — 1280×1000, captured 2026-10-29T18:00:52.362Z.
- [08-verified-recovery.png](browser/2026-10-29T18-00-44-208Z/08-verified-recovery.png) — 1280×1000, captured 2026-10-29T18:00:52.771Z.
- [09-uptime-report-desktop.png](browser/2026-10-29T18-00-44-208Z/09-uptime-report-desktop.png) — 1280×1000, captured 2026-10-29T18:00:52.959Z.
- [10-endpoints-768.png](browser/2026-10-29T18-00-44-208Z/10-endpoints-768.png) — 768×1000, captured 2026-10-29T18:00:53.898Z.
- [11-incidents-768.png](browser/2026-10-29T18-00-44-208Z/11-incidents-768.png) — 768×1000, captured 2026-10-29T18:00:54.748Z.
- [12-report-768.png](browser/2026-10-29T18-00-44-208Z/12-report-768.png) — 768×1000, captured 2026-10-29T18:00:55.579Z.
- [10-endpoints-390.png](browser/2026-10-29T18-00-44-208Z/10-endpoints-390.png) — 390×1000, captured 2026-10-29T18:00:56.470Z.
- [11-incidents-390.png](browser/2026-10-29T18-00-44-208Z/11-incidents-390.png) — 390×1000, captured 2026-10-29T18:00:57.324Z.
- [12-report-390.png](browser/2026-10-29T18-00-44-208Z/12-report-390.png) — 390×1000, captured 2026-10-29T18:00:58.666Z.
- [13-invalid-form.png](browser/2026-10-29T18-00-44-208Z/13-invalid-form.png) — 1280×1000, captured 2026-10-29T18:00:59.216Z.
- [14-network-error.png](browser/2026-10-29T18-00-44-208Z/14-network-error.png) — 1280×1000, captured 2026-10-29T18:00:59.559Z.
- [15-server-error-state.png](browser/2026-10-29T18-00-44-208Z/15-server-error-state.png) — 1280×1000, captured 2026-10-29T18:01:00.075Z.

The browser demo has one failed Payments check and one passing repair-verification check: 50.00%. The API D02/R01 dataset intentionally has two failed checks and one pass: 33.33%. They are separately identified datasets. B08 and B09 explicitly inject browser transport/HTTP responses to verify feedback; actual backend timeout and transaction-failure evidence is F01/F02.

## Actual crash / restart

[C01 PASS](restart/2026-10-29T18-00-20-589Z/C01.json): an actual spawned backend was abruptly terminated after a saved 503 attempt, then restarted against the same database. See [logs](restart/2026-10-29T18-00-20-589Z/runtime.jsonl) and [source/environment](restart/2026-10-29T18-00-20-589Z/environment.json).

## Validation and preserved failures

| Run | Command | Actual exit | Output |
| --- | --- | --- | --- |
| 2026-10-29T17-41-33-306Z-reproduced-layout-failure | flutter.bat test --reporter expanded | 1 | [log](validation/2026-10-29T17-41-33-306Z-reproduced-layout-failure/flutter-tests.log) |
| 2026-10-29T17-42-48-674Z-layout-fix | flutter.bat test --reporter expanded | 0 | [log](validation/2026-10-29T17-42-48-674Z-layout-fix/flutter-tests.log) |
| 2026-10-29T17-44-14-377Z-full-verification | npm.cmd test | 0 | [log](validation/2026-10-29T17-44-14-377Z-full-verification/backend-tests.log) |
| 2026-10-29T17-44-14-377Z-full-verification | flutter.bat analyze | 0 | [log](validation/2026-10-29T17-44-14-377Z-full-verification/flutter-analyze.log) |
| 2026-10-29T17-44-14-377Z-full-verification | flutter.bat test --reporter expanded | 0 | [log](validation/2026-10-29T17-44-14-377Z-full-verification/flutter-tests.log) |
| 2026-10-29T17-44-14-377Z-full-verification | flutter.bat build web --release --no-web-resources-cdn | 0 | [log](validation/2026-10-29T17-44-14-377Z-full-verification/flutter-build.log) |
| 2026-10-29T17-57-09-358Z-final-verification | flutter.bat --version --machine | 0 | [log](validation/2026-10-29T17-57-09-358Z-final-verification/toolchain.log) |
| 2026-10-29T17-57-09-358Z-final-verification | npm.cmd test | 0 | [log](validation/2026-10-29T17-57-09-358Z-final-verification/backend-tests.log) |
| 2026-10-29T17-57-09-358Z-final-verification | flutter.bat analyze | 0 | [log](validation/2026-10-29T17-57-09-358Z-final-verification/flutter-analyze.log) |
| 2026-10-29T17-57-09-358Z-final-verification | flutter.bat test --reporter expanded | 0 | [log](validation/2026-10-29T17-57-09-358Z-final-verification/flutter-tests.log) |
| 2026-10-29T17-57-09-358Z-final-verification | flutter.bat build web --release --no-web-resources-cdn | 0 | [log](validation/2026-10-29T17-57-09-358Z-final-verification/flutter-build.log) |

Earlier browser runs are retained:

- [2026-10-29T17-45-53-406Z](browser/2026-10-29T17-45-53-406Z/summary.json): B01-login FAIL.
- [2026-10-29T17-48-15-119Z](browser/2026-10-29T17-48-15-119Z/summary.json): B01-login PASS; B02-success-demo PASS; B03-transient-demo PASS; B04-persistent-human-recovery-demo FAIL; B05-report FAIL; B06-responsive FAIL; B07-invalid-form FAIL; B08-network-error PASS; B09-server-error-state PASS.
- [2026-10-29T17-50-24-037Z](browser/2026-10-29T17-50-24-037Z/summary.json): B01-login PASS; B02-success-demo PASS; B03-transient-demo PASS; B04-persistent-human-recovery-demo PASS; B05-report PASS; B06-responsive PASS; B07-invalid-form PASS; B08-network-error PASS; B09-server-error-state PASS.
- [2026-10-29T18-00-44-208Z](browser/2026-10-29T18-00-44-208Z/summary.json): B01-login PASS; B02-success-demo PASS; B03-transient-demo PASS; B04-persistent-human-recovery-demo PASS; B05-report PASS; B06-responsive PASS; B07-invalid-form PASS; B08-network-error PASS; B09-server-error-state PASS.

Earlier API executions are retained:

- [2026-10-29T17-42-47-512Z](runs/2026-10-29T17-42-47-512Z/summary.json).
- [2026-10-29T17-48-47-837Z](runs/2026-10-29T17-48-47-837Z/summary.json).
- [2026-10-29T18-00-20-548Z](runs/2026-10-29T18-00-20-548Z/summary.json).

The initial dropdown overflow, selector failures, and setup problems are not erased. See [setup issues](setup-issues.md) and [lab log](lab-log.md). The original failure logs and later passing reruns are separate artifacts.

Latest complete validation: [results](validation/2026-10-29T17-57-09-358Z-final-verification/results.json), [environment/source identity](validation/2026-10-29T17-57-09-358Z-final-verification/environment.json). The backend-test datasets/logs are copied under that validation directory after the tests close their databases.

[Observed metrics](metrics.json) · [Lab log](lab-log.md) · [Limitations](../limitations.md) · [Maintainability](../maintainability-note.md)

[Configuration/log audit](configuration-audit.json) · [Module 13 interpretation](interpretation.md) · [Local source-control record](source-control.json) · [Viva practice notes](../docs/viva-guide.md)

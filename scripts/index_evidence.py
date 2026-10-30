"""Create the SA7 evidence map and a browser-independent screenshot fallback."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / "evidence"


def latest(prefix, exclude=""):
    candidates = []
    for directory in sorted(EVIDENCE.iterdir()):
        if not directory.is_dir() or not directory.name.startswith(prefix) or (exclude and directory.name.startswith(exclude)):
            continue
        path = directory / "results.json"
        if path.exists():
            scenarios = json.loads(path.read_text(encoding="utf-8"))["scenarios"]
            if scenarios and all(c.get("passed") for c in scenarios):
                candidates.append((directory, scenarios))
    if not candidates:
        raise SystemExit(f"No completed passing evidence for {prefix}; finish verification before indexing.")
    return candidates[-1]


def main():
    browser, browser_cases = latest("browser-", "browser-recovery-")
    recovery, recovery_cases = latest("browser-recovery-")
    http, http_cases = latest("http-demo-")
    worker, worker_cases = latest("worker-")
    text = f"""# Week 13 / SA7 evidence map

Project: Pulsewatch API Health Monitoring Dashboard. Actual stack: Flutter Web, FastAPI, **MySQL 8.4.8**. Controlled fictional services only. Runtime versions are in [environment.json](environment.json) and [flutter-environment.json](flutter-environment.json). Exact submitted source is fingerprinted in [source-manifest.json](source-manifest.json).

## Observed verification

| Check | Observed result | Artifact |
| --- | --- | --- |
| MySQL-backed backend regression | 30 passed; one documented dependency deprecation warning | [original failures](backend-tests-01.txt), [passing rerun](backend-tests-02.txt), [JUnit](backend-tests-02.xml) |
| OpenAPI/auth dependency adjustment | 2 focused regression checks passed | [contract regression](backend-contract-regression.txt) |
| Flutter state/client regression | 10 passed, including open-dialog updates and in-dialog feedback | [final state tests](flutter-tests-05.txt); runs 01–04 retain earlier observations |
| Flutter Web compilation | Successful local-resource build | [final build](flutter-build-03.txt) |
| Real HTTP/API/MySQL demonstration | {len(http_cases)} expected/actual scenarios passed | [{http.name}]({http.name}/results.json), [structured logs]({http.name}/structured-logs.jsonl) |
| Independent worker and restart | {len(worker_cases)} actual process scenarios passed | [{worker.name}]({worker.name}/results.json) |
| Edge / actual Flutter normal and adverse states | {len(browser_cases)} recorded checks passed | [{browser.name}]({browser.name}/results.json) |
| Edge / actual incident and recovery workflow | {len(recovery_cases)} recorded checks passed | [{recovery.name}]({recovery.name}/results.json) |
| Local stop/start preserves MySQL records | Expected and actual endpoint counts match | [local lifecycle](local-lifecycle.json) |

The browser basic capture records whether its controlled service was newly registered or reused. Recovery capture explicitly records API-based baseline preparation when a previous demonstration incident existed. API-unavailable browser evidence uses controlled request interception; it does not claim the API process crashed.

## Requirement → implementation → evidence

| Requirement | Implementation and verification |
| --- | --- |
| SA7-01 registration | `main.py` registration + MySQL URL constraint; healthy/duplicate API tests; basic browser normal path |
| SA7-02 invalid/boundary inputs | `schemas.py`; invalid URL/origin/interval/timeout tests; basic browser invalid form |
| SA7-03 unauthorized action | API-key dependency; unauthorized API tests; real browser invalid-key state |
| SA7-04 normal check | Shared `HealthRunner`; persisted healthy test and actual HTTP/browser check |
| SA7-05 transient recovered | Two attempts 503→200; actual HTTP run and matching structured logs |
| SA7-06 persistent → human action | Three-attempt exhaustion; incident/notification deduplication tests; actual outage screenshot and HTTP records |
| SA7-07 acknowledgement | Protected support acknowledgement API and Flutter dialog; actual browser acknowledgement |
| SA7-08 recovery verification | Two successful cycles, failure resets streak; backend regression, open-dialog widget regression, actual recovery screenshots |
| SA7-09 duplicate/concurrent work | MySQL advisory lock + endpoint/idempotency unique key; overlap test and actual replayed HTTP request |
| SA7-10 scheduling/restart | Separate APScheduler worker, due-time checks and heartbeat; actual worker/restart results |
| SA7-11 uptime summary | SQL completed-cycle aggregates; unknown-without-samples test; actual reports |
| SA7-12 responsive workflow/states | Flutter state tests; actual 1440px and 390px captures, unavailable/reconnect capture |

## Review and fallback

Open [gallery.html](gallery.html) for the final verified screenshots. Read [workflow and decisions](../docs/week13-design.md), [API contract](../docs/api-contract.md), [architecture](../docs/architecture.md), [recovery runbook](../docs/recovery-runbook.md), [issue record](../docs/issue-record.md), and [maintainability/risks](../docs/maintainability.md).

Earlier browser directories preserve MIME/locator interruptions and the real stale-dialog observation. A partial/interrupted directory is **not** used as proof of a completed walkthrough. Failure artifacts are normalized to UTF-8 and credential diagnostics are redacted; they are not represented as untouched originals. The issue record identifies fixes and regression evidence.

Screenshots support source, structured logs and machine-readable expected/actual observations. They do not establish production readiness, Week 14–18 completion, stakeholder UAT, student viva or individual contributions. Complete the personal contribution record after reproducing the work.
"""
    (EVIDENCE / "README.md").write_text(text, encoding="utf-8")
    cards = []
    for directory in (browser, recovery):
        for path in sorted(directory.glob("*.png")):
            relative = path.relative_to(EVIDENCE).as_posix()
            title = path.stem.replace("-", " ")
            cards.append(f'<article><a href="{html.escape(relative)}"><img loading="lazy" src="{html.escape(relative)}" alt="{html.escape(title)}"></a><p>{html.escape(directory.name)} / {html.escape(title)}</p></article>')
    page = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Pulsewatch · SA7 Evidence</title><style>body{font:15px system-ui;background:#f4f7f5;color:#182c2b;margin:32px}h1{font-size:30px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px}article{background:white;border:1px solid #dce6e0;border-radius:12px;padding:12px}img{width:100%;max-height:550px;object-fit:contain;object-position:top}p{font-size:12px;line-height:1.7}a{color:#087f6d}</style><h1>Pulsewatch / Week 13 evidence</h1><p>Actual Flutter Web screenshots from controlled runs. Open an image for its full size. The evidence map and JSON records explain the scenario and limitations.</p><p><a href="README.md">Evidence map</a> · <a href="../README.md">Setup and demonstration guide</a></p><main>' + ''.join(cards) + '</main></html>'
    (EVIDENCE / "gallery.html").write_text(page, encoding="utf-8")
    print(f"Indexed verified evidence and {len(cards)} real screenshots.")


if __name__ == "__main__":
    main()

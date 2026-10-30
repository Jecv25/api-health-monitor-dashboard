"""Capture the actual Flutter incident/recovery flow after demo_week13.py."""
import json
import re
import sys
import time
from uuid import uuid4
from datetime import datetime, timezone
from pathlib import Path

import httpx
from playwright.sync_api import sync_playwright
from app.config import get_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    settings = get_settings()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = ROOT / "evidence" / f"browser-recovery-{stamp}"
    directory.mkdir(parents=True)
    records = []
    private = [settings.operator_key.get_secret_value(), settings.db_password.get_secret_value()]
    headers = {"X-Operator-Key": private[0]}
    client = httpx.Client(base_url="http://127.0.0.1:8000", trust_env=False, timeout=10)

    def safe(message):
        for secret in private:
            message = message.replace(secret, "[REDACTED]") if secret else message
        return message

    def endpoint():
        return next(e for e in client.get("/api/endpoints").json() if e["url"].endswith("/health/persistent"))

    def wait_endpoint(status):
        for _ in range(60):
            value = endpoint()
            if value["status"] == status:
                return value
            time.sleep(.2)
        raise RuntimeError(f"Expected controlled endpoint state {status} was not observed.")

    def open_ui(page):
        page.goto("http://localhost:8080", wait_until="networkidle", timeout=60000)
        placeholder = page.locator("flt-semantics-placeholder")
        placeholder.wait_for(state="attached", timeout=30000)
        placeholder.evaluate("element => element.click()")
        page.get_by_role("button", name="Connect operator", exact=True).wait_for()

    try:
        current = endpoint()
        active = [i for i in client.get('/api/incidents').json()
                  if i['endpoint_id'] == current['id'] and i['status'] != 'recovered']
        if active:
            # Reproducible preparation after an interrupted previous capture.
            client.post('/api/demo/recover', headers=headers).raise_for_status()
            for _ in range(2):
                client.post(f"/api/endpoints/{current['id']}/checks",
                            headers={**headers, 'Idempotency-Key': str(uuid4())}).raise_for_status()
            records.append({'scenario': 'controlled baseline preparation',
                            'method': 'API repair plus two checks close a prior interrupted demonstration incident', 'passed': True})
        client.post("/api/demo/reset", headers=headers).raise_for_status()
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="msedge", headless=True, args=["--enable-unsafe-swiftshader"])
            page = browser.new_page(viewport={"width": 1440, "height": 1100})
            runtime_errors = []
            page.on("pageerror", lambda e: runtime_errors.append(safe(str(e))))
            open_ui(page)
            page.get_by_role("button", name="Connect operator", exact=True).click()
            page.get_by_role("textbox", name="Operator key").fill(private[0])
            page.get_by_role("button", name="Connect", exact=True).click()
            page.get_by_role("button", name="Check Billing API now").click()
            failed = wait_endpoint("down")
            page.get_by_role("button", name="Refresh results", exact=True).click()
            page.wait_for_timeout(750)
            page.screenshot(path=str(directory / "01-outage-overview.png"), full_page=True)
            (directory / "outage-accessibility-tree.txt").write_text(page.locator("body").aria_snapshot(), encoding="utf-8")
            records.append({"scenario": "persistent failure checked via Flutter", "expected": "down; three recorded attempts", "actual": failed,
                            "passed": failed["last_run"]["attempt_count"] == 3})
            page.get_by_role("button", name=re.compile(r"^Incidents")).click()
            page.get_by_role("button", name="Acknowledge", exact=True).click()
            page.get_by_role("button", name="Confirm acknowledgement", exact=True).click()
            page.get_by_text(re.compile(r"Acknowledged by support-demo")).first.wait_for()
            page.screenshot(path=str(directory / "02-human-acknowledgement.png"), full_page=True)
            records.append({"scenario": "support acknowledgement through Flutter", "expected": "acknowledged, not recovered", "actual": client.get("/api/incidents").json(), "passed": True})
            page.get_by_role("button", name="Inspect service", exact=True).click()
            page.get_by_role("button", name="Repair demo service", exact=True).click()
            page.get_by_text("Demo repaired. Run two successful checks to verify recovery.", exact=True).first.wait_for()
            page.get_by_role("button", name="Check now", exact=True).click()
            intermediate = wait_endpoint("recovering")
            for _ in range(50):
                tree = page.locator('body').aria_snapshot()
                if 'Recovery verification: 1 / 2 successful cycles.' in tree:
                    break
                page.wait_for_timeout(200)
            (directory / 'recovery-accessibility-tree.txt').write_text(tree, encoding='utf-8')
            page.screenshot(path=str(directory / "03-recovery-verification.png"))
            if 'Recovery verification: 1 / 2 successful cycles.' not in tree:
                raise RuntimeError('The service dialog did not expose the expected recovery verification state. Inspect screenshot 03 and its accessibility tree.')
            records.append({"scenario": "first recovery cycle via Flutter", "expected": "recovering, streak 1", "actual": intermediate, "passed": intermediate["recovery_streak"] == 1})
            page.get_by_role("button", name="Check now", exact=True).click()
            recovered = wait_endpoint("up")
            page.wait_for_timeout(500)
            page.screenshot(path=str(directory / "04-recovered-history.png"))
            page.get_by_role("button", name="Close service details", exact=True).click()
            page.get_by_text(re.compile(r"Verified recovery")).first.wait_for()
            page.screenshot(path=str(directory / "05-recovered-incidents.png"), full_page=True)
            records.append({"scenario": "second recovery cycle via Flutter", "expected": "up with incident recovered", "actual": recovered, "passed": recovered["status"] == "up"})
            page.get_by_role("button", name=re.compile(r"^Notifications")).click()
            page.screenshot(path=str(directory / "06-notifications.png"))
            page.get_by_role("button", name="Close notifications", exact=True).click()
            page.get_by_role("button", name="Reports", exact=True).click()
            page.get_by_text("Availability reports", exact=True).wait_for()
            page.screenshot(path=str(directory / "07-desktop-reports.png"), full_page=True)
            page.set_viewport_size({"width": 390, "height": 844})
            page.screenshot(path=str(directory / "08-narrow-reports.png"), full_page=True)
            records.append({"scenario": "reports and durable notifications", "actual": client.get("/api/notifications").json(), "passed": True})
            offline = browser.new_page(viewport={"width": 1280, "height": 900})
            offline.route("http://127.0.0.1:8000/**", lambda route: route.abort("connectionrefused"))
            open_ui(offline)
            offline.get_by_text("Monitoring API unavailable", exact=True).wait_for()
            offline.screenshot(path=str(directory / "09-api-unavailable.png"))
            offline.unroute("http://127.0.0.1:8000/**")
            offline.get_by_role("button", name="Retry connection", exact=True).click()
            offline.get_by_text("Service overview", exact=True).wait_for()
            records.append({"scenario": "API unavailable and reconnect", "method": "controlled browser network interception; API process left running", "passed": True})
            records.append({"scenario": "runtime errors", "expected": [], "actual": runtime_errors, "passed": not runtime_errors})
            browser.close()
        code = 0 if all(r["passed"] for r in records) else 1
    except Exception as exc:
        records.append({"scenario": "browser recovery interrupted", "passed": False, "error": safe(str(exc))})
        print(safe(str(exc)))
        code = 1
    finally:
        client.close()
        (directory / "results.json").write_text(json.dumps({"environment": "actual Flutter Web / Edge / FastAPI / MySQL / controlled dependency", "scenarios": records}, indent=2), encoding="utf-8")
        print(f"Recovery browser evidence: evidence/{directory.name}")
    return code


if __name__ == "__main__":
    sys.exit(main())

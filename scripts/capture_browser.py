"""Browser smoke pass against the actual Flutter build and API, using installed Edge."""
import json
import sys
import httpx
from datetime import datetime, timezone
from pathlib import Path

from playwright.sync_api import sync_playwright
from app.config import get_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = ROOT / "evidence" / f"browser-{stamp}"
    directory.mkdir(parents=True)
    records = []
    settings = get_settings()
    existing = any(e["url"].endswith("/health/healthy-ui") for e in
                   httpx.get("http://127.0.0.1:8000/api/endpoints", trust_env=False).json())
    private_values = [settings.operator_key.get_secret_value(), settings.db_password.get_secret_value()]

    def safe(value):
        for secret in private_values:
            value = value.replace(secret, "[REDACTED]") if secret else value
        return value

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="msedge", headless=True, args=["--enable-unsafe-swiftshader"])
            context = browser.new_context(viewport={"width": 1440, "height": 1100}, device_scale_factor=1)
            page = context.new_page()
            errors = []
            page.on("pageerror", lambda exc: errors.append(safe(str(exc))))
            page.goto("http://localhost:8080", wait_until="networkidle", timeout=60000)
            placeholder = page.locator("flt-semantics-placeholder")
            if placeholder.count():
                placeholder.evaluate("element => element.click()")
            page.get_by_role("button", name="Connect operator", exact=True).wait_for(timeout=30000)
            page.screenshot(path=str(directory / "01-desktop.png"), full_page=True)
            (directory / "accessibility-tree.txt").write_text(page.locator("body").aria_snapshot(), encoding="utf-8")
            records.append({"scenario": "desktop initial view", "viewport": "1440x1100", "screenshot": "01-desktop.png", "passed": True})
            # Remaining UI actions run with normal accessibility locators.
            page.get_by_role("button", name="Connect operator", exact=True).click()
            page.get_by_role("textbox", name="Operator key").fill("invalid-key")
            page.get_by_role("button", name="Connect", exact=True).click()
            page.get_by_text("Connect with the local operator key to perform this action.").wait_for()
            page.screenshot(path=str(directory / "02-unauthorized.png"))
            records.append({"scenario": "invalid operator key", "expected": "safe unauthorized message", "passed": True})
            page.get_by_role("textbox", name="Operator key").fill(settings.operator_key.get_secret_value())
            page.get_by_role("button", name="Connect", exact=True).click()
            page.get_by_role("button", name="Operator connected", exact=True).wait_for()
            page.get_by_role("button", name="Add service", exact=True).click()
            page.get_by_role("textbox", name="Service name").fill("UI smoke API")
            page.get_by_role("textbox", name="Health endpoint URL").fill("http://unapproved.invalid/health")
            page.get_by_role("button", name="Register service", exact=True).click()
            page.get_by_text("Choose an approved service origin.", exact=True).first.wait_for()
            page.screenshot(path=str(directory / "03-invalid-url.png"))
            records.append({"scenario": "unapproved URL validation", "expected": "form remains open; no registration", "passed": True})
            page.get_by_role("textbox", name="Health endpoint URL").fill("http://127.0.0.1:9001/health/healthy-ui")
            if existing:
                page.get_by_role("button", name="Cancel", exact=True).click()
            else:
                page.get_by_role("button", name="Register service", exact=True).click()
            page.get_by_role("button", name="Check UI smoke API now").wait_for()
            page.get_by_role("button", name="Check UI smoke API now").click()
            page.get_by_text("UI smoke API: completed with 1 attempt(s).", exact=True).first.wait_for(timeout=15000)
            page.screenshot(path=str(directory / "04-normal-path.png"), full_page=True)
            records.append({"scenario": "registration and manual check via Flutter" if not existing else "existing controlled service checked via Flutter",
                            "created_via_ui": not existing, "expected": "persisted service and successful result", "passed": True})
            page.set_viewport_size({"width": 390, "height": 844})
            page.get_by_role("button", name="Open navigation").wait_for()
            page.screenshot(path=str(directory / "05-narrow.png"), full_page=True)
            page.get_by_role("button", name="Open navigation").click()
            page.get_by_role("button", name="Reports", exact=True).click()
            page.get_by_text("Availability reports", exact=True).wait_for()
            page.screenshot(path=str(directory / "06-narrow-reports.png"), full_page=True)
            records.append({"scenario": "narrow navigation and reports", "viewport": "390x844", "passed": True})
            records.append({"scenario": "browser runtime errors", "expected": [], "actual": errors, "passed": not errors})
            if errors:
                raise RuntimeError("Browser runtime errors were captured.")
            context.close()
            browser.close()
    except Exception as exc:
        records.append({"scenario": "browser verification interrupted", "passed": False, "error": safe(str(exc))})
        print(safe(str(exc)))
        return_code = 1
    else:
        return_code = 0
    finally:
        (directory / "results.json").write_text(json.dumps({"browser": "installed Microsoft Edge / Playwright", "scenarios": records}, indent=2), encoding="utf-8")
        print(f"Browser evidence: evidence/{directory.name}")
    return return_code


if __name__ == "__main__":
    sys.exit(main())

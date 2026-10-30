"""Run actual HTTP scenarios and preserve sanitized expected/actual evidence."""
import json
import platform
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import httpx
from app.config import get_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    settings = get_settings()
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = ROOT / "evidence" / f"http-demo-{timestamp}"
    directory.mkdir(parents=True)
    records, run_ids = [], set()
    headers = {"X-Operator-Key": settings.operator_key.get_secret_value()}
    client = httpx.Client(base_url="http://127.0.0.1:8000", timeout=40, trust_env=False)

    def record(name, expected, actual, passed):
        records.append({"scenario": name, "timestamp": datetime.now(timezone.utc).isoformat(),
                        "expected": expected, "actual": actual, "passed": bool(passed)})
        (directory / "results.json").write_text(json.dumps({"python": platform.python_version(),
            "environment": "loopback HTTP + real MySQL + controlled HTTP service", "scenarios": records}, indent=2), encoding="utf-8")
        if not passed:
            raise RuntimeError(f"Scenario failed: {name}; inspect {directory.name}/results.json")

    def check(endpoint, key=None):
        response = client.post(f"/api/endpoints/{endpoint['id']}/checks",
                               headers={**headers, "Idempotency-Key": key or str(uuid4())})
        response.raise_for_status()
        value = response.json()
        run_ids.add(value["id"])
        return value

    try:
        client.get("/healthz").raise_for_status()
        seeded = client.post("/api/demo/seed", headers=headers)
        seeded.raise_for_status()
        services = {e["url"].rsplit("/", 1)[-1]: e for e in seeded.json()}
        bad_body = {"name": "Invalid API", "url": "http://unapproved.invalid/health"}
        unauthorized = client.post("/api/endpoints", json=bad_body)
        record("unauthorized mutation", "401; no registration", {"status": unauthorized.status_code, "body": unauthorized.json()}, unauthorized.status_code == 401)
        invalid = client.post("/api/endpoints", headers=headers, json=bad_body)
        record("unapproved endpoint", "422; origin rejected", {"status": invalid.status_code, "body": invalid.json()}, invalid.status_code == 422)
        healthy = check(services["healthy"])
        record("normal health check", "200; one successful attempt", healthy, healthy["success"] and healthy["attempt_count"] == 1)
        transient = check(services["transient"])
        record("transient failure recovered", "503 then 200; two attempts", transient,
               transient["status"] == "transient_recovered" and [a["http_status"] for a in transient["attempts"]] == [503, 200])
        client.post("/api/demo/reset", headers=headers).raise_for_status()
        persistent = check(services["persistent"])
        record("persistent failure bounded", "three attempts then human action", persistent,
               persistent["status"] == "failed" and persistent["attempt_count"] == 3)
        before = client.get("/api/incidents").json()
        incident = next(i for i in before if i["endpoint_id"] == services["persistent"]["id"] and i["status"] != "recovered")
        key = str(uuid4())
        once, duplicate = check(services["persistent"], key), check(services["persistent"], key)
        record("idempotent resubmission", "same run ID; no second execution", {"original": once["id"], "replayed": duplicate["id"]}, once["id"] == duplicate["id"])
        after = client.get("/api/incidents").json()
        record("outage incident deduplicated", "one active incident for service", after,
               len([i for i in after if i["endpoint_id"] == services["persistent"]["id"] and i["status"] != "recovered"]) == 1)
        acknowledged = client.post(f"/api/incidents/{incident['id']}/acknowledge", headers=headers,
                                   json={"operator_alias": "support-demo", "note": "Controlled dependency repair."})
        record("human acknowledgement", "acknowledged; incident remains open for recovery", acknowledged.json(),
               acknowledged.status_code == 200 and acknowledged.json()["status"] == "acknowledged")
        client.post("/api/demo/recover", headers=headers).raise_for_status()
        check(services["persistent"])
        intermediate = next(e for e in client.get("/api/endpoints").json() if e["id"] == services["persistent"]["id"])
        record("first recovery check", "recovering; one successful cycle", intermediate,
               intermediate["status"] == "recovering" and intermediate["recovery_streak"] == 1)
        check(services["persistent"])
        recovered = next(i for i in client.get("/api/incidents").json() if i["id"] == incident["id"])
        notifications = client.get("/api/notifications").json()
        record("verified recovery notification", "recovered; one durable recovery notification",
               {"incident": recovered, "notifications": notifications}, recovered["status"] == "recovered" and
               len([n for n in notifications if n["incident_id"] == incident["id"] and n["kind"] == "recovery"]) == 1)
        report = client.get("/api/reports").json()
        record("uptime summary", "computed from actual completed check cycles", report,
               report["summary"]["completed_checks"] >= 6 and report["summary"]["uptime_percent"] is not None)
    finally:
        client.close()
        log_path = ROOT / "backend" / "logs" / "automation.jsonl"
        if log_path.exists():
            rows = [line for line in log_path.read_text().splitlines() if json.loads(line).get("run_id") in run_ids]
            (directory / "structured-logs.jsonl").write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"{len(records)} real HTTP scenarios passed. Evidence: evidence/{directory.name}")


if __name__ == "__main__":
    main()

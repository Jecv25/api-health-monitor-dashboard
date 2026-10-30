"""Observe real scheduled execution and restart using MySQL and the controlled HTTP service."""
import json
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
from sqlalchemy import select
from app.main import app
from app.database import utcnow
from app.models import CheckRun, Endpoint

ROOT = Path(__file__).resolve().parent.parent


def main():
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = ROOT / "evidence" / f"worker-{stamp}"
    directory.mkdir(parents=True)
    records = []
    with app.state.sessions() as db:
        endpoint = db.scalar(select(Endpoint).where(Endpoint.url.endswith("/health/healthy")))
        if not endpoint:
            raise SystemExit("Run the controlled HTTP demo first to register the test services.")
        endpoint_id = endpoint.id

    def history_ids():
        with app.state.sessions() as db:
            return {r.id for r in db.scalars(select(CheckRun).where(CheckRun.endpoint_id == endpoint_id, CheckRun.source == "scheduled"))}

    def make_due():
        with app.state.sessions() as db:
            # Controlled scheduling injection: postpone other fixtures and make one service due.
            for item in db.scalars(select(Endpoint)):
                item.next_check_at = utcnow() + timedelta(minutes=5)
            db.get(Endpoint, endpoint_id).next_check_at = utcnow() - timedelta(seconds=1)
            db.commit()

    try:
        for name in ("scheduled_without_browser", "restart_resumes_due_work"):
            before = history_ids()
            make_due()
            started = time.perf_counter()
            with (ROOT / ".runtime" / f"{name}.log").open("w") as log:
                process = subprocess.Popen([sys.executable, "-m", "app.worker"], cwd=ROOT / "backend",
                                           stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
                try:
                    for _ in range(30):
                        new_ids = history_ids() - before
                        if new_ids:
                            with app.state.sessions() as db:
                                run = db.get(CheckRun, next(iter(new_ids)))
                                if run.finished_at:
                                    break
                        time.sleep(.5)
                    else:
                        raise RuntimeError("No completed scheduled check was observed within 15 seconds.")
                    time.sleep(2.5)
                    final_ids = history_ids() - before
                    health = httpx.get("http://127.0.0.1:8000/healthz", trust_env=False).json()
                    record = {"scenario": name, "timestamp": datetime.now(timezone.utc).isoformat(),
                              "expected": "one completed scheduled run, fresh heartbeat, no replay burst",
                              "run_ids": sorted(final_ids), "worker_signal": health["worker"],
                              "elapsed_seconds": round(time.perf_counter()-started, 3),
                              "passed": len(final_ids) == 1 and health["worker"] == "online"}
                    records.append(record)
                    if not record["passed"]:
                        raise RuntimeError("Scheduled execution did not match the expected result.")
                finally:
                    process.terminate()
                    process.wait(timeout=10)
    finally:
        (directory / "results.json").write_text(json.dumps({"method": "real worker subprocess; controlled due-time injection; no browser dependency", "scenarios": records}, indent=2), encoding="utf-8")
    print(f"{len(records)} actual worker/restart scenarios passed. Evidence: evidence/{directory.name}")


if __name__ == "__main__":
    main()

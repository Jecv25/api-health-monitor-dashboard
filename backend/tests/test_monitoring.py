import asyncio
import json
from datetime import timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import func, select, text

from app.database import utcnow
from app.models import CheckAttempt, CheckRun, Endpoint, Incident, Notification
from app.schemas import DomainError


def test_healthy_result_persists_in_mysql(context, register, check):
    endpoint = register()
    result = check(endpoint).json()
    assert result["status"] == "success" and result["attempt_count"] == 1
    assert result["success"] and result["http_status"] == 200
    assert result["finished_at"].endswith("Z")
    with context["app"].state.sessions() as db:
        assert db.get(CheckRun, result["id"]).success
        assert db.scalar(select(func.count()).select_from(CheckAttempt)) == 1


def test_transient_recovers_on_second_attempt(context, register, check):
    result = check(register("transient")).json()
    assert result["status"] == "transient_recovered"
    assert [a["http_status"] for a in result["attempts"]] == [503, 200]
    assert context["client"].get("/api/incidents").json() == []


def test_persistent_failure_is_bounded_and_routes_once(context, register, check):
    endpoint = register("persistent")
    for _ in range(2):
        result = check(endpoint).json()
        assert result["status"] == "failed" and result["attempt_count"] == 3
    incidents = context["client"].get("/api/incidents").json()
    assert len(incidents) == 1 and incidents[0]["owner_group"] == "support"
    notes = context["client"].get("/api/notifications").json()
    assert len(notes) == 1 and notes[0]["kind"] == "human_action"


def test_acknowledgement_then_verified_recovery_with_streak_reset(context, register, check):
    endpoint = register("persistent")
    check(endpoint)
    client = context["client"]
    incident = client.get("/api/incidents").json()[0]
    ack = client.post(f"/api/incidents/{incident['id']}/acknowledge", headers=context["headers"],
                      json={"operator_alias": "support-demo", "note": "Controlled repair in progress."})
    assert ack.status_code == 200 and ack.json()["status"] == "acknowledged"
    assert client.get("/api/endpoints").json()[0]["status"] == "down"
    context["state"]["persistent"] = 200
    check(endpoint)
    assert client.get("/api/endpoints").json()[0]["status"] == "recovering"
    context["state"]["persistent"] = 503
    check(endpoint)
    assert client.get("/api/endpoints").json()[0]["recovery_streak"] == 0
    context["state"]["persistent"] = 200
    check(endpoint)
    assert client.get("/api/incidents").json()[0]["status"] == "acknowledged"
    check(endpoint)
    assert client.get("/api/incidents").json()[0]["status"] == "recovered"
    check(endpoint)
    assert len([n for n in client.get("/api/notifications").json() if n["kind"] == "recovery"]) == 1
    assert client.post(f"/api/incidents/{incident['id']}/acknowledge", headers=context["headers"],
                       json={"operator_alias": "support-demo"}).status_code == 409


@pytest.mark.parametrize("overrides", [
    {"url": "invalid"}, {"url": "http://unapproved.invalid/health"},
    {"url": "http://user:password@127.0.0.1:9001/health/healthy"},
    {"url": "http://127.0.0.1:9001/health/healthy?token=fictional"},
    {"url": "http://127.0.0.1:9001/health/healthy#fragment"},
    {"url": "ftp://127.0.0.1:9001/health/healthy"},
    {"interval_seconds": 14}, {"interval_seconds": 3601},
    {"timeout_seconds": 0}, {"timeout_seconds": 11}, {"interval_seconds": True}, {"name": "x"},
])
def test_invalid_registration_changes_nothing(context, overrides):
    response = context["client"].post("/api/endpoints", headers=context["headers"],
        json={"name": "Controlled API", "url": "http://127.0.0.1:9001/health/healthy", **overrides})
    assert response.status_code == 422
    assert context["client"].get("/api/endpoints").json() == []


@pytest.mark.parametrize("interval,timeout", [(15, 1), (3600, 10)])
def test_registration_boundary_values(register, interval, timeout):
    assert register(interval_seconds=interval, timeout_seconds=timeout)["interval_seconds"] == interval


def test_unauthorized_and_duplicate_registration(context, register):
    body = {"name": "Unauthorized API", "url": "http://127.0.0.1:9001/health/healthy"}
    assert context["client"].post("/api/endpoints", json=body).status_code == 401
    assert context["client"].post("/api/endpoints", json=body, headers={"X-Operator-Key": "invalid"}).status_code == 401
    assert context["client"].get("/api/endpoints").json() == []
    register()
    assert context["client"].post("/api/endpoints", json=body, headers=context["headers"]).status_code == 409


@pytest.mark.parametrize("path,code,attempts", [("invalid", "http_404", 1), ("redirect", "http_302", 1),
                                                    ("timeout", "timeout", 3), ("network", "network_error", 3)])
def test_failure_taxonomy(context, register, check, path, code, attempts):
    result = check(register(path)).json()
    assert result["error_code"] == code and result["attempt_count"] == attempts
    assert context["state"]["calls"] == attempts


def test_idempotency_and_paused_checks(context, register, check):
    endpoint = register()
    first, repeated = check(endpoint, "same-submission").json(), check(endpoint, "same-submission").json()
    assert first["id"] == repeated["id"] and context["state"]["calls"] == 1
    context["client"].patch(f"/api/endpoints/{endpoint['id']}", json={"enabled": False}, headers=context["headers"])
    assert check(endpoint).status_code == 409


def test_mysql_lock_prevents_overlapping_execution(context, register, check):
    endpoint = register()
    app = context["app"]
    with app.state.engine.connect() as connection:
        name = f"pw:{app.state.settings.db_name}:{endpoint['id']}"
        assert connection.execute(text("SELECT GET_LOCK(:n,0)"), {"n": name}).scalar() == 1
        connection.commit()
        assert check(endpoint).status_code == 409
        assert context["state"]["calls"] == 0
        connection.execute(text("SELECT RELEASE_LOCK(:n)"), {"n": name})
        connection.commit()


def test_interrupted_run_is_reconciled(context, register, check):
    endpoint = register()
    run_id = str(uuid4())
    with context["app"].state.sessions() as db:
        db.add(CheckRun(id=run_id, endpoint_id=endpoint["id"], correlation_id=str(uuid4()),
                        source="scheduled", idempotency_key="interrupted-submission"))
        db.commit()
    assert check(endpoint).json()["success"]
    with context["app"].state.sessions() as db:
        assert db.get(CheckRun, run_id).status == "interrupted"


def test_worker_checks_due_without_browser_and_does_not_replay(context, register):
    endpoint = register()
    runner = context["app"].state.runner
    asyncio.run(runner.check_due())
    asyncio.run(runner.check_due())
    assert context["state"]["calls"] == 1
    assert context["client"].get("/healthz").json()["worker"] == "online"
    history = context["client"].get(f"/api/endpoints/{endpoint['id']}/checks").json()
    assert history[0]["source"] == "scheduled"


def test_schedule_is_rechecked_after_lock(context, register):
    endpoint = register()
    with context["app"].state.sessions() as db:
        db.get(Endpoint, endpoint["id"]).next_check_at = utcnow() + timedelta(minutes=1)
        db.commit()
    with pytest.raises(DomainError) as caught:
        asyncio.run(context["app"].state.runner.run(endpoint["id"], str(uuid4()), str(uuid4()), "scheduled"))
    assert caught.value.code == "not_due" and context["state"]["calls"] == 0


def test_uptime_is_unknown_without_samples_then_computed(context, register, check):
    endpoint = register("persistent")
    client = context["client"]
    assert client.get("/api/reports").json()["summary"]["uptime_percent"] is None
    check(endpoint)
    context["state"]["persistent"] = 200
    check(endpoint)
    summary = client.get("/api/reports").json()["summary"]
    assert summary["uptime_percent"] == 50 and summary["retry_attempts"] == 2


def test_structured_logs_exclude_sensitive_material(context, register, check):
    run = check(register("transient")).json()
    settings = context["app"].state.settings
    content = (Path(settings.log_dir) / "automation.jsonl").read_text()
    records = [json.loads(line) for line in content.splitlines()]
    matching = [r for r in records if r.get("run_id") == run["id"]]
    assert {r["event"] for r in matching} >= {"check.started", "attempt.finished", "retry.scheduled", "check.finished"}
    assert settings.operator_key.get_secret_value() not in content
    assert settings.db_password.get_secret_value() not in content
    assert "Do not store this controlled response body" not in content

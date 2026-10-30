from pathlib import Path

import httpx
import pytest
from pydantic import SecretStr
from secrets import token_urlsafe
from fastapi.testclient import TestClient

from app.config import get_settings
from app.database import Base, make_database
from app.main import create_app


class ProtectedHeaders(dict):
    def __repr__(self):
        return "<operator headers redacted>"


@pytest.fixture(scope="session")
def test_settings():
    settings = get_settings().model_copy(update={"db_name": "pulsewatch_test", "retry_base_seconds": 0,
        "operator_key": SecretStr(token_urlsafe(32)),
        "log_dir": str(Path(__file__).resolve().parents[2] / ".runtime" / "test-logs")})
    assert settings.db_name == "pulsewatch_test", "Tests may only modify the isolated test database."
    engine, _ = make_database(settings)
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    engine.dispose()
    return settings


@pytest.fixture
def context(test_settings):
    settings = test_settings
    engine, _ = make_database(settings)
    with engine.begin() as connection:
        for table in reversed(Base.metadata.sorted_tables):
            connection.execute(table.delete())
    engine.dispose()
    state = {"persistent": 503, "calls": 0}

    async def service(request):
        state["calls"] += 1
        path = request.url.path
        if path.endswith("timeout"):
            raise httpx.ReadTimeout("controlled timeout")
        if path.endswith("network"):
            raise httpx.ConnectError("controlled network failure")
        code = 200
        if path.endswith("transient"):
            code = 503 if request.headers.get("X-Check-Attempt") == "1" else 200
        elif path.endswith("persistent"):
            code = state["persistent"]
        elif path.endswith("invalid"):
            code = 404
        elif path.endswith("redirect"):
            return httpx.Response(302, headers={"Location": "http://unapproved.invalid/private"})
        return httpx.Response(code, text="Do not store this controlled response body.")

    app = create_app(settings, httpx.MockTransport(service))
    with TestClient(app) as client:
        yield {"app": app, "client": client, "state": state,
               "headers": ProtectedHeaders({"X-Operator-Key": settings.operator_key.get_secret_value()})}


@pytest.fixture
def register(context):
    def create(path="healthy", **overrides):
        data = {"name": "Controlled API", "url": f"http://127.0.0.1:9001/health/{path}", **overrides}
        response = context["client"].post("/api/endpoints", headers=context["headers"], json=data)
        assert response.status_code == 201, response.text
        return response.json()
    return create


@pytest.fixture
def check(context):
    from uuid import uuid4
    def run(endpoint, key=None):
        return context["client"].post(f"/api/endpoints/{endpoint['id']}/checks",
                                     headers={**context["headers"], "Idempotency-Key": key or str(uuid4())})
    return run

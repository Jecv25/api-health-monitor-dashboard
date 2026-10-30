import hmac
import re
from contextlib import asynccontextmanager
from datetime import timedelta
from uuid import UUID, uuid4

import httpx
from fastapi import Depends, FastAPI, Header, Query, Request, Security
from fastapi.security import APIKeyHeader
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import case, func, select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from .config import Settings, get_settings
from .database import Base, iso, make_database, utcnow
from .logging_json import event, make_logger
from .models import CheckAttempt, CheckRun, Endpoint, Incident, Notification, WorkerHeartbeat
from .monitor import HealthRunner
from .presenters import endpoint_dict, incident_dict, notification_dict, run_dict
from .schemas import Acknowledgement, DomainError, EndpointInput, EndpointPatch, ErrorEnvelope, approved_url


def create_app(settings: Settings | None = None, transport=None):
    config = settings or get_settings()
    engine, sessions = make_database(config)
    logger = make_logger(config)

    @asynccontextmanager
    async def lifespan(app):
        config.validate_runtime()
        Base.metadata.create_all(engine)
        yield
        engine.dispose()

    app = FastAPI(title="Pulsewatch Monitoring API", version="0.1.0", lifespan=lifespan,
                  responses={code: {"model": ErrorEnvelope} for code in (401, 404, 409, 422, 503)},
                  description="Week 13 / SA7 controlled prototype. Mutations require X-Operator-Key. "
                  "Scheduled work runs in a separate worker. Times are UTC; uptime is sampled check success.")
    app.state.settings, app.state.engine, app.state.sessions = config, engine, sessions
    app.state.runner = HealthRunner(config, engine, sessions, logger, transport)
    app.add_middleware(CORSMiddleware, allow_origins=config.cors_origins,
                       allow_methods=["GET", "POST", "PATCH"],
                       allow_headers=["Content-Type", "X-Operator-Key", "Idempotency-Key", "X-Correlation-ID"],
                       expose_headers=["X-Correlation-ID"])

    @app.middleware("http")
    async def correlation(request, call_next):
        try:
            request.state.correlation_id = str(UUID(request.headers.get("X-Correlation-ID", "")))
        except ValueError:
            request.state.correlation_id = str(uuid4())
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = request.state.correlation_id
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    def error_response(request, code, message, status):
        return JSONResponse(status_code=status, content={"error": {
            "code": code, "message": message, "correlation_id": request.state.correlation_id}})

    @app.exception_handler(DomainError)
    async def domain_error(request, exc):
        return error_response(request, exc.code, exc.message, exc.status)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        fields = sorted({str(e["loc"][-1]) for e in exc.errors()})
        return error_response(request, "validation_error", "Check these fields: " + ", ".join(fields), 422)

    @app.exception_handler(SQLAlchemyError)
    async def database_error(request, exc):
        event(logger, "database.error", correlation_id=request.state.correlation_id, error_type=type(exc).__name__)
        return error_response(request, "database_unavailable", "Monitoring storage is unavailable. Try again shortly.", 503)

    operator_header = APIKeyHeader(name="X-Operator-Key", auto_error=False)

    def operator(x_operator_key: str | None = Security(operator_header)):
        expected = config.operator_key.get_secret_value()
        if not expected or not hmac.compare_digest(x_operator_key or "", expected):
            raise DomainError("unauthorized", "Connect with the local operator key to perform this action.", 401)

    protected = [Depends(operator)]

    @app.get("/healthz", tags=["Operations"])
    def health():
        try:
            with sessions() as db:
                db.execute(text("SELECT 1"))
                beat = db.get(WorkerHeartbeat, "scheduler")
                fresh = bool(beat and (utcnow() - beat.updated_at).total_seconds() < 90)
                return {"status": "ok", "database": "connected", "worker": "online" if fresh else "offline",
                        "worker_last_seen": iso(beat.updated_at) if beat else None,
                        "server_time": iso(utcnow()), "environment": config.app_env}
        except SQLAlchemyError:
            return JSONResponse(status_code=503, content={"status": "unavailable", "database": "unavailable", "worker": "unknown"})

    @app.get("/api/config", tags=["Operations"])
    def public_config():
        return {"demo_enabled": config.demo_enabled, "approved_origins": config.approved_origins,
                "recovery_successes": config.recovery_successes, "max_attempts": 3,
                "retry_base_seconds": config.retry_base_seconds, "max_endpoints": 50,
                "access_mode": "local_operator_capability", "version": "0.1.0"}

    @app.post("/api/operator/verify", dependencies=protected, tags=["Operations"])
    def verify_operator():
        return {"connected": True, "scope": "local_lab_operator"}

    @app.get("/api/endpoints", tags=["Endpoints"])
    def endpoints():
        with sessions() as db:
            return [endpoint_dict(db, item) for item in db.scalars(select(Endpoint).order_by(Endpoint.id))]

    @app.post("/api/endpoints", status_code=201, dependencies=protected, tags=["Endpoints"])
    def register(data: EndpointInput, request: Request):
        url = approved_url(data.url, config)
        with sessions() as db:
            if db.scalar(select(func.count()).select_from(Endpoint)) >= 50:
                raise DomainError("endpoint_limit", "This classroom prototype supports up to 50 registered services.", 409)
            item = Endpoint(**{**data.model_dump(), "url": url})
            db.add(item)
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                raise DomainError("duplicate_endpoint", "This endpoint URL is already registered.", 409) from None
            event(logger, "endpoint.registered", endpoint_id=item.id, correlation_id=request.state.correlation_id)
            return endpoint_dict(db, item)

    @app.patch("/api/endpoints/{endpoint_id}", dependencies=protected, tags=["Endpoints"])
    def pause(endpoint_id: int, data: EndpointPatch):
        with sessions() as db:
            endpoint = db.get(Endpoint, endpoint_id)
            if endpoint is None:
                raise DomainError("not_found", "Endpoint not found.", 404)
            endpoint.enabled = data.enabled
            if data.enabled:
                endpoint.next_check_at = utcnow()
            db.commit()
            return endpoint_dict(db, endpoint)

    @app.post("/api/endpoints/{endpoint_id}/checks", dependencies=protected, tags=["Checks"])
    async def check(endpoint_id: int, request: Request, idempotency_key: str = Header()):
        if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", idempotency_key):
            raise DomainError("invalid_idempotency_key", "Supply an Idempotency-Key with 1–64 safe identifier characters.")
        return await app.state.runner.run(endpoint_id, idempotency_key, request.state.correlation_id)

    @app.get("/api/endpoints/{endpoint_id}/checks", tags=["Checks"])
    def check_history(endpoint_id: int, limit: int = Query(default=30, ge=1, le=100)):
        with sessions() as db:
            if db.get(Endpoint, endpoint_id) is None:
                raise DomainError("not_found", "Endpoint not found.", 404)
            return [run_dict(run) for run in db.scalars(select(CheckRun).where(CheckRun.endpoint_id == endpoint_id)
                                                      .order_by(CheckRun.started_at.desc()).limit(limit))]

    @app.get("/api/incidents", tags=["Incidents"])
    def incidents():
        with sessions() as db:
            return [incident_dict(db, item) for item in db.scalars(select(Incident)
                                                                 .order_by(Incident.opened_at.desc()).limit(100))]

    @app.post("/api/incidents/{incident_id}/acknowledge", dependencies=protected, tags=["Incidents"])
    def acknowledge(incident_id: int, data: Acknowledgement, request: Request):
        with sessions() as db:
            item = db.scalar(select(Incident).where(Incident.id == incident_id).with_for_update())
            if item is None:
                raise DomainError("not_found", "Incident not found.", 404)
            if item.status == "recovered":
                raise DomainError("incident_recovered", "This incident has already recovered.", 409)
            if item.status != "acknowledged":
                item.status, item.acknowledged_by = "acknowledged", data.operator_alias
                item.acknowledged_at, item.note = utcnow(), data.note
                db.commit()
                event(logger, "incident.acknowledged", incident_id=item.id, endpoint_id=item.endpoint_id,
                      correlation_id=request.state.correlation_id)
            return incident_dict(db, item)

    @app.get("/api/notifications", tags=["Notifications"])
    def notifications():
        with sessions() as db:
            return [notification_dict(item) for item in db.scalars(select(Notification)
                                                        .order_by(Notification.created_at.desc()).limit(100))]

    @app.post("/api/notifications/{notification_id}/read", dependencies=protected, tags=["Notifications"])
    def read_notification(notification_id: int):
        with sessions() as db:
            item = db.get(Notification, notification_id)
            if not item:
                raise DomainError("not_found", "Notification not found.", 404)
            item.read_at = item.read_at or utcnow()
            db.commit()
            return notification_dict(item)

    @app.get("/api/reports", tags=["Reports"])
    def reports(hours: int = Query(default=24, ge=1, le=720)):
        since = utcnow() - timedelta(hours=hours)
        with sessions() as db:
            aggregates = db.execute(select(CheckRun.endpoint_id, func.count(CheckRun.id),
                                     func.sum(case((CheckRun.success.is_(True), 1), else_=0)),
                                     func.sum(case((CheckRun.status == "transient_recovered", 1), else_=0)))
                                    .where(CheckRun.finished_at >= since)
                                    .group_by(CheckRun.endpoint_id)).all()
            counts = {row[0]: row[1:] for row in aggregates}
            attempts = dict(db.execute(select(CheckRun.endpoint_id, func.count(CheckAttempt.id))
                                 .join(CheckAttempt, CheckAttempt.run_id == CheckRun.id)
                                 .where(CheckRun.finished_at >= since).group_by(CheckRun.endpoint_id)).all())
            average = db.scalar(select(func.avg(CheckAttempt.duration_ms)).join(CheckRun)
                                 .where(CheckRun.finished_at >= since))
            result = []
            for endpoint in db.scalars(select(Endpoint).order_by(Endpoint.id)):
                total, successful, transient = counts.get(endpoint.id, (0, 0, 0))
                result.append({"endpoint_id": endpoint.id, "name": endpoint.name, "status": endpoint.status,
                               "completed_checks": int(total), "successful_checks": int(successful),
                               "failed_checks": int(total-successful), "transient_recoveries": int(transient),
                               "retry_attempts": max(0, attempts.get(endpoint.id, 0)-total),
                               "uptime_percent": round(successful/total*100, 2) if total else None})
            total = sum(r["completed_checks"] for r in result)
            successful = sum(r["successful_checks"] for r in result)
            open_incidents = db.scalar(select(func.count()).select_from(Incident).where(Incident.status != "recovered"))
            recent = list(db.scalars(select(CheckRun).order_by(CheckRun.started_at.desc()).limit(8)))
            return {"hours": hours, "since": iso(since), "generated_at": iso(utcnow()),
                    "definition": "Successful completed check cycles / all completed check cycles. Sampled availability, not time-based SLA uptime.",
                    "summary": {"total_endpoints": len(result), "healthy": sum(r["status"] == "up" for r in result),
                                "unavailable": sum(r["status"] == "down" for r in result),
                                "recovering": sum(r["status"] == "recovering" for r in result),
                                "open_incidents": int(open_incidents), "completed_checks": total,
                                "successful_checks": successful, "failed_checks": total-successful,
                                "retry_attempts": sum(r["retry_attempts"] for r in result),
                                "transient_recoveries": sum(r["transient_recoveries"] for r in result),
                                "uptime_percent": round(successful/total*100, 2) if total else None,
                                "avg_response_ms": round(average, 2) if average is not None else None},
                    "endpoints": result,
                    "recent_runs": [{**run_dict(run), "endpoint_name": db.get(Endpoint, run.endpoint_id).name} for run in recent]}

    def require_demo():
        if not config.demo_enabled:
            raise DomainError("demo_disabled", "Controlled demonstration is disabled.", 404)

    @app.post("/api/demo/seed", dependencies=protected, tags=["Controlled demo"])
    def seed():
        require_demo()
        with sessions() as db:
            for name, path in [("Gateway API", "healthy"), ("Orders API", "transient"), ("Billing API", "persistent")]:
                url = approved_url(f"{config.demo_origin}/health/{path}", config)
                if not db.scalar(select(Endpoint).where(Endpoint.url == url)):
                    db.add(Endpoint(name=name, url=url, interval_seconds=60, owner_group="support"))
            db.commit()
            return [endpoint_dict(db, item) for item in db.scalars(select(Endpoint).order_by(Endpoint.id))]

    @app.post("/api/demo/{action}", dependencies=protected, tags=["Controlled demo"])
    async def demo_control(action: str):
        require_demo()
        if action not in ("recover", "reset"):
            raise DomainError("not_found", "Unknown demo control.", 404)
        try:
            async with httpx.AsyncClient(timeout=3, trust_env=False) as client:
                response = await client.post(f"{config.demo_origin}/control/{action}",
                                             headers={"X-Operator-Key": config.operator_key.get_secret_value()})
                response.raise_for_status()
            return {"action": action, "applied": True}
        except httpx.HTTPError:
            raise DomainError("demo_unavailable", "Start the controlled demo service on port 9001, then retry.", 503) from None

    return app


app = create_app()

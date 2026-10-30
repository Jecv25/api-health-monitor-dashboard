import asyncio
from datetime import timedelta
from time import perf_counter
from uuid import uuid4

import httpx
from sqlalchemy import select, text

from .database import utcnow
from .logging_json import event
from .models import CheckAttempt, CheckRun, Endpoint, Incident, Notification, WorkerHeartbeat
from .presenters import run_dict
from .schemas import DomainError, approved_url


class HealthRunner:
    def __init__(self, settings, engine, sessions, logger, transport=None):
        self.settings, self.engine, self.sessions = settings, engine, sessions
        self.logger, self.transport = logger, transport

    async def run(self, endpoint_id: int, key: str, correlation_id: str, source="manual"):
        lock_name = f"pw:{self.settings.db_name}:{endpoint_id}"
        with self.engine.connect() as lock:
            acquired = lock.execute(text("SELECT GET_LOCK(:name, 0)"), {"name": lock_name}).scalar()
            lock.commit()
            if acquired != 1:
                raise DomainError("check_in_progress", "A check is already running for this service. Refresh shortly.", 409)
            try:
                with self.sessions() as db:
                    endpoint = db.get(Endpoint, endpoint_id)
                    if not endpoint:
                        raise DomainError("not_found", "Endpoint not found.", 404)
                    existing = db.scalar(select(CheckRun).where(CheckRun.endpoint_id == endpoint_id,
                                                                CheckRun.idempotency_key == key))
                    if existing and existing.status != "running":
                        return run_dict(existing)
                    # Owning the lock proves no active process owns unfinished runs.
                    for old in db.scalars(select(CheckRun).where(CheckRun.endpoint_id == endpoint_id,
                                                                 CheckRun.status == "running")):
                        old.status, old.success = "interrupted", False
                        old.error_code, old.finished_at = "execution_interrupted", utcnow()
                        event(self.logger, "check.interrupted", run_id=old.id, endpoint_id=endpoint_id,
                              correlation_id=old.correlation_id)
                    db.commit()
                    if existing:
                        return run_dict(existing)
                    if not endpoint.enabled:
                        raise DomainError("endpoint_paused", "Resume the endpoint before checking it.", 409)
                    if source == "scheduled" and endpoint.next_check_at > utcnow():
                        raise DomainError("not_due", "A recent check already moved the schedule forward.", 409)
                    approved_url(endpoint.url, self.settings)  # Revalidate if the allowlist changed.
                    run = CheckRun(id=str(uuid4()), endpoint_id=endpoint_id, idempotency_key=key,
                                   correlation_id=correlation_id, source=source)
                    db.add(run)
                    db.commit()
                    event(self.logger, "check.started", run_id=run.id, endpoint_id=endpoint_id,
                          correlation_id=correlation_id, source=source)
                    started = perf_counter()
                    success, status, error = False, None, None
                    async with httpx.AsyncClient(transport=self.transport, follow_redirects=False,
                                                 trust_env=False) as client:
                        for number in range(1, 4):
                            attempt_started = perf_counter()
                            status, error = None, None
                            try:
                                status = await asyncio.wait_for(self._request(client, endpoint, run.id, number),
                                                                timeout=endpoint.timeout_seconds)
                                success = 200 <= status < 300
                                if not success:
                                    error = f"http_{status}"
                            except (TimeoutError, httpx.TimeoutException):
                                success, error = False, "timeout"
                            except httpx.RequestError:
                                success, error = False, "network_error"
                            attempt = CheckAttempt(run_id=run.id, number=number, success=success,
                                                   http_status=status, error_code=error,
                                                   duration_ms=round((perf_counter()-attempt_started)*1000, 2))
                            db.add(attempt)
                            db.commit()
                            event(self.logger, "attempt.finished", run_id=run.id, endpoint_id=endpoint_id,
                                  correlation_id=correlation_id, attempt=number, success=success,
                                  http_status=status, error_code=error, duration_ms=attempt.duration_ms)
                            retryable = status is None or status in (408, 429) or status >= 500
                            if success or not retryable or number == 3:
                                break
                            delay = self.settings.retry_base_seconds * 2 ** (number - 1)
                            event(self.logger, "retry.scheduled", run_id=run.id, endpoint_id=endpoint_id,
                                  correlation_id=correlation_id, next_attempt=number+1, delay_seconds=delay)
                            await asyncio.sleep(delay)
                    run.success, run.http_status, run.error_code = success, status, error
                    run.status = "transient_recovered" if success and number > 1 else "success" if success else "failed"
                    run.duration_ms = round((perf_counter()-started)*1000, 2)
                    run.finished_at = endpoint.last_check_at = utcnow()
                    endpoint.next_check_at = utcnow() + timedelta(seconds=endpoint.interval_seconds)
                    self._transition(db, endpoint, run)
                    db.commit()
                    db.refresh(run)
                    event(self.logger, "check.finished", run_id=run.id, endpoint_id=endpoint_id,
                          correlation_id=correlation_id, status=run.status, attempts=number,
                          duration_ms=run.duration_ms)
                    return run_dict(run)
            finally:
                lock.execute(text("SELECT RELEASE_LOCK(:name)"), {"name": lock_name})
                lock.commit()

    @staticmethod
    async def _request(client, endpoint, run_id, number):
        async with client.stream("GET", endpoint.url, timeout=endpoint.timeout_seconds,
                                 headers={"X-Check-Run": run_id, "X-Check-Attempt": str(number)}) as response:
            return response.status_code  # Never download or retain the response body.

    def _transition(self, db, endpoint, run):
        incident = db.scalar(select(Incident).where(Incident.endpoint_id == endpoint.id,
                                                   Incident.status != "recovered"))
        if not run.success:
            endpoint.status, endpoint.recovery_streak = "down", 0
            if incident is None:
                incident = Incident(endpoint_id=endpoint.id, owner_group=endpoint.owner_group,
                                    opening_run_id=run.id)
                db.add(incident)
                db.flush()
                db.add(Notification(endpoint_id=endpoint.id, incident_id=incident.id, kind="human_action",
                                    message=f"{endpoint.name} is unavailable. {endpoint.owner_group} action required."))
                event(self.logger, "incident.opened", incident_id=incident.id, endpoint_id=endpoint.id,
                      run_id=run.id, correlation_id=run.correlation_id, owner_group=endpoint.owner_group)
        elif incident is not None:
            endpoint.recovery_streak += 1
            if endpoint.recovery_streak >= self.settings.recovery_successes:
                endpoint.status, endpoint.recovery_streak = "up", 0
                incident.status, incident.recovered_at, incident.recovery_run_id = "recovered", utcnow(), run.id
                db.add(Notification(endpoint_id=endpoint.id, incident_id=incident.id, kind="recovery",
                                    message=f"{endpoint.name} recovered after {self.settings.recovery_successes} successful checks."))
                event(self.logger, "incident.recovered", incident_id=incident.id, endpoint_id=endpoint.id,
                      run_id=run.id, correlation_id=run.correlation_id)
            else:
                endpoint.status = "recovering"
        else:
            endpoint.status, endpoint.recovery_streak = "up", 0

    def heartbeat(self):
        with self.sessions() as db:
            beat = db.get(WorkerHeartbeat, "scheduler")
            if beat is None:
                db.add(WorkerHeartbeat(name="scheduler", updated_at=utcnow()))
            else:
                beat.updated_at = utcnow()
            db.commit()

    async def check_due(self):
        self.heartbeat()
        with self.sessions() as db:
            ids = list(db.scalars(select(Endpoint.id).where(Endpoint.enabled.is_(True),
                              Endpoint.next_check_at <= utcnow()).order_by(Endpoint.next_check_at).limit(100)))
        for endpoint_id in ids:
            try:
                await self.run(endpoint_id, str(uuid4()), str(uuid4()), "scheduled")
            except DomainError as exc:
                event(self.logger, "scheduled.skipped", endpoint_id=endpoint_id, reason=exc.code)
            except Exception as exc:
                event(self.logger, "scheduled.error", endpoint_id=endpoint_id, error_type=type(exc).__name__)
            self.heartbeat()

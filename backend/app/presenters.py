from sqlalchemy import select

from .database import iso
from .models import CheckRun, Endpoint, Incident, Notification


def run_dict(run: CheckRun):
    return {"id": run.id, "endpoint_id": run.endpoint_id, "correlation_id": run.correlation_id,
            "source": run.source, "status": run.status, "success": run.success,
            "http_status": run.http_status, "duration_ms": run.duration_ms,
            "error_code": run.error_code, "started_at": iso(run.started_at),
            "finished_at": iso(run.finished_at), "attempt_count": len(run.attempts),
            "attempts": [{"number": a.number, "success": a.success, "http_status": a.http_status,
                          "duration_ms": a.duration_ms, "error_code": a.error_code,
                          "recorded_at": iso(a.recorded_at)} for a in run.attempts]}


def endpoint_dict(db, endpoint: Endpoint):
    recent = list(db.scalars(select(CheckRun).where(CheckRun.endpoint_id == endpoint.id)
                            .order_by(CheckRun.started_at.desc()).limit(24)))
    samples = [r for r in recent if r.success is not None]
    last = next((r for r in recent if r.finished_at), None)
    return {"id": endpoint.id, "name": endpoint.name, "url": endpoint.url,
            "owner_group": endpoint.owner_group, "interval_seconds": endpoint.interval_seconds,
            "timeout_seconds": endpoint.timeout_seconds, "enabled": endpoint.enabled,
            "status": endpoint.status, "recovery_streak": endpoint.recovery_streak,
            "created_at": iso(endpoint.created_at), "last_check_at": iso(endpoint.last_check_at),
            "next_check_at": iso(endpoint.next_check_at),
            "last_run": run_dict(last) if last else None,
            "recent_samples": [bool(r.success) for r in reversed(samples)]}


def incident_dict(db, incident: Incident):
    endpoint = db.get(Endpoint, incident.endpoint_id)
    return {"id": incident.id, "endpoint_id": incident.endpoint_id, "endpoint_name": endpoint.name,
            "status": incident.status, "owner_group": incident.owner_group,
            "opened_at": iso(incident.opened_at), "acknowledged_at": iso(incident.acknowledged_at),
            "acknowledged_by": incident.acknowledged_by, "note": incident.note,
            "recovered_at": iso(incident.recovered_at), "opening_run_id": incident.opening_run_id,
            "recovery_run_id": incident.recovery_run_id, "recovery_streak": endpoint.recovery_streak}


def notification_dict(n: Notification):
    return {"id": n.id, "endpoint_id": n.endpoint_id, "incident_id": n.incident_id,
            "kind": n.kind, "message": n.message, "created_at": iso(n.created_at), "read_at": iso(n.read_at)}

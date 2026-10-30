from datetime import datetime

from sqlalchemy import Boolean, Float, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.dialects.mysql import DATETIME
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base, utcnow

UTCDateTime = DATETIME(fsp=6)


class Endpoint(Base):
    __tablename__ = "endpoints"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    url: Mapped[str] = mapped_column(String(512), unique=True)
    owner_group: Mapped[str] = mapped_column(String(40), default="support")
    interval_seconds: Mapped[int] = mapped_column(Integer, default=60)
    timeout_seconds: Mapped[int] = mapped_column(Integer, default=3)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    status: Mapped[str] = mapped_column(String(20), default="unknown")
    recovery_streak: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    last_check_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    next_check_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, index=True)


class CheckRun(Base):
    __tablename__ = "check_runs"
    __table_args__ = (UniqueConstraint("endpoint_id", "idempotency_key", name="uq_run_submission"),
                      Index("ix_runs_endpoint_started", "endpoint_id", "started_at"))
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    endpoint_id: Mapped[int] = mapped_column(ForeignKey("endpoints.id"))
    idempotency_key: Mapped[str] = mapped_column(String(64))
    correlation_id: Mapped[str] = mapped_column(String(36))
    source: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(24), default="running")
    success: Mapped[bool | None] = mapped_column(Boolean)
    http_status: Mapped[int | None] = mapped_column(Integer)
    duration_ms: Mapped[float | None] = mapped_column(Float)
    error_code: Mapped[str | None] = mapped_column(String(40))
    started_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, index=True)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    attempts: Mapped[list["CheckAttempt"]] = relationship(order_by="CheckAttempt.number", lazy="selectin")


class CheckAttempt(Base):
    __tablename__ = "check_attempts"
    __table_args__ = (UniqueConstraint("run_id", "number", name="uq_attempt_number"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[str] = mapped_column(ForeignKey("check_runs.id"))
    number: Mapped[int] = mapped_column(Integer)
    success: Mapped[bool] = mapped_column(Boolean)
    http_status: Mapped[int | None] = mapped_column(Integer)
    duration_ms: Mapped[float] = mapped_column(Float)
    error_code: Mapped[str | None] = mapped_column(String(40))
    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Incident(Base):
    __tablename__ = "incidents"
    id: Mapped[int] = mapped_column(primary_key=True)
    endpoint_id: Mapped[int] = mapped_column(ForeignKey("endpoints.id"), index=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    owner_group: Mapped[str] = mapped_column(String(40))
    opened_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    acknowledged_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    acknowledged_by: Mapped[str | None] = mapped_column(String(40))
    note: Mapped[str | None] = mapped_column(String(240))
    recovered_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    opening_run_id: Mapped[str] = mapped_column(ForeignKey("check_runs.id"))
    recovery_run_id: Mapped[str | None] = mapped_column(ForeignKey("check_runs.id"))


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(primary_key=True)
    endpoint_id: Mapped[int] = mapped_column(ForeignKey("endpoints.id"))
    incident_id: Mapped[int] = mapped_column(ForeignKey("incidents.id"))
    kind: Mapped[str] = mapped_column(String(24))
    message: Mapped[str] = mapped_column(String(240))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    read_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class WorkerHeartbeat(Base):
    __tablename__ = "worker_heartbeats"
    name: Mapped[str] = mapped_column(String(24), primary_key=True)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

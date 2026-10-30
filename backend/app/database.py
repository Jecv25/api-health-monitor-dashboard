from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import Settings


def utcnow() -> datetime:
    # MySQL DATETIME is stored as naive UTC; all API serialization restores Z.
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso(value: datetime | None) -> str | None:
    return value.isoformat(timespec="milliseconds") + "Z" if value else None


class Base(DeclarativeBase):
    pass


def make_database(settings: Settings):
    engine = create_engine(settings.database_url, pool_pre_ping=True,
                           pool_size=8, max_overflow=4,
                           connect_args={"connect_timeout": 3},
                           isolation_level="READ COMMITTED")
    return engine, sessionmaker(bind=engine, expire_on_commit=False)

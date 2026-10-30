import asyncio

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from .config import get_settings
from .database import Base, make_database
from .logging_json import event, make_logger
from .monitor import HealthRunner


async def serve():
    settings = get_settings()
    settings.validate_runtime()
    engine, sessions = make_database(settings)
    Base.metadata.create_all(engine)
    logger = make_logger(settings)
    runner = HealthRunner(settings, engine, sessions, logger)
    scheduler = AsyncIOScheduler(timezone="UTC")
    scheduler.add_job(runner.check_due, "interval", seconds=settings.worker_poll_seconds,
                      id="due-endpoints", max_instances=1, coalesce=True, misfire_grace_time=30)
    event(logger, "worker.started", poll_seconds=settings.worker_poll_seconds)
    runner.heartbeat()
    scheduler.start()
    try:
        await asyncio.Event().wait()
    finally:
        scheduler.shutdown(wait=False)
        engine.dispose()
        event(logger, "worker.stopped")


if __name__ == "__main__":
    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        pass

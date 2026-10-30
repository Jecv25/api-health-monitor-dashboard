import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from .config import BACKEND_ROOT, Settings


class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({"timestamp": datetime.now(timezone.utc).isoformat(),
                           "level": record.levelname, **record.msg}, default=str)


def make_logger(settings: Settings) -> logging.Logger:
    directory = Path(settings.log_dir)
    if not directory.is_absolute():
        directory = BACKEND_ROOT / directory
    directory.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger(f"pulsewatch.{directory.resolve()}")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    if not logger.handlers:
        handler = logging.FileHandler(directory / "automation.jsonl", encoding="utf-8")
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
    return logger


def event(logger: logging.Logger, name: str, **fields):
    # Callers pass bounded identifiers/outcomes, never URLs, bodies, keys or headers.
    logger.info({"event": name, **fields})

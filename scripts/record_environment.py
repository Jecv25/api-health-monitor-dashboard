import importlib.metadata
import json
import platform
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import text
from app.main import app

ROOT = Path(__file__).resolve().parent.parent
with app.state.engine.connect() as connection:
    mysql_version = connection.execute(text("SELECT VERSION()")).scalar()
versions = {name: importlib.metadata.version(name) for name in
            ("fastapi", "uvicorn", "SQLAlchemy", "PyMySQL", "APScheduler", "httpx", "pytest", "playwright")}
record = {"recorded_at": datetime.now(timezone.utc).isoformat(), "scope": "Week 13 / SA7 controlled monitoring",
          "os": platform.platform(), "python": platform.python_version(), "mysql": mysql_version,
          "libraries": versions, "database": "real MySQL, isolated project schema plus disposable _test schema",
          "ports": {"mysql": 3307, "api": 8000, "web": 8080, "controlled_service": 9001},
          "data": "fictional controlled endpoints and support-demo alias",
          "assistance": "Codex-assisted implementation and verification; student reproduction and viva pending"}
(ROOT / "evidence" / "environment.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
print("Recorded actual runtime/library versions without credentials.")

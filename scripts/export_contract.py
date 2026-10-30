import hashlib
import json
from pathlib import Path

from sqlalchemy.schema import CreateIndex, CreateTable
from sqlalchemy.dialects import mysql
from app.main import app
from app.database import Base

ROOT = Path(__file__).resolve().parent.parent
(ROOT / "docs" / "openapi.json").write_text(json.dumps(app.openapi(), indent=2), encoding="utf-8")
statements = ["-- Generated from SQLAlchemy models; MySQL 8.4. UTC DATETIME values.\n"]
for table in Base.metadata.sorted_tables:
    statements.append(str(CreateTable(table).compile(dialect=mysql.dialect())) + ";")
    statements.extend(str(CreateIndex(i).compile(dialect=mysql.dialect())) + ";" for i in table.indexes)
(ROOT / "database" / "schema.sql").write_text("\n\n".join(statements), encoding="utf-8")
print("Exported docs/openapi.json and database/schema.sql.")

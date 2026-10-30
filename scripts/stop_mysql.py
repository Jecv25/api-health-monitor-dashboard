import json
from pathlib import Path
import pymysql

root = Path(__file__).resolve().parent.parent
password = json.loads((root / ".runtime" / "mysql-admin.json").read_text())["password"]
try:
    connection = pymysql.connect(host="127.0.0.1", port=3307, user="root", password=password, connect_timeout=2)
    with connection.cursor() as cursor:
        cursor.execute("SELECT @@datadir")
        if Path(cursor.fetchone()[0]).resolve() != (root / ".runtime" / "mysql-data").resolve():
            raise SystemExit("Refusing to shut down a database outside this project's runtime directory.")
        cursor.execute("SHUTDOWN")
    connection.close()
    print("Project MySQL shut down cleanly.")
except pymysql.err.OperationalError as exc:
    if exc.args[0] != 2003:
        raise
    print("Project MySQL is already stopped.")

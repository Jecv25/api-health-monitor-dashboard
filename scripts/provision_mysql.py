"""Provision an isolated local MySQL instance; never touch an existing XAMPP database."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

import pymysql

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / ".runtime"
RUNTIME.mkdir(exist_ok=True)
MYSQL = ROOT / ".tools" / "mysql-8.4.8-winx64"
DATA = RUNTIME / "mysql-data"
ENV = ROOT / "backend" / ".env"
ADMIN = RUNTIME / "mysql-admin.json"


def connect(password=""):
    return pymysql.connect(host="127.0.0.1", port=3307, user="root", password=password,
                           connect_timeout=2, autocommit=True)


def main():
    if not (MYSQL / "bin" / "mysqld.exe").exists():
        raise SystemExit("Portable MySQL is missing. Run scripts/setup-local.ps1.")
    fresh = not (DATA / "mysql").exists()
    if fresh:
        DATA.mkdir(exist_ok=True)
        subprocess.run([str(MYSQL / "bin" / "mysqld.exe"), "--no-defaults", "--initialize-insecure",
                        f"--basedir={MYSQL}", f"--datadir={DATA}"], check=True,
                       stdout=subprocess.DEVNULL, stderr=(RUNTIME / "mysql-initialize.log").open("w"))
    admin = json.loads(ADMIN.read_text()) if ADMIN.exists() else {"password": ""}
    try:
        connection = connect(admin["password"])
        # Avoid configuring any unrelated server already using the selected port.
        with connection.cursor() as cursor:
            cursor.execute("SELECT @@datadir")
            actual = Path(cursor.fetchone()[0]).resolve()
            if actual != DATA.resolve():
                raise SystemExit("Port 3307 belongs to another database. Stop it or configure this project separately.")
    except pymysql.err.OperationalError:
        config = RUNTIME / "my.ini"
        config.write_text("[mysqld]\n" + f"basedir={MYSQL.as_posix()}\ndatadir={DATA.as_posix()}\n"
                          "bind-address=127.0.0.1\nport=3307\nmysqlx=0\n"
                          "character-set-server=utf8mb4\ncollation-server=utf8mb4_unicode_ci\n"
                          f"log-error={(RUNTIME / 'mysql-error.log').as_posix()}\n", encoding="utf-8")
        process = subprocess.Popen([str(MYSQL / "bin" / "mysqld.exe"), f"--defaults-file={config}"],
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        (RUNTIME / "mysql-process.json").write_text(json.dumps({"pid": process.pid}))
        for _ in range(45):
            try:
                connection = connect(admin["password"])
                break
            except pymysql.err.OperationalError:
                if process.poll() is not None:
                    raise SystemExit("MySQL stopped during startup. Inspect .runtime/mysql-error.log.")
                time.sleep(1)
        else:
            raise SystemExit("MySQL startup timed out. Inspect .runtime/mysql-error.log.")
    with connection:
        with connection.cursor() as cursor:
            if not admin["password"]:
                admin["password"] = secrets.token_urlsafe(32)
                cursor.execute("ALTER USER 'root'@'localhost' IDENTIFIED BY %s", (admin["password"],))
                ADMIN.write_text(json.dumps(admin), encoding="utf-8")
            if not ENV.exists():
                password, operator = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
                text = (ROOT / "backend" / ".env.example").read_text(encoding="utf-8")
                ENV.write_text(text.replace("DB_PASSWORD=\n", f"DB_PASSWORD={password}\n")
                               .replace("OPERATOR_KEY=\n", f"OPERATOR_KEY={operator}\n"), encoding="utf-8")
            values = dict(line.split("=", 1) for line in ENV.read_text().splitlines()
                          if "=" in line and not line.lstrip().startswith("#"))
            cursor.execute("CREATE DATABASE IF NOT EXISTS pulsewatch CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            cursor.execute("CREATE DATABASE IF NOT EXISTS pulsewatch_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            cursor.execute("CREATE USER IF NOT EXISTS 'pulsewatch'@'127.0.0.1' IDENTIFIED BY %s", (values["DB_PASSWORD"],))
            cursor.execute("GRANT ALL PRIVILEGES ON pulsewatch.* TO 'pulsewatch'@'127.0.0.1'")
            cursor.execute("GRANT ALL PRIVILEGES ON pulsewatch_test.* TO 'pulsewatch'@'127.0.0.1'")
            cursor.execute("SELECT VERSION()")
            version = cursor.fetchone()[0]
    print(f"Isolated MySQL {version} ready on 127.0.0.1:3307. Secrets saved locally, not printed.")


if __name__ == "__main__":
    main()

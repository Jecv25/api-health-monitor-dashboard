"""Normalize shell-output encoding, redact credential diagnostics, validate saved artifacts."""
import json
import re
from pathlib import Path
from xml.etree import ElementTree

from app.config import get_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    settings = get_settings()
    private = [settings.operator_key.get_secret_value(), settings.db_password.get_secret_value()]
    count = 0
    for path in (ROOT / "evidence").rglob("*"):
        if not path.is_file() or path.suffix not in (".txt", ".xml", ".json", ".jsonl", ".md"):
            continue
        content = path.read_bytes()
        text = content.decode("utf-16") if content.startswith((b"\xff\xfe", b"\xfe\xff")) else content.decode("utf-8-sig", errors="replace")
        text = text.replace("\x00", "").lstrip("\ufffd\ufeff")
        text = text.replace("<redacted-local-value>", "[REDACTED]")
        for secret in private:
            if secret:
                text = text.replace(secret, "[REDACTED]")
        text = re.sub(r"(?<=X-Operator-Key': ')[A-Za-z0-9_-]{24,}", "[REDACTED]", text)
        path.write_text(text, encoding="utf-8")
        if path.suffix == ".json":
            json.loads(text)
        elif path.suffix == ".jsonl":
            for line in text.splitlines():
                if line:
                    json.loads(line)
        elif path.suffix == ".xml":
            ElementTree.fromstring(text)
        count += 1
    print(f"Validated and normalized {count} evidence text artifacts; credentials excluded.")


if __name__ == "__main__":
    main()

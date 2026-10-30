"""Export a reviewable source/evidence archive; exclude all local secrets and runtimes."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from app.config import get_settings

ROOT = Path(__file__).resolve().parent.parent
DIRECTORIES = ["backend/app", "backend/tests", "frontend/lib", "frontend/test", "frontend/web",
               "docs", "database", "scripts", "evidence"]
FILES = ["README.md", ".gitignore", "backend/.env.example", "backend/requirements.txt",
         "backend/requirements.lock.txt", "backend/requirements-qa.txt", "frontend/pubspec.yaml",
         "frontend/pubspec.lock", "frontend/analysis_options.yaml", "frontend/.metadata"]


def main():
    settings = get_settings()
    paths = [ROOT / name for name in FILES if (ROOT / name).exists()]
    for name in DIRECTORIES:
        paths.extend(p for p in (ROOT / name).rglob("*") if p.is_file() and
                     "__pycache__" not in p.parts and p.suffix not in (".pyc", ".zip") and p.name != ".env")
    paths = sorted(set(paths))
    secrets = [settings.operator_key.get_secret_value(), settings.db_password.get_secret_value()]
    admin = ROOT / ".runtime" / "mysql-admin.json"
    if admin.exists():
        secrets.append(json.loads(admin.read_text())["password"])
    for path in paths:
        content = path.read_bytes()
        if any(secret and secret.encode() in content for secret in secrets):
            raise SystemExit(f"Refusing to package a local credential in {path.relative_to(ROOT)}")
    # Source-only fingerprint avoids circular hashing of evidence manifests/archives.
    source = {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in paths if "evidence" not in p.relative_to(ROOT).parts}
    manifest = {"created_at": datetime.now(timezone.utc).isoformat(), "sha256_files": source,
                "source_sha256": hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest(),
                "excluded": ["backend/.env", ".tools", ".runtime", "frontend/build", "backend/logs"]}
    manifest_path = ROOT / "evidence" / "source-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    if manifest_path not in paths:
        paths.append(manifest_path)
    output = ROOT / "deliverables"
    output.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive = output / f"Pulsewatch-Week13-SA7-{stamp}.zip"
    with ZipFile(archive, "w", ZIP_DEFLATED) as package:
        for path in paths:
            package.write(path, str(path.relative_to(ROOT)))
    print(f"Packaged {len(paths)} source/evidence files: deliverables/{archive.name}")
    print(f"Source fingerprint: {manifest['source_sha256']}")


if __name__ == "__main__":
    main()

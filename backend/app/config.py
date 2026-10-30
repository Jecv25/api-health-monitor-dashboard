from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL

BACKEND_ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_ROOT / ".env", extra="ignore")
    db_host: str = "127.0.0.1"
    db_port: int = 3307
    db_name: str = Field(default="pulsewatch", pattern=r"^[A-Za-z0-9_]{1,32}$")
    db_user: str = "pulsewatch"
    db_password: SecretStr = SecretStr("")
    operator_key: SecretStr = SecretStr("")
    app_env: str = "local"
    approved_origins: list[str] = ["http://127.0.0.1:9001"]
    cors_origins: list[str] = ["http://localhost:8080", "http://127.0.0.1:8080"]
    demo_enabled: bool = True
    demo_origin: str = "http://127.0.0.1:9001"
    retry_base_seconds: float = Field(default=0.5, ge=0, le=2)
    recovery_successes: int = Field(default=2, ge=2, le=5)
    worker_poll_seconds: int = Field(default=2, ge=1, le=30)
    log_dir: str = "logs"

    @property
    def database_url(self) -> URL:
        return URL.create("mysql+pymysql", username=self.db_user,
                          password=self.db_password.get_secret_value(), host=self.db_host,
                          port=self.db_port, database=self.db_name,
                          query={"charset": "utf8mb4"})

    def validate_runtime(self) -> None:
        if len(self.operator_key.get_secret_value()) < 24:
            raise RuntimeError("Set a generated OPERATOR_KEY of at least 24 characters in backend/.env.")
        if not self.db_password.get_secret_value():
            raise RuntimeError("Configure DB_PASSWORD in backend/.env; see README.md.")


@lru_cache
def get_settings() -> Settings:
    return Settings()

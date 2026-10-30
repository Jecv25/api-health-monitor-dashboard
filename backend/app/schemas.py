from urllib.parse import urlsplit, urlunsplit

from pydantic import BaseModel, Field

from .config import Settings


class DomainError(Exception):
    def __init__(self, code: str, message: str, status: int = 422):
        self.code, self.message, self.status = code, message, status


class ErrorDetail(BaseModel):
    code: str
    message: str
    correlation_id: str


class ErrorEnvelope(BaseModel):
    error: ErrorDetail


class EndpointInput(BaseModel):
    name: str = Field(min_length=2, max_length=80, pattern=r"^[A-Za-z0-9][A-Za-z0-9 ._-]+$")
    url: str = Field(min_length=8, max_length=512)
    interval_seconds: int = Field(default=60, ge=15, le=3600, strict=True)
    timeout_seconds: int = Field(default=3, ge=1, le=10, strict=True)
    owner_group: str = Field(default="support", pattern=r"^(support|developers)$")


class EndpointPatch(BaseModel):
    enabled: bool = Field(strict=True)


class Acknowledgement(BaseModel):
    operator_alias: str = Field(min_length=2, max_length=40, pattern=r"^[A-Za-z0-9][A-Za-z0-9_.-]+$")
    note: str = Field(default="Investigating the controlled service.", max_length=240)


def approved_url(value: str, settings: Settings) -> str:
    try:
        parsed = urlsplit(value.strip())
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            raise ValueError()
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError()
        if any(ord(c) < 33 for c in value) or "\\" in value or "%" in parsed.netloc:
            raise ValueError()
        port = parsed.port
        host = parsed.hostname.lower()
        if ":" in host:
            host = f"[{host}]"
        authority = host + (f":{port}" if port else "")
        origin = f"{parsed.scheme}://{authority}"
        if origin not in settings.approved_origins:
            raise DomainError("origin_not_approved", "Choose a service origin approved in the backend configuration.")
        return urlunsplit((parsed.scheme, authority, parsed.path or "/", "", ""))
    except ValueError:
        raise DomainError("invalid_url", "Use an approved HTTP(S) URL without credentials, query strings, or fragments.") from None

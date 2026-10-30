"""Loopback-only fictional service. No real service or production credential is used."""
import hmac

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse

from .config import get_settings

app = FastAPI(title="Controlled classroom service", version="0.1.0")
app.state.recovered = False


@app.get("/health/{scenario}")
def health(scenario: str, x_check_attempt: str = Header(default="1")):
    if scenario in ("healthy", "healthy-ui"):
        return {"status": "healthy", "fictional": True}
    if scenario == "transient":
        return JSONResponse(status_code=503 if x_check_attempt == "1" else 200,
                            content={"scenario": "transient", "fictional": True})
    if scenario == "persistent":
        return JSONResponse(status_code=200 if app.state.recovered else 503,
                            content={"scenario": "persistent", "fictional": True})
    if scenario == "invalid":
        return JSONResponse(status_code=404, content={"scenario": "nonretryable"})
    raise HTTPException(status_code=404, detail="Unknown controlled scenario")


@app.post("/control/{action}")
def control(action: str, x_operator_key: str = Header(default="")):
    settings = get_settings()
    expected = settings.operator_key.get_secret_value()
    if not settings.demo_enabled or not expected or not hmac.compare_digest(x_operator_key, expected):
        raise HTTPException(status_code=401, detail="Operator access required")
    if action not in ("recover", "reset"):
        raise HTTPException(status_code=404, detail="Unknown control")
    app.state.recovered = action == "recover"
    return {"recovered": app.state.recovered, "fictional": True}

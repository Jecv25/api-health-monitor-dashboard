# API contract — Week 13 / SA7

Base URL in the controlled lab: `http://127.0.0.1:8000`. JSON; UTC ISO-8601 timestamps ending in `Z`. `/docs` provides Swagger; `openapi.json` is exported by `scripts/export_contract.py`. The OpenAPI API-key scheme is `X-Operator-Key`. The key is server configuration, never a Flutter compile-time value.

| Method and route | Access | Request / result |
| --- | --- | --- |
| `GET /healthz` | Local reader | API/storage signal, worker heartbeat and server time; 503 if MySQL is unavailable |
| `GET /api/config` | Local reader | Approved service origins, retry/recovery bounds, controlled-demo flag; no secrets |
| `POST /api/operator/verify` | Operator | Verify capability; 401 for absent/invalid capability |
| `GET /api/endpoints` | Local reader | Registered endpoints, latest run and up to 24 recent completed check samples |
| `POST /api/endpoints` | Operator | Register validated endpoint; 201, 409 duplicate/limit, or 422 invalid input |
| `PATCH /api/endpoints/{id}` | Operator | `{"enabled":false}` pauses future checks; in-flight check can finish |
| `POST /api/endpoints/{id}/checks` | Operator | Required `Idempotency-Key` header; returns the completed run, 409 if paused/in progress |
| `GET /api/endpoints/{id}/checks?limit=30` | Local reader | At most 100 recent runs including individual attempts |
| `GET /api/incidents` | Local reader | Most recent 100 incidents with acknowledgement and recovery metadata |
| `POST /api/incidents/{id}/acknowledge` | Operator | Support alias and bounded note; cannot mark a service recovered |
| `GET /api/notifications` | Local reader | Most recent 100 durable notifications |
| `POST /api/notifications/{id}/read` | Operator | Idempotently mark notification read |
| `GET /api/reports?hours=24` | Local reader | Reporting window 1–720 hours; SQL aggregates plus recent activity |
| `POST /api/demo/seed` | Operator; demo enabled | Register three controlled fixtures without duplicating their URLs |
| `POST /api/demo/reset` | Operator; demo enabled | Restore the controlled persistent 503 dependency |
| `POST /api/demo/recover` | Operator; demo enabled | Repair controlled dependency; monitoring must still verify recovery |

## Registration example

```json
{"name":"Example API","url":"http://127.0.0.1:9001/health/healthy","interval_seconds":60,"timeout_seconds":3,"owner_group":"support"}
```

Name: 2–80 letters/numbers/spaces/dots/underscores/hyphens, starting with a letter/number. URL: at most 512 characters, HTTP(S), exact allowlisted origin, no user credentials/query/fragment/whitespace. Interval: integer 15–3600; timeout: integer 1–10. Ownership: `support` or `developers`. Classroom registration is capped at 50 through the registration route; this is not a distributed quota guarantee.

## Run response fields

`id` UUID, `endpoint_id` integer, `correlation_id` UUID, `source` (`manual`/`scheduled`), `status` (`running`/`success`/`transient_recovered`/`failed`/`interrupted`), nullable `success`, nullable `http_status`, nullable total-cycle `duration_ms`, nullable bounded `error_code`, UTC `started_at` and nullable `finished_at`, integer `attempt_count`, and `attempts` array. Each attempt contains number (1–3), success, nullable HTTP status/error code, elapsed milliseconds and recorded timestamp. No service response body or HTTP credentials are retained.

POST success is HTTP 200 even when the monitored dependency is unavailable: the monitoring operation completed and its run contains `success:false`. A monitoring-storage error is HTTP 503. Browser actions inspect both the HTTP response and the recorded monitoring outcome.

Idempotency keys are 1–64 characters from `[A-Za-z0-9_.:-]`, scoped to an endpoint and retained with the run. Replay returns that recorded run. New checks need new keys. If a request loses its response, replay the original key rather than treating it as a new operation.

## Error envelope

```json
{"error":{"code":"origin_not_approved","message":"Choose a service origin approved in the backend configuration.","correlation_id":"00000000-0000-4000-8000-000000000000"}}
```

Safe errors: 401 unauthorized; 404 missing record/disabled demo; 409 duplicate/in-flight/paused/already recovered; 422 validation/unapproved origin; 503 unavailable storage or demo dependency. `X-Correlation-ID` is returned for tracing. Supplied correlation IDs are accepted only when valid UUIDs. Response cache is disabled.

## Summary semantics

Successful completed cycles / all completed cycles in the requested window × 100. Retried success counts as one successful cycle and contributes additional retry attempts. Interrupted cycles count as failed completed cycles when reconciled. No completed cycles means `null`, displayed as `—`. This is sampled availability, not time-weighted availability or an SLA. Average response measures individual attempt elapsed time, including unsuccessful/timeout attempts; total cycle time includes backoff and database overhead.

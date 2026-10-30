# Architecture and data model

## Components and alternatives

Flutter is the required browser client. FastAPI exposes the application contract; one separate APScheduler worker runs the same monitoring service. MySQL is the user's chosen persistence engine. SQLAlchemy separates storage from API and monitoring logic. HTTPX performs allowlisted health requests with TLS verification enabled for HTTPS and redirects disabled.

```mermaid
flowchart TB
  subgraph Browser[Untrusted browser]
    UI[Flutter Web / responsive presentation]
    K[Operator capability in memory]
  end
  subgraph Lab[Controlled local machine]
    API[FastAPI :8000 / boundary validation]
    Worker[Independent APScheduler worker]
    Monitor[Shared check and recovery service]
    DB[(MySQL :3307)]
    Demo[Controlled service :9001]
    Logs[Structured local JSON logs]
  end
  UI --> API
  K -->|mutation header| API
  API --> Monitor
  Worker --> Monitor
  API --> DB
  Monitor -->|advisory endpoint lock| DB
  Monitor -->|bounded allowlisted GET| Demo
  Monitor --> DB
  Monitor --> Logs
```

Decisions and rejected alternatives are recorded in `week13-design.md`: interval vs browser/event triggers; a single worker vs distributed queue; bounded retries vs continuous retries. SQLite was discussed before the user's explicit MySQL choice. The actual implementation and evidence use MySQL, with no SQLite fallback.

## Entity relationships

```mermaid
erDiagram
  ENDPOINTS ||--o{ CHECK_RUNS : checked_by
  CHECK_RUNS ||--o{ CHECK_ATTEMPTS : records
  ENDPOINTS ||--o{ INCIDENTS : experiences
  CHECK_RUNS ||--o{ INCIDENTS : opens_or_recovers
  INCIDENTS ||--o{ NOTIFICATIONS : announces
  ENDPOINTS ||--o{ NOTIFICATIONS : concerns
  ENDPOINTS {
    int id PK
    string url UK
    int interval_seconds
    string status
    int recovery_streak
    datetime next_check_at
  }
  CHECK_RUNS {
    uuid id PK
    int endpoint_id FK
    string idempotency_key
    string status
    uuid correlation_id
  }
  CHECK_ATTEMPTS {
    int id PK
    uuid run_id FK
    int number
    int http_status
    float duration_ms
  }
  INCIDENTS {
    int id PK
    int endpoint_id FK
    string status
    string owner_group
    string acknowledged_by
  }
  NOTIFICATIONS {
    int id PK
    int incident_id FK
    string kind
    datetime read_at
  }
  WORKER_HEARTBEATS {
    string name PK
    datetime updated_at
  }
```

MySQL `DATETIME(6)` stores naive UTC with microsecond precision. This avoids near-future rounding of immediately due checks. API serialization explicitly appends `Z`. The schema is generated in `database/schema.sql`; the composite `(endpoint_id,idempotency_key)` and `(run_id,number)` constraints prevent duplicate submissions/attempt numbers.

## Failure and recovery sequence

```mermaid
sequenceDiagram
  participant W as Worker or manual API
  participant M as Monitoring service
  participant D as MySQL
  participant S as Controlled service
  participant H as Support via Flutter
  W->>M: Check endpoint
  M->>D: Acquire endpoint lock; persist running record
  loop Up to three total attempts
    M->>S: Bounded GET
    S-->>M: 503 / timeout
    M->>D: Persist attempt
  end
  M->>D: Failed cycle + one incident + human-action notification
  M->>D: Release lock
  H->>D: Acknowledge through protected API
  H->>S: Repair controlled dependency
  W->>M: Next check
  S-->>M: 200
  M->>D: Recovery streak 1; incident remains active
  W->>M: Following check
  S-->>M: 200
  M->>D: Mark recovered + one recovery notification
```

Credentials cross only the local operator boundary or server-side MySQL connection. Logs contain identifiers/outcomes, not credentials, headers, query strings or dependency response bodies. Local HTTP, shared capability and read-only unauthenticated lab views are explicit residual risks for Week 14.

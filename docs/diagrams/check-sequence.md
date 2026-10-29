# Check, retry, and recovery sequence

Status: implemented local behavior. This sequence describes a single accepted run; run-all/scheduler triggers allocate a child correlation per run.

```mermaid
sequenceDiagram
    actor Operator as Demo operator
    participant UI as Flutter / API client
    participant API as Express + check service
    participant DB as SQLite
    participant Dep as Local HTTP fixture
    participant Logs as JSONL log
    Operator->>UI: Register or run check
    UI->>API: Mutation + demo cookie + idempotency key
    alt Missing session, viewer mutation, or invalid input
        API->>Logs: Denial / validation event + correlation
        API-->>UI: Safe 401 / 403 / 400 / 422; no domain work
    else Valid authorized request
        API->>DB: Look up key and reserve run/capacity transactionally
        alt Accepted request replay
            DB-->>API: Original response and resource IDs
            API-->>UI: Original accepted response + replay marker
        else Conflicting key, active run, or no capacity
            API-->>UI: 409 or 503; no queued job
        else New run reserved
            API-->>UI: 202 + run ID + status URL
            loop At most three attempts; stop on success or non-retryable failure
                API->>Dep: GET with 3000 ms timeout and run metadata
                Dep-->>API: Actual HTTP response or transport failure
                API->>DB: Persist measured attempt
                API->>Logs: Attempt + correlation/run ID
                opt Retryable failure and attempts remain
                    API->>Logs: retry_scheduled, wait_ms 700
                    Note over API: Wait at least 700 ms before next attempt
                end
            end
            alt Saved passing result
                API->>DB: Atomic result + UP + run completion
                opt Active incident exists
                    Note over API,DB: Same transaction also sets RECOVERED and inserts one recovery notice
                end
                API->>Logs: Completion / transient recovery / verified recovery
            else Saved failed result
                API->>DB: Atomic result + DOWN + run completion + open/reuse incident
                Note over API,DB: New incident gets one in-app support notice
                API->>Logs: Completion + human-action incident event
            end
            UI->>API: GET run and related committed state
            API-->>UI: Attempts, result, incident and demo notice
        end
    end
    opt Human follow-up after outage
        Operator->>API: Acknowledge incident
        API->>DB: Save ACKNOWLEDGED and actor/time; still DOWN
        Operator->>API: Simulate fix: future behavior stable
        Note over API,DB: No recovery transition yet
        Operator->>API: New check; repeat accepted-run sequence
        Note over API,DB: Only a committed passing run verifies recovery
    end
```

The “saved” branches assume the transaction succeeds. A failed attempt write/final transaction stops further work, pauses dispatch, and emits a safe storage error; it does not choose either committed-result branch. On process interruption, startup preserves saved attempts and marks the run INTERRUPTED. Neither a missing response nor a UI repair action is evidence of success.

# Boundary and data-flow diagram

Status: implemented local Module 13 architecture, originally drawn before code. Node/Express, SQLite, the controlled fixture, and Flutter are present; see the evidence index for observed execution. No external deployment is claimed.

```mermaid
flowchart LR
    Human["Fictional operator / viewer"]
    subgraph Browser["Untrusted browser boundary"]
        UI["Flutter Web\nDemo login and workflow screens\nNo stored secrets"]
    end
    subgraph Backend["Trusted local backend boundary: one Node process"]
        API["Express API\nValidate + demo capability check\nIdempotency reservation"]
        Scheduler["Scheduler\nDue times + two-slot capacity"]
        Worker["Check service\nGET, timeout, max three attempts"]
        Domain["Atomic finalization\nResult + status + incident + notice"]
    end
    subgraph Disk["Maintainer-controlled local storage"]
        DB[("SQLite\nRuns, attempts, results\nIncidents, notices, keys")]
        Log["Append-only JSONL lab log\nCorrelations and safe diagnostics"]
    end
    subgraph Dependency["Controlled dependency boundary"]
        Fixture["Loopback HTTP fixture\n200 / transient 503 / persistent 503 / 404\nNo real external service"]
    end
    Human --> UI
    UI -->|"JSON + opaque demo cookie; no real credentials"| API
    API -->|"Validate and reserve"| DB
    API --> Worker
    Scheduler -->|"Same reservation and worker rules"| Worker
    Worker -->|"Fixed loopback target; fictional URL path only"| Fixture
    Fixture -->|"Actual response or transport failure"| Worker
    Worker -->|"Save each attempt before retry"| DB
    Worker --> Domain
    Domain --> DB
    API --> Log
    Worker --> Log
    Scheduler --> Log
    DB -->|"Saved state and in-app demo notices"| API
    API -->|"Safe JSON + correlation ID"| UI
    Human -->|"Acknowledge responsibility; explicitly simulate repair"| UI
```

The browser is not a trusted authority for roles, results, or recovery. The server-side demo session is a placeholder rather than a real credential system. All records are fictional; no personal data or dependency secrets are needed. Local filesystem contents remain maintainer-controlled. DB and log sinks are separate, so reconcile them rather than claiming a cross-file atomic commit. Exceptional paths return safe API errors and retain evidence; storage failure pauses automation.

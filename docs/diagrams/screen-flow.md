# Screen navigation

Status: implemented Flutter Web navigation, first sketched in Stage 1 from the HTML prototype. See [screen details and states](../flutter-screen-flow.md).

```mermaid
flowchart TD
    Login["Login placeholder\nSelect local demo persona"]
    List["Endpoint List\nRun checks / scheduler controls"]
    Register["Register Endpoint\nInline + authoritative server validation"]
    Detail["Endpoint Detail / Results\nAttempts + final result + interrupted runs"]
    Incidents["Incidents\nAcknowledge + in-app support notices"]
    Report["Uptime Report\nCompleted-check ratio / No data"]
    Logs["Structured Logs\nRead / filter / copy"]
    Guide["Evidence Guide\nThree controlled demos"]
    Login --> List
    List --> Register
    Register -->|"201 saved"| List
    Register -->|"Invalid or duplicate: retain input"| Register
    List --> Detail
    Detail -->|"Linked incident"| Incidents
    Incidents -->|"Linked endpoint"| Detail
    List --> Incidents
    List --> Report
    List --> Logs
    List --> Guide
    Detail -->|"Run correlation filter"| Logs
    Detail --> List
    Incidents --> List
    Report --> List
    Logs --> List
    Guide --> List
    List -->|"Logout or 401"| Login
```

All protected screens follow the same 401-to-login rule. A 403 retains the readable view and explains the missing demo capability. Network/server errors retain input or last confirmed state and provide safe retry feedback. Run completion updates data without requiring navigation to a separate success page. A viewer can navigate read views but cannot mutate server state.

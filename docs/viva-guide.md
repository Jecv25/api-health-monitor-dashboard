# Module 13 viva practice notes

These are explanations of the implemented work, not a claim about the student's independent contribution. Review the source and actual evidence before using them.

| Likely question | Brief explanation you can verify |
| --- | --- |
| Why schedule checks on the backend? | The workflow must not depend on an open browser tab. One backend owns due times, retry rules, and saved outcomes. It still cannot monitor while its local process is off. |
| Why polling plus manual requests? | Polling can detect a silent service. Manual checks let a person verify an injected repair immediately. Both call the same worker, so their retry behavior stays consistent. |
| What does “3 attempts” mean? | The first request plus at most two retries. The worker waits 700 ms between retryable failures and times each request out at 3,000 ms. HTTP 404 stops after one attempt. |
| What did the transient demo prove? | The actual local fixture returned 503, 503, then 200. All attempts were saved, but the run contributed only one passed completed check and no new incident. |
| How do you avoid duplicate incidents? | A transaction opens/reuses the incident and a database index permits only one OPEN/ACKNOWLEDGED incident per endpoint. Repeated failures retain the same active incident. |
| What is idempotency here? | The same accepted method/route/actor/key/payload replays its saved response. The response and domain change commit together. A changed payload under that key is rejected. |
| Does acknowledge mean fixed? | No. It records human responsibility. Even Simulate fix changes only future fixture behavior; a new committed passing check verifies recovery. |
| What happens if HTTP succeeds but saving fails? | The final transaction rolls back. There is no saved success or recovery notice. Automation pauses, attempts remain, and the run is interrupted for reconciliation. F02 captures this case. |
| What happens after a crash? | C01 kills a real child backend after a saved failed attempt. Startup preserves that attempt, marks the old run INTERRUPTED, disables scheduling, and requires a new observation. |
| Why SQLite and one process? | It keeps setup and transaction ownership small enough to inspect. The tradeoff is no distributed scheduling, high availability, or monitoring during downtime. |
| What is the uptime number? | Successful completed checks divided by all completed checks. Retries do not inflate the denominator; interrupted runs are excluded; zero observations shows No data. It is not elapsed uptime. |
| Is the login secure? | It is explicitly a selectable demo placeholder. The API demonstrates 401/403 rejection branches; real authentication and deployed security belong to Module 14. |
| Are the service failures fake evidence? | The dependency modes are deliberately injected, while HTTP calls, timings, saved outcomes, logs, and screenshots are real. Browser-only UI response stubs are labeled separately. |
| What failed during development? | Dropdown layout tests and some Flutter accessibility selectors failed. Original failures were preserved, corrected, and rerun. Their timestamps/logs are in the evidence index. |

Before the viva, identify one source function you can explain and modify, one evidence record you can reproduce, and one limitation you understand. Write your own truthful contribution/reflection; do not claim you personally performed work you have not reviewed or repeated. [Decision record](decision-record.md), [actual evidence](../evidence/evidence-index.md), and [maintainability note](../maintainability-note.md) supply the technical basis.

# Proportional Week 13 controls

| Objective | Implemented control | Verification / remaining boundary |
| --- | --- | --- |
| Protect database configuration | Generated local password in ignored backend `.env`; example values blank; app DB grants limited to project schemas | Submission packager rejects current credentials and excludes runtime/config files; full secret-store integration is later work |
| Bound endpoint access | Exact server-side origin allowlist, GET only, no redirects, reject embedded credentials/query/fragment | Invalid/unapproved/redirect tests; generalized DNS/private-network hardening remains future work |
| Reject unauthorized mutation | Constant-time comparison of generated local operator capability; memory-only browser key | API 401 tests and actual browser invalid-key capture; full individual identities/RBAC remain Week 14 |
| Prevent unbounded automation | Three attempts maximum, outer request deadline, bounded exponential waits, one scheduler instance per process | Actual transient/persistent demos plus timeout/network tests |
| Avoid duplicate work | Connection-scoped MySQL lock, endpoint/idempotency-key unique constraint | Overlap and idempotency tests plus repeated actual HTTP request |
| Minimize stored/logged data | Status, timings, IDs and fictional support aliases; no service bodies, credentials or request headers in logs | Structured-log test; sanitized log export tied to actual demo run IDs |
| Make failures actionable | Safe errors with correlation IDs; persisted support incident and notifications | Original failures, reruns, HTTP observations and browser recovery flow |
| Protect web resource interpretation | Explicit JavaScript/Wasm MIME types and `X-Content-Type-Options: nosniff` | Real Edge initialization after the recorded Windows MIME fix |

No additional cryptography is added to monitoring payloads without a protection objective. Existing HTTPS verification is preserved for HTTPS targets, and the MySQL client supports the server's authentication mechanism. This checklist does not assert Week 14 encryption, user authentication, authorization or HTTPS deployment completion.

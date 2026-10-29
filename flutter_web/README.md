# Flutter Web client — Module 13

This is the actual Flutter source for Pulseboard. It includes a labeled demo login, endpoint list/registration, endpoint detail and attempt/results history, incidents/acknowledgement and support notices, uptime report, structured logs, and the three-demo guide.

```powershell
flutter.bat pub get
flutter.bat analyze
flutter.bat test --reporter expanded
flutter.bat build web --release --no-web-resources-cdn
```

Start `npm.cmd start` in `../backend` and open `http://localhost:3000`. The release build uses the current browser origin for `/api/v1`; the backend serves its files. For a separate Flutter development server on localhost:8080, pass `--dart-define=API_BASE_URL=http://localhost:3000/api/v1` and keep `FLUTTER_ORIGIN` in the backend consistent.

`lib/api.dart` centralizes async JSON requests, safe error parsing, server correlation references, cookie credentials, and UUID mutation keys. Its platform adapter uses a credentialed BrowserClient on Web; the VM adapter permits focused widget tests. `lib/validation.dart` mirrors authoritative server rules. `lib/main.dart` contains the shared shell, cards, forms, status chips, views, and workflow state.

No password, token, or confidential setting is embedded in Flutter. The selectable operator/viewer persona is explicitly a local placeholder; server-side rejection still applies. A lost mutation response retains the same key for safe retry. Loading, empty, validation, no-session, forbidden, network, safe server-error, dependency failure, and interruption feedback are represented. A first-invalid-field focus action supports keyboard correction.

At 1280 pixels, navigation uses a left rail. At 768 and 390 pixels, a drawer and wrapping cards/actions keep core tasks operable. Semantic labels and text accompany colors; the browser verification uses Flutter's accessibility semantics rather than replacing the application with HTML. The original failed dropdown layout tests and locator failures are preserved in `../evidence/` with passing reruns.

The Web release build and local HTTP fixture do not establish internet availability, identity security, mobile compatibility, or production deployment readiness. Browser-level error-response injection tests are explicitly labeled UI-only; backend outage/rollback claims use actual backend evidence.

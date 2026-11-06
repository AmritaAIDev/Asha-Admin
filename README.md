# Asha Admin

Admin console for Asha Phase 1. Staff use it to set up organizations (colleges), their counselors
and High-risk contacts, choose alert channels, send test alerts, activate an organization, and
watch the delivery log.

It is a Flutter web app, separate from `Asha_Frontend`, and talks to the same Django backend
(`Asha_Backend`).

> **The backend for this does not exist yet.** See [`docs/BACKEND_CHANGES.md`](docs/BACKEND_CHANGES.md)
> for every model, endpoint and rule the backend needs. Until those exist, run the console with
> sample data (`USE_MOCK=true`).

## Run it

Needs the same Flutter as Asha_Frontend (Dart ≥ 3.11.1).

```bash
cd D:\work\Asha_Admin
flutter create . --platforms=web --project-name asha_admin   # first time only: adds Flutter's web runner files; keeps existing files
flutter pub get

# Sample data, no backend needed
flutter run -d chrome --web-port 6003 --dart-define=USE_MOCK=true

# Against local Django (docker compose up in Asha_Backend)
flutter run -d chrome --web-port 6003 --dart-define=API_BASE_URL=http://localhost:8000

# Production build
flutter build web --release --dart-define=API_BASE_URL=https://asha-be.amritaai.org
```

Running `flutter create .` once is safe: it only adds files that are missing and doesn't overwrite
`lib/`, `web/index.html` or `pubspec.yaml`.

**Sample data sign-in:** any username, password `demo1234`. Username `student` shows the
"no console access" error. Five wrong passwords lock sign-in for 15 minutes. Simulated delivery: a
number ending in **0** fails on WhatsApp ("number not on WhatsApp"), and one ending in **00** also
fails on SMS. Reloading the page resets everything.

**Against the real backend:** sign in with an account that has `is_staff = True`
(`python manage.py createsuperuser` in Asha_Backend). The backend must return `is_staff` from
`GET /api/auth/me/` and allow the console's origin in `CORS_ALLOWED_ORIGINS` (items A1 and A5 in
the backend changes doc).

## Screens (storyboard frames)

| Route | Screen | Frame |
|---|---|---|
| `/login` | Admin login (staff only, lockout message, idle sign-out) | A1 |
| `/organizations` | Organizations list, search, status filter | A2 |
| `/organizations/new` | Step 1 · Details (creates a Draft) | A3 |
| `/organizations/:id/contacts` | Step 2 · Contacts, "Receives High-risk alerts" | A4 |
| `/organizations/:id/counselors` | Step 3 · Counselors, primary/backup, consent check | A5 |
| `/counselors/new?assignTo=:id` | Side path · Add counselor, then back to step 3 | A6 |
| `/organizations/:id/alerts` | Step 4 · Alert channels + message preview | A7 |
| `/organizations/:id/review` | Step 5 · Review, test alerts, activate | A8 |
| `/organizations/:id` | Active organization: Overview / Details / Contacts / Counselors / Alert channels / Log tabs | A9 |
| `/log` | Delivery log, red banner for failed High alerts, Resend | A10, A11 |
| `/counselors`, `/counselors/:id` | Counselors list and detail; deactivation blocked for an only primary | A12 |

A **Draft** organization always opens in the 5-step setup, on the step after the last one saved.
An **Active** or **Inactive** organization opens on tabs; the same forms are used, with a
"Save changes" button.

## Code layout

```
lib/
  main.dart                    picks HttpConsoleApi or MockConsoleApi, restores the session
  app/                         config (dart-defines), session + 30-min idle timer, router, scope
  api/
    console_api.dart           the interface: every call the console makes
    http_console_api.dart      Django client (JWT, single-flight refresh like Asha_Frontend)
    mock_console_api.dart      in-memory backend that enforces the same rules (executable spec)
    token_store.dart           tokens in shared_preferences under asha_console_* keys
  models/                      Organization, OrgContact, Counselor, LogRow, TestRun … (JSON)
  utils/validators.dart        phone, code, email rules (mirror the backend)
  screens/                     login, organizations, org/ (steps + tabs), counselors/, delivery log
  widgets/                     shell (sidebar), tables, chips, banners, log table
docs/BACKEND_CHANGES.md        what the backend has to add (nothing changed there yet)
tool/check_logic.dart          plain-Dart checks for validators, models and mock rules
```

`api/`, `models/` and `utils/` have no Flutter imports, so they can be checked with plain Dart:

```bash
dart run tool/check_logic.dart      # after flutter pub get
```

## Notes

* Console tokens use their own storage keys, so a staff member's student session in the same
  browser is never mixed with the console session.
* The console never shows message text. The delivery log shows only the `ASH-XXXX` reference.
* Fonts (Playfair Display, Roboto) are bundled under `assets/fonts` (SIL Open Font License), so
  nothing is downloaded at runtime.

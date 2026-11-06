# Asha Admin: backend changes needed

Checked against `D:\work\Asha_Backend` on 4 Nov 2026. **No backend code has been changed.**
Sources: *Asha Phase 1 — Implementation Plan* (doc) and *Asha Alerts Storyboard* (console designs A1–A12).

**Summary.** None of the admin-console backend exists yet. There is no `organizations` app, no
`/api/console/` route, no Celery app, no risk events and no SMS/WhatsApp code. Login, token refresh,
the error format, Redis and the `is_staff` flag already exist and are reused. Asha_Admin can run
today against an in-memory mock (`USE_MOCK=true`) that enforces every rule below, so UI work does
not have to wait for the backend.

Tags used below:

* **[Console]**: the console can't work against the real backend without it
* **[Alerts]**: needed before real alerts are sent
* **[Students]**: student-side linking (Asha_Frontend + backend)
* **[Security]**: must be fixed before the console goes live

---

## 0. Decide first: where the plan and the storyboard disagree

The console follows the **storyboard**, because it is the UI spec and it is more detailed. Each row
below changes the data model, so it needs a yes or no before backend work starts.

| # | Topic | Implementation Plan says | Storyboard says (console built to this) | Who decides |
|---|---|---|---|---|
| D1 | Data model | One `Person` per organization with role `counsellor` or `manager` | **Counselor** is a shared record that can serve several organizations as **primary** or **backup**. **Contacts** (principal, dean …) belong to one organization and have a "Receives High-risk alerts" tick | Product |
| D2 | Who gets **Medium** | Every active counsellor at once | The **primary** counselor only; the first active **backup** if the primary is inactive (AC 2.1) | Product + clinical |
| D3 | Who gets **High** | All counsellors + all managers | Medium's recipients + every contact ticked "Receives High-risk alerts" (AC 3.1) | Product + clinical |
| D4 | Organization status | `active` / `inactive`, default inactive | `draft` / `active` / `inactive`. Saving step 1 creates a Draft (AC 1.2) | Product |
| D5 | Channels | Fixed: SMS always, WhatsApp if the person has a number | Set **per organization, per level**: SMS, WhatsApp or both; at least one (AC 1.8) | Product |
| D6 | Activate rule | ≥1 active counsellor and ≥1 active manager | ≥1 High-risk contact, a primary counselor, channels set, **and** a test that reached every recipient on ≥1 channel (AC 1.5, 1.9) | Product |
| D7 | Where the console lives | New routes inside Asha_Frontend | Separate app, `D:\work\Asha_Admin` (as you asked). Needs its own hosting origin and CORS entry (see A5) | Eng |
| D8 | SMS content | If DLT caps variables at ~30 chars, SMS carries name/org/ref/time only; messages on WhatsApp | One long multi-part SMS with the 5 messages (AC 2.3) | Product, after SMS provider confirms DLT limits |
| D9 | Counselor fields | name, title, mobile, WhatsApp, email | Also **languages spoken** and **notes** | Product |

If D1–D3 go the plan's way instead, the console's Counselors step and the overview cards need
rework. The other screens stay the same.

---

## 1. Already in the backend and reused as-is

| What | Where | Used for |
|---|---|---|
| Login by username **or** email | `POST /api/auth/login/` (`accounts/views.py`) | Console sign-in |
| Refresh-token families, rotation, grace window | `POST /api/auth/token/refresh/`, `accounts/token_family.py` | Staying signed in; console uses the same single-flight refresh as Asha_Frontend |
| Logout (revokes this device's family) | `POST /api/auth/logout/` | Log out, idle sign-out |
| `User.is_staff` | `accounts/models.py` | Gate for the console (but see A1) |
| Error shape `{"detail","code","errors"?}` | `Asha_Django/api_errors.py` | Console reads `code`, `detail` and `errors` |
| DRF page-number pagination | `REST_FRAMEWORK` in settings (`PAGE_SIZE` 50) | Lists (`count`, `next`, `results`) |
| `celery>=5.4` in requirements, Redis service | `requirements.txt`, `docker-compose.yml` | Alert worker (no Celery app yet) |
| `X-Internal-Api-Key` auth | `internal_api/authentication.py` | New `/api/internal/risk-events/` |
| `ChatSession`, `Message` | `sessions_app/models.py` | RiskEvent FKs, last-5-messages builder |
| `UserProfile.college` (free text), `mental_health_consent` | `profiles/models.py` | Mapping existing students; consent text update |
| FastAPI side-effects hook and Django client | `Asha_Backend/services/phase_side_effects.py`, `services/django_client.py` | Where `post_risk_event` goes |

---

## 2. Auth and security

| # | Change | Why | Tag |
|---|---|---|---|
| A1 | Add **`is_staff`** to `UserSerializer` (`GET /api/auth/me/`) **as a read-only field** | `/me/` doesn't return it today, so the console can't tell staff from students. It has to be in `read_only_fields`, otherwise `PATCH /api/auth/me/` would let any student make themselves staff | [Console] [Security] |
| A2 | **`IsConsoleAdmin`** permission (`is_authenticated and is_staff and is_active`) on every `/api/console/` route; 403 for everyone else | AC 1.1 | [Console] |
| A3 | **`POST /api/auth/password/change/` lets anyone set any account's password from just a username or email, with no old password, OTP or token, and returns a signed-in token pair.** Once staff accounts can see student names and phone numbers, this is a direct way in for anyone | Fix before go-live. At minimum refuse it for `is_staff` accounts; better, require the old password or an authenticated session | [Security] |
| A4 | **Login lockout**: 5 wrong passwords → sign-in paused 15 minutes (per username, ideally per username + IP). Return `429` with code `login_locked`, `detail` and `retry_after` (seconds). Add `login_locked` to `accounts/auth_errors.py` | AC 1.1. No throttling exists today (`DEFAULT_THROTTLE_*` not set) | [Console] [Security] |
| A5 | **CORS**: add the console's origin(s) to `CORS_ALLOWED_ORIGINS`, e.g. `http://localhost:6003` (dev) and the production console URL | Asha_Admin is a separate web app (D7). `CORS_ALLOW_ALL_ORIGINS` is only on in DEBUG | [Console] |
| A6 | **Device limit**: `AUTH_MAX_ACTIVE_SESSIONS=2` is per user. A staff member signed in to the student app on phone and laptop gets one of those signed out when they open the console | Decide: higher limit for staff, or console sessions don't count. The console signs out right away if a non-staff account signs in, so students never lose a device slot | [Console] |
| A7 | **Audit log**: the login screen (A1 design) says "Activity in this console is logged". Nothing logs it today. Add a `ConsoleAuditLog` (actor, action, object type/id, changes JSON, IP, time) written by the console views, or drop that sentence from the design | Accountability for who changed which phone number | [Console] |
| A8 | Forgot password for staff: `POST /api/auth/password/forgot/` only writes the token to the log (email is a stub). The console currently says "Ask an Asha super-admin to reset your password" | Later | — |
| A9 | Recommended: shorter access-token lifetime for staff (today 1 h; the console signs out after 30 min idle on the client side only) | Defence in depth | [Security] |

---

## 3. Data model: new Django app `organizations`

All additive migrations: `organizations/0001_initial`, `profiles/00NN_userprofile_organization`.
Register every model in Django admin too.

### Organization (`organizations`)

| Field | Type | Rules |
|---|---|---|
| id | UUID PK | |
| name | CharField(120) | 2–120 chars |
| code | CharField(12) unique | `^[A-Z0-9-]{3,12}$` after uppercasing; saved uppercase |
| type | choices `college, school, ngo, other` | |
| city, state | CharField(80) | required |
| notes | TextField blank | *new vs plan* |
| status | choices **`draft`**, `active`, `inactive` | default **draft** (D4) |
| setup_step | SmallInt 1–5 | highest setup step saved, so a Draft reopens on the next step. *new* |
| medium_sms, medium_whatsapp, high_sms, high_whatsapp | Boolean, default true | at least one per level (D5). Exposed as `channels` |
| created_by | FK User SET_NULL | |
| created_at, updated_at, activated_at | DateTime | |

### Counselor (`counselors`): shared across organizations (D1)

| Field | Type | Rules |
|---|---|---|
| id | UUID PK | |
| full_name | CharField(120) | required |
| mobile | CharField(13) **unique** | 10 digits starting 6–9, saved `+91XXXXXXXXXX` |
| whatsapp | CharField(13) null | null = no WhatsApp |
| email | EmailField blank | |
| languages | JSONField (list of names) | *new* (D9) |
| notes | TextField blank | *new* |
| consent_at | DateTime null | set by the server when the admin ticks consent; **required before any assignment** (AC 1.7) |
| consent_recorded_by | FK User SET_NULL | |
| is_active | Boolean default true | |
| created_at, updated_at | DateTime | |

### OrgCounselor (`organization_counselors`)

| Field | Type | Rules |
|---|---|---|
| organization | FK Organization CASCADE | |
| counselor | FK Counselor PROTECT | |
| role | choices `primary`, `backup` | |

Constraints: `unique(organization, counselor)`;
`UniqueConstraint(fields=["organization"], condition=Q(role="primary"), name="one_primary_per_org")`.

### OrgContact (`organization_contacts`)

| Field | Type | Rules |
|---|---|---|
| id | UUID PK | |
| organization | FK Organization CASCADE | |
| full_name | CharField(120) | required |
| title | CharField(80) | their role there, e.g. Principal; required |
| mobile | CharField(13) | as above |
| whatsapp | CharField(13) null | |
| email | EmailField blank | |
| receives_high_alerts | Boolean default false | |
| is_active | Boolean default true | a removed contact is deactivated, not deleted, so old log rows keep the name |

Constraint: `unique(organization, mobile)` where `is_active`.

### RiskEvent (`risk_events`)

As in the plan (user, session, message, level, safety_state, organization snapshot, outcome,
created_at), with **`skipped_draft`** added to `outcome`
(`sent, low_recorded, skipped_no_org, skipped_draft, skipped_inactive, skipped_repeat`).

### AlertDelivery (`alert_deliveries`)

As in the plan, plus the following changes:

* Replace `person` with **`counselor`** FK (null) + **`contact`** FK (null) + `recipient_role` snapshot (`primary`, `backup`, `contact`) and `recipient_name` snapshot
* **`organization`** FK (null): test rows have no RiskEvent but belong to an organization
* **`test_run_id`** UUID (null): groups the rows of one "Send test alerts" click
* **`next_retry_at`** DateTime (null): the log shows "Retrying · next in 5 min"
* **`resent_from`** FK self (null): the new row created by Resend points at the failed one; the failed row is then "resolved" for the red banner (AC 4.1)
* `error`: short readable reason (e.g. `number not on WhatsApp`), not raw provider JSON

### UserProfile

Add `organization = FK(Organization, null=True, blank=True, on_delete=SET_NULL)` and
`consent_version = CharField(20, blank=True)` ([Students]).

---

## 4. Console API: what Asha_Admin calls

All routes are under `/api/console/`, use the existing JWT auth plus `IsConsoleAdmin`, use DRF
pagination (`?page=`, 20 per page suggested), and return errors in the existing shape. The full
client is `lib/api/http_console_api.dart`, and the JSON is parsed in `lib/models/*.dart`.
**`lib/api/mock_console_api.dart` implements every rule below and is the executable spec.**

### Organizations

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `organizations/` | `search` (name or code), `status`, `page` | page of Organization | |
| POST | `organizations/` | `name, code, type, city, state, notes` | Organization (status `draft`) | 400 `validation_error`, `errors.code = ["NCC-01 is already used by North Campus College."]` |
| GET | `organizations/{id}/` | | Organization | 404 |
| PATCH | `organizations/{id}/` | any of the create fields, `channels`, `setup_step` | Organization | 400 (`errors.medium` / `errors.high` when a level has no channel) |
| GET | `organizations/{id}/contacts/` | | `[OrgContact]` (active only) | |
| PUT | `organizations/{id}/contacts/` | `[OrgContact]`, existing ones with `id`; missing ones are deactivated | `[OrgContact]` | 400 with field keys **`contacts.{index}.{field}`** (e.g. `contacts.1.mobile`); 409 `high_risk_contact_required` if an Active org would be left with none |
| GET | `organizations/{id}/counselors/` | | `[{counselor: Counselor, role}]` | |
| PUT | `organizations/{id}/counselors/` | `[{counselor_id, role}]` (replaces the set) | same as GET | 400 `consent_missing`, `counselor_inactive`, `one_primary`; 409 `primary_required` (Active org without a primary) |
| GET | `organizations/{id}/readiness/` | | Readiness | |
| POST | `organizations/{id}/test-alerts/` | | TestRun | 400 `no_recipients` |
| GET | `organizations/{id}/test-alerts/latest/` | | TestRun | 404 if never run |
| POST | `organizations/{id}/activate/` | | Organization | **422 `not_ready`** with `missing: [...]` |
| POST | `organizations/{id}/deactivate/` | | Organization | always allowed |

### Counselors

| Method | Path | Body / query | Returns | Errors |
|---|---|---|---|---|
| GET | `counselors/` | `search` (name or mobile), `is_active`, `page` | page of Counselor (with `assignments`) | |
| POST | `counselors/` | `full_name, mobile, whatsapp, email, languages, notes, consent: true` | Counselor | 400 `errors.consent` if not true; `errors.mobile` if the mobile is already used |
| GET | `counselors/{id}/` | | Counselor | |
| PATCH | `counselors/{id}/` | same fields; `is_active` to (de)activate; `consent: true` stamps `consent_at` if missing | Counselor | **409 `only_primary`** with `organizations: [ids]` when deactivating the only primary of an Active org (AC 4.4) |
| POST | `counselors/{id}/test-alert/` | | TestRun (one recipient) | |

### Delivery log

| Method | Path | Body / query | Returns | Notes |
|---|---|---|---|---|
| GET | `alerts/` | `organization`, `level` (`low, medium, high, test`), `status` (`delivered, failed, retrying, skipped`), `from` (ISO time), `needs_attention=true`, `page` | page of LogRow, newest first | **One row per risk event per recipient** (its channels nested). An event with no deliveries (skipped, low) is one row with `recipient: null`. **Never returns message text** |
| GET | `alerts/summary/` | | `{"needs_attention": 1}` | Count for the red banner |
| POST | `alerts/{delivery_id}/resend/` | | 201 | Only `failed` deliveries. Creates a **new** delivery to the number on file **now**; the old row keeps the old number (AC 4.2) |

### JSON shapes (generated from the console's own models)

Organization:

```json
{
  "id": "…", "name": "North Campus College", "code": "NCC-01", "type": "college",
  "city": "Kochi", "state": "Kerala", "notes": "", "status": "active",
  "channels": {"medium": {"sms": true, "whatsapp": true}, "high": {"sms": true, "whatsapp": true}},
  "primary_counselor": {"id": "…", "full_name": "Anjali Menon", "mobile": "+919847012345"},
  "backup_counselors": [{"id": "…", "full_name": "Joseph Varghese", "mobile": "+919847154321"}],
  "high_risk_contacts": [{"id": "…", "full_name": "Dr. Thomas Kurian", "mobile": "+919847066778"}],
  "counselor_count": 2, "contact_count": 2, "setup_step": 5,
  "created_at": "2026-09-05T04:30:00Z", "activated_at": "2026-09-20T04:30:00Z"
}
```

OrgContact:

```json
{"id": "…", "full_name": "Dr. Kavya Rao", "title": "Principal", "mobile": "+919845067890",
 "whatsapp": "+919845067890", "email": "", "receives_high_alerts": true}
```

Counselor (`is_only_primary` is true when this counselor is the organization's primary):

```json
{
  "id": "…", "full_name": "Anjali Menon", "mobile": "+919847012345", "whatsapp": "+919847012345",
  "email": "", "languages": ["Malayalam", "English"], "notes": "",
  "consent_at": "2026-10-05T04:30:00Z", "is_active": true,
  "assignments": [{"organization": {"id": "…", "name": "North Campus College", "status": "active"},
                   "role": "primary", "is_only_primary": true}],
  "last_test": {"at": "2026-11-04T04:30:00Z", "sms": "delivered", "whatsapp": "delivered"}
}
```

Readiness (`missing` codes: `details`, `high_risk_contact`, `primary_counselor`, `channels`, `test_alerts`):

```json
{"details_complete": true, "code": "CNI-BLR", "high_risk_contact_count": 1,
 "primary_counselor_name": "Rahul Iyer", "channels_set": true,
 "test_run": true, "tests_all_reached": true, "missing": []}
```

TestRun (status: `queued, sent, delivered, retrying, failed`; `whatsapp: null` = no WhatsApp number):

```json
{
  "run_at": "2026-11-04T04:30:00Z",
  "recipients": [
    {"name": "Rahul Iyer", "role_label": "Primary counselor", "phone": "+919886013579",
     "sms": {"status": "delivered", "error": null, "delivery_id": "…"},
     "whatsapp": {"status": "delivered", "error": null, "delivery_id": "…"}},
    {"name": "Dr. Kavya Rao", "role_label": "Principal · High-risk contact", "phone": "+919845067890",
     "sms": {"status": "delivered", "error": null, "delivery_id": "…"},
     "whatsapp": {"status": "failed", "error": "number not on WhatsApp", "delivery_id": "…"}}
  ]
}
```

LogRow (`outcome`: `sent, test, low_recorded, skipped_draft, skipped_inactive, skipped_no_org, skipped_repeat`;
`recipient.label`: `primary`, `backup` or `contact`):

```json
[
  {"id": "…", "time": "2026-11-03T20:30:00Z", "level": "high", "outcome": "sent",
   "organization": {"id": "…", "name": "Riverside Arts College"}, "student_ref": "ASH-7H3D",
   "recipient": {"name": "Dean of Students", "label": "contact"},
   "channels": [
     {"delivery_id": "…", "channel": "sms", "status": "failed", "attempts": 4,
      "error": "number unreachable", "next_retry_at": null, "phone": "+919443022110"},
     {"delivery_id": "…", "channel": "whatsapp", "status": "failed", "attempts": 4,
      "error": "number not on WhatsApp", "next_retry_at": null, "phone": "+919443022110"}],
   "resolved": false},
  {"id": "…", "time": "2026-11-03T02:30:00Z", "level": "medium", "outcome": "skipped_no_org",
   "organization": null, "student_ref": "ASH-5T1Z", "recipient": null, "channels": [], "resolved": false}
]
```

---

## 5. Rules the API must enforce

The console checks these too, but the server is the source of truth.

1. **Code**: trim and uppercase, then `^[A-Z0-9-]{3,12}$`; unique; the duplicate message names the other organization.
2. **Phone numbers**: strip spaces, dashes and a leading `+91`, `91` or `0`; then `^[6-9]\d{9}$`; save as `+91XXXXXXXXXX`. `whatsapp: null` means no WhatsApp.
3. **Email**: optional; validated if given.
4. **Create = Draft.** Draft and Inactive organizations never send alerts (events are recorded as `skipped_draft` / `skipped_inactive`).
5. **Consent**: a counselor cannot be created without `consent: true`, and one without `consent_at` cannot be assigned. The server sets `consent_at` to the time of the request.
6. **Exactly one primary** per organization (DB constraint). Backups are optional. A counselor can serve several organizations.
7. **Active organizations keep their safety net**: they can't be left without a primary (409 `primary_required`) or without a High-risk contact (409 `high_risk_contact_required`), and their only primary can't be deactivated (409 `only_primary`).
8. **Channels**: at least one per level.
9. **Test recipients** = active primary + active backups + active contacts with `receives_high_alerts`. Test messages say **TEST**, use fixed sample lines and never contain student messages.
10. **Readiness / activate**: details complete, ≥1 High-risk contact, a primary, channels valid, **and the latest test reached every current recipient on at least one channel**. A test counts only if no recipient or number changed after it was sent (keep a fingerprint of recipients and numbers on the test run, or compare `updated_at`).
11. **One channel is enough**: a recipient counts as reached if SMS *or* WhatsApp was delivered (AC 3.3).
12. **Resend**: only failed deliveries; new row to the current number; set `resent_from`; once the new row is delivered, the old row no longer counts toward the red banner.
13. **Log privacy**: `alerts/` never returns message text or the student's name; only the `ASH-XXXX` reference.

---

## 6. Alert pipeline [Alerts]

Mostly as in the plan. Changes are in **bold**.

| # | Change | Where |
|---|---|---|
| P1 | Hidden `report_safety_state` tool on every chat path (text, speech batch, streaming); fire-and-forget `post_risk_event` | `Asha_Backend/services/openai_llm.py`, `phase_side_effects.py`, `django_client.py`, `routers/speech.py`, `routers/stt_ws.py` |
| P2 | `POST /api/internal/risk-events/` (X-Internal-Api-Key): save RiskEvent, queue the job, answer in under 100 ms | `internal_api/urls.py` + view |
| P3 | Celery app `Asha_Django/celery.py` (+ import in `Asha_Django/__init__.py`), `CELERY_BROKER_URL=redis://redis:6379/1`, `CELERY_TASK_ACKS_LATE=True`, route `organizations.alerts.*` to queue `alerts` | settings |
| P4 | `worker` service in `docker-compose.yml`, `.prod.yml`, `.tunnel.yml` | compose files |
| P5 | `process_risk_event`: S2/S3/S3.1 → low; S3.2 → medium; S4 → high. Skips: no org, **Draft**, Inactive, repeat (same or higher level `sent` in the same session within 6 h; Medium → High always sends) | `organizations/alerts/tasks.py` |
| P6 | **Recipients per D2/D3**: Medium → primary (or first active backup if the primary is inactive); High → that + every active High-risk contact | same |
| P7 | **Channels from the organization's settings** (D5), skipping WhatsApp when the recipient has no number | same |
| P8 | `send_delivery` with retries at 60, 300 and 900 s, then `failed`; **set `next_retry_at`** before each retry | same |
| P9 | Message builder: preferred_name or username, ref `ASH-` + first 4 of the event id, last 5 messages oldest first, 120 chars each; first line generic ("Asha MEDIUM alert — {org}") because it shows on lock screens | `organizations/alerts/message.py` |
| P10 | Providers: one interface, MSG91/Gupshup SMS and Meta WhatsApp Cloud API, plus a `console` provider that only logs, for dev | `organizations/alerts/providers.py` |
| P11 | Webhooks `/api/webhooks/sms/` and `/api/webhooks/whatsapp/` (signature-checked) move `sent` to `delivered` or `failed`. **The console polls test results for 2 minutes, so webhooks must be live for test alerts to show Delivered** | new urls |
| P12 | Backup check: reply contains the 112 / nearest-hospital wording but no tool call → log a warning and post S4 | FastAPI |
| P13 | Prompt edits from the plan (section 3.1 escalation sentence, tool instructions) | `services/asha_system_prompt_revised.py` |
| P14 | Env vars from the plan: `ALERTS_ENABLED`, `ALERT_PILOT_ORG_CODES`, `ALERT_REPEAT_WINDOW_HOURS`, `ALERT_MESSAGE_MAX_CHARS`, `SMS_*`, `WHATSAPP_*`, `ALERT_WEBHOOK_SECRET` | `.env` |

Start provider approvals (DLT entity, sender ID, templates; WhatsApp business verification and
templates) on day one. They have the longest lead time.

---

## 7. Student linking [Students]

1. `RegisterSerializer`: optional `organization_code`; uppercase it and look it up; unknown → 400 "We couldn't find that college code"; a match sets `profile.organization`.
2. `PATCH /api/users/profile/` accepts `organization_code`; `UserProfileSerializer` returns `organization` (id, name, code).
3. Asha_Frontend: "College code" field on `screens/register_screen.dart` and `website/widgets/get_started_auth_card.dart`, and on the Profile screen.
4. Consent wording that covers alerts, plus `consent_version` (needs clinical and legal sign-off, DPDP Act, students under 18).
5. Management command `link_students_by_college`: lists distinct free-text `college` values to map by hand; changes nothing without `--confirm`.

---

## 8. Deployment and docs

* Host Asha_Admin (`flutter build web`) on its own origin or path, e.g. `console.asha-be.amritaai.org` or `/console/` behind the same nginx/Caddy. Add that origin to CORS (A5). If it is served under `/console/`, build with `--base-href /console/`.
* Update `docs/API_ENDPOINTS.md` and `docs/CODEBASE_STRUCTURE_AND_API_GUIDE.md` with `/api/console/*`, `/api/internal/risk-events/` and the webhooks.
* Add `organizations` to `INSTALLED_APPS` and a "Console" tag to `SPECTACULAR_SETTINGS`.

---

## 9. Suggested backend order (to unblock the console first)

| Step | Work | Unblocks |
|---|---|---|
| B1 | A1 `is_staff` on `/me/` (read-only), A2 permission, A5 CORS, A3 password-change fix, A4 lockout | Real sign-in in the console |
| B2 | Models and migrations (section 3) + Django admin | everything below |
| B3 | Organizations, contacts, counselors, channels endpoints + rules 1–8 | Steps 1–4, counselor screens |
| B4 | Readiness, test alerts with the `console` provider, activate/deactivate | Step 5, Overview |
| B5 | `alerts/`, `alerts/summary/`, resend | Delivery log |
| B6 | Alert pipeline (section 6), then real providers and webhooks | Real alerts |
| B7 | Student linking (section 7) | Students land in organizations |

Until B1–B5 exist, run the console with `--dart-define=USE_MOCK=true`.

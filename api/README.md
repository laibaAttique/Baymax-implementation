# Baymax API

The Express server behind the **specialist portal** (`../baymax-portal`) and the **admin panel** (`../baymax-admin`). Neither web app reads the database: they send a Firebase ID token to this API, which checks it, checks the person's role and ownership, and uses the Firebase Admin SDK. Port **4000**. It is separate from the mobile app and from both web apps (own folder, own packages).

```
Baymax app ─────────────────────┐
Specialist portal ─┐            ├──► Firebase project baymax-148da (Auth + Realtime Database)
Admin panel ───────┴─► this API ┘
```

## Routes

| Area | Routes | Who |
|---|---|---|
| Who am I | `GET /api/me` | any signed-in person (a non-specialist is told to register) |
| Registration | `POST /api/applications`, `DELETE /api/applications` (withdraw) | a signed-in person who is not yet a specialist |
| Specialist | `/api/dashboard`, `/api/appointments…` (accept, decline, notes, status), `/api/patients…` (record, plans, food-log reviews), `/api/prescriptions`, `/api/exercises`, `/api/summary`, `PUT /api/me/profile`, `DELETE /api/me` | doctor, nutritionist, trainer (role-checked; some actions are role-specific) |
| Payments (Module 15 on the web) | `GET /api/payments` (the specialist's own: earned, upcoming, waiting, refunded, with totals) | doctor, nutritionist, trainer |
| Video room | `GET /api/appointments/:id/call` (room name only inside the join window), `POST …/call/event` (`joined` / `left`) | the appointment's specialist |
| Client messages | `GET /api/chats`, `GET /api/chats/:id` (opens and marks read; `?since=` for polling), `POST /api/chats/:id` | the appointment's specialist (the patient's phone writes its own messages straight to the database; the rules check them) |
| Admin | `/api/admin/overview` (now with payment, call and message figures), `/api/admin/applications…`, `/api/admin/specialists`, `GET /api/admin/payments`, `POST /api/admin/payments/:id/refund` | `admin` only |

A request with no valid token gets 401; the wrong role gets 403; someone else's appointment or patient gets 404.

**Input checks on every route** (`src/lib/validate.js`): ids in addresses must look like Firebase keys (400 otherwise, before the database is touched); query values (status, dates, search) must make sense (a bad one is a 400, not silently ignored); a body must be a JSON object sent as `application/json` (415 otherwise); one signed-in person is limited to 120 writes a minute, and chat to 20 messages a minute per conversation (429).

**Money.** Declining or cancelling a paid appointment, closing a specialist account, or a request nobody answered before its start time records a `refund` on the appointment (a test payment is returned at once; a live one is marked `manual` for the administrator, because this server holds no gateway keys). A patient who cancels is refunded by the administrator in the admin panel. The `payment` record itself is never rewritten.

## How a consultation works

1. A member books in the app, pays (test mode), and the booking becomes a **request**.
2. The specialist **accepts** or **declines** it. Accepting makes an unguessable video link here on the server (`MEETING_BASE_URL`), so a phone never creates or writes the link.
3. Declining frees the time. A request nobody answers before its start time expires.

## Data layout (shared with the app; rules are `app/database.rules.json`)

| Path | Written by | Notes |
|---|---|---|
| `roles/{uid}` | this API / scripts only | `doctor`, `nutritionist`, `trainer`, `admin` |
| `specialists/{uid}` | this API only | public profile the app lists (`verified` once approved) |
| `applications/{uid}` | this API only | a registration with its licence number; closed to every client |
| `appointments/{id}` | member (create, pay, cancel); this API (accept, decline, status, notes, `meetingLink`) | `payment` is the transaction (never card details) |
| `slots/{specialistId}/{startMs}` | member (hold/cancel); this API (cancel) | creating the key is the booking, so two people cannot book one time |
| `specialistPlans/{uid}/diet|workout`, `dietReviews/{uid}/{date}` | this API only | plans and food-log verdicts; the member can read, never write |
| `users/{uid}/…` | the member; this API for inbox notifications | `planChoice` is the member's choice between a specialist's plan and Baymax's |
| `accessLog/{appointmentId}/…` | this API | who opened shared data, and when |
| `chats/{appointmentId}/{key}`, `chatRead/{appointmentId}/{uid}` | the patient's phone (own messages only); this API (the specialist's) | plain text, 1 to 1000 characters; writing closes 24 hours after the slot; the two people in the appointment can read |
| `callLog/{appointmentId}/…`, `paymentLog/{appointmentId}/…` | this API | joins and leaves of the video room; refunds an administrator recorded. Closed to every client |
| `appointments/{id}/refund` | this API | `refunded` or `manual`, amount, who, why |

## Set up

1. `npm install`
2. **Service account**: Firebase console → Project settings → Service accounts → *Generate new private key*. Save it **outside** every project folder (for example `~/keys/`). `cp .env.example .env` and set `GOOGLE_APPLICATION_CREDENTIALS` to its path. `PORTAL_ORIGIN` must list both web apps: `http://localhost:3000,http://localhost:3001`.
3. **Database rules** (from the app folder): `firebase deploy --only database --project baymax-148da`.
4. **Create the administrator login, once.** This generates a password and saves the login in `../baymax-admin/.env.admin` (private, not printed, not in git):
   ```bash
   node scripts/create-admin.js --email you@example.com
   ```
   (An account that already exists keeps its password unless you add `--reset-password`; or run `node scripts/make-admin.js --email ...` to make an existing account an administrator and keep its password.)
5. `npm start`. Check http://localhost:4000/health.

Other scripts: `node scripts/create-specialist.js --email … --name … --type doctor|nutritionist|trainer --specialty … --video-fee … --chat-fee …` (add `--dry-run` to preview).

## Tests

* `npm test`: the API against an in-memory database (roles, ownership, consent windows, plans, reviews, account closing, validation).
* `e2e/`: the real rules, this API and the whole flow on the **local Firebase emulators** (no real project touched); see `e2e/README.md`.

## Known limits

* **Video** is a Jitsi Meet room (`MEETING_BASE_URL`, default `https://meet.jit.si`), now opened inside the portal (`/appointments/:id/call`) with a device check, a join log and notes beside the call. The public server may ask the first person in a room to sign in; host your own for real use. No own signalling or TURN servers; the call itself is not recorded. The embed script is only loaded from the servers listed in the portal's `NEXT_PUBLIC_JITSI_DOMAINS` (default `meet.jit.si`); this was checked against the API and in the browser only as far as the pre-join screen, because the Jitsi service itself needs internet and a camera.
* **Payment** is a test gateway (published test cards only). The scope's JazzCash needs merchant credentials and a server holding the secret key; going live means writing that server, letting only it write `payment`, and removing the client write rules for it.
* No push notifications to specialists (FCM; the portal polls every 30 seconds and can show a desktop alert), no patient reviews/ratings, no chat attachments, no typing indicators, and no risk/posture/emotion panels (they need AI-engine data that does not exist yet). Chat is polled every 4 seconds while a conversation is open, not pushed.
* The new `chats` and `chatRead` rules are in `app/database.rules.json` and pass on the emulator, but **have not been deployed** to `baymax-148da`: deploy them (with the owner's OK) before the app's Messages screen can work against the real project.
* A specialist's diet plan replaces the calorie target and macros but the meal suggestions stay as Baymax built them for its own target, and the app says so.
* Join call stays open from 5 minutes before the start until the slot ends; shared data stays open 60 minutes after the slot. Both are constants in `src/lib/rules.js`.

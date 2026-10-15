# Baymax Specialist Portal (Module 14)

A web portal for Baymax **doctors, nutritionists and trainers** to see and run the consultations that members book in the mobile app.

| Folder | What it is |
|---|---|
| `server/` | Express API. The only thing that talks to the database for the portal (Firebase Admin SDK). |
| `web/` | Next.js (App Router, TypeScript) front end. Signs in with Firebase, then calls only `server/`. |

It is **separate from the mobile app** (`Baymax-implementation` / `app/`): its own folder, its own packages, its own server and its own
deployment. The only thing they share is the Firebase project `baymax-148da` (same sign-in accounts, same Realtime Database).

```
Baymax app ──────────────┐
                         ├──► Firebase project baymax-148da  (Auth + Realtime Database)
Next.js portal ► Express ┘
```

## What it does

* **Sign in** with a Firebase account that an administrator made a specialist (`roles/{uid}` = doctor / nutritionist / trainer).
* **Overview**: greeting by the specialist's own clock, four cards (consultations today, upcoming 7 days, patients, awaiting notes), and
  *Today's consultations*: live sessions first with **Join call**, upcoming ones with **Prepare** (from 30 minutes before), finished ones greyed out. Refreshes every 30 seconds.
* **Appointments**: every booking, filterable by patient name, status and date range.
* **Appointment page**: the patient's note, the meeting link, and the data the patient agreed to share (health summary, 7-day diet log,
  30-day workouts). Nothing is shown unless the patient ticked it, and only from 30 minutes before to 60 minutes after the slot.
  Every time shared data is opened it is logged in `accessLog/{appointmentId}`.
* **Notes and prescriptions**: saved to the appointment; the patient sees them in the app and gets a notification. Prescriptions are doctors only (FR-6).
* **Complete / missed / cancel**: cancelling frees the time for other members and tells the patient.
* **My profile**: specialty, bio, fees (video and chat), working days and hours, "taking bookings", "urgent bookings". The app's specialist list updates straight away.

## How the pieces are kept apart

* The browser never reads the database. It gets an ID token from Firebase Auth and sends it to the Express API as `Authorization: Bearer …`.
* The API verifies the token, reads the person's role from `roles/{uid}` and refuses anyone who is not a specialist with **403**, even by direct URL.
  A specialist only ever sees appointments whose `specialistId` is their own uid; anyone else's appointment answers **404**.
* The service-account key lives **outside** this folder and is never committed (`.gitignore` blocks `.env` and `serviceAccount*.json`).
* The database rules are one file for the whole Firebase project, kept with the app: `app/database.rules.json`. The Admin SDK bypasses rules, so the portal checks roles and ownership in code and is covered by `server/test/`.

## Data layout (shared with the app)

| Path | Written by | Notes |
|---|---|---|
| `roles/{uid}` | administrator only | `doctor`, `nutritionist`, `trainer`, `admin` |
| `specialists/{uid}` | administrator tool and the specialist's own profile page | public profile the app lists: name, type, specialty, fees, working hours, rating |
| `appointments/{id}` | member (create, pay, cancel); portal (status, notes) | the booking; `consultation` holds notes and prescription; `payment` is the transaction (never card details). `pending_payment` bookings are held for 10 minutes and are never shown to specialists |
| `slots/{specialistId}/{startMs}` | member (hold/cancel); portal (cancel) | `{appt, holdUntil?}`; creating this key *is* the booking, so two people cannot book the same time. An unpaid hold expires after 10 minutes |
| `users/{uid}/appointmentIds/{id}` | member | the member's own index |
| `users/{uid}/inbox/{id}` | the app; the portal for "notes added" / "cancelled" | shows in the app's Notifications |
| `accessLog/{appointmentId}/…` | portal | who opened shared data, and when |

## Set up

1. **Packages**: `cd server && npm install` and `cd web && npm install`.
2. **Service account** (server): Firebase console → Project settings → Service accounts → *Generate new private key*. Save it **outside** this folder.
   `cd server && cp .env.example .env`, then set `GOOGLE_APPLICATION_CREDENTIALS` to that file's path.
3. **Web app config** (web): Firebase console → Project settings → General → *Add app → Web*. `cd web && cp .env.example .env.local` and paste `apiKey` and `appId`.
   Authentication → *Sign-in method* → Email/Password must be on (the app already needs it).
4. **Deploy the database rules** (they now include specialists, slots, appointments, payments and held bookings): from the app folder
   `firebase deploy --only database --project baymax-148da`. Until you do, booking in the app will say the database refused access.
5. **Create the specialists** (administrator, from `server/`):
   ```bash
   node scripts/create-specialist.js --email sara@example.com --name "Sara Khan" --type nutritionist \
     --specialty "Sports nutrition" --video-fee 2000 --chat-fee 1200 --years 7
   ```
   It creates the sign-in account if needed (no password is set), writes `roles/{uid}` and `specialists/{uid}`, and prints a one-time link the specialist uses to choose a password. Add `--dry-run` to see what it would do.
6. **Run**: `cd server && npm start` (port 4000) and `cd web && npm run dev` (port 3000). Open http://localhost:3000.

## Tests

* `cd server && npm test` runs the API end to end against an in-memory database (roles, ownership, filters, consent windows, notes, cancel/slot release, validation).
* `cd web && npm run typecheck && npm run build`.

## Known limits (honest list)

* **Video** uses a Jitsi Meet room link created by the app (`MEETING_BASE_URL`, default `https://meet.jit.si`). The public server may ask the first person in a room to sign in. For real use, host your own Jitsi. The scope names WebRTC with TURN; Jitsi is WebRTC (DTLS-SRTP) underneath, but this project does not run its own signalling or TURN servers.
* **Chat only** bookings open the same room with camera and microphone off; the conversation is in the room's text chat. There is no separate chat product.
* **Payment** (Module 15) works end to end in the app but through a **test gateway**: only the published test cards are accepted and no money moves. The scope's JazzCash integration needs merchant credentials and a server that holds the secret key; until then the portal shows "Paid (test)". Going live means writing that server, letting only it write `payment`, and removing the client write rules for it (`app/database.rules.json`).
* The scope's overview cards for **risk alerts, diet reviews, posture flags, clients on track** and the **notification bell** need AI-engine data that does not exist yet; they are not faked. The portal shows only numbers it can compute from appointments.
* **Plan editing** (FR-5: modify workout/diet plans) is not built: plans are derived in the app, not stored, so there is nothing for a specialist to edit yet.
* **Join call** stays available from 5 minutes before the start until the slot ends (the scope says within 5 minutes before *or after* the start). Shared data stays open 60 minutes after the slot so notes can be written up. Both are one-line constants in `server/src/lib/rules.js`.
* The scope says a specialist only appears in the app once they have at least one review. There is no review feature, so that would hide every new specialist; the app shows them as **New** instead.
* Database rules and the portal were tested with unit/API tests only. **The rules have not been run against the Firebase emulator or the live project, and nothing was tried with a real sign-in.**

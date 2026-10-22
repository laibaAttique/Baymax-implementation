# Baymax Specialist Portal

A web app for Baymax **doctors, nutritionists and trainers** to run the consultations that members book in the mobile app. Next.js (App Router, TypeScript). Port **3000**.

It is its own project: its own packages, its own port, its own deployment. It does **not** read the database. It signs in with Firebase and then talks only to the **Baymax API** (`../baymax-api`).

| Project | Folder | Port |
|---|---|---|
| Mobile app | `baymaxxxx 2/untitled folder/app` | n/a (phone) |
| **Specialist portal (this)** | `baymax-portal` | 3000 |
| Admin panel | `baymax-admin` | 3001 |
| API shared by both web apps (+ end-to-end tests) | `baymax-api` | 4000 |

All of them use the same Firebase project, `baymax-148da`, and nothing else is shared: no code, no packages.

## What a specialist can do

* **Register** at `/register` (email and password go straight to Firebase). A registration grants nothing until an administrator approves the licence number in the admin panel; the applicant sees the outcome (and a reason if rejected) when they sign in and can correct and resubmit.
* **Overview**: greeting by the specialist's own clock, requests waiting, today's consultations (live first, with **Join call**), and **New requests** with **Accept** / **Decline**. Accepting creates the video room.
* **Appointments**: every booking, filterable by patient name, status and date range. The appointment page shows the patient's note, the meeting link, and a **patient dashboard** of what the patient chose to share (health summary, 7-day calories, 30-day workouts, with charts), only after the request is accepted and only from 30 minutes before to 60 minutes after the slot.
* **My patients and the patient record**: everyone with an accepted appointment, their history with you, notes and prescriptions.
* **Plans**: diet plan (doctor, nutritionist) and workout plan (doctor, trainer): approve the patient's plan as it is, or change it. The patient is told and can switch back to Baymax's own plan.
* **Food log review** (nutritionist): approve or flag each day, with a reason to flag.
* **Prescriptions** (doctor): everything prescribed.
* **My profile**: specialty, bio, fees, working hours, "taking bookings". **Close my account** (asks for the password and DELETE).
* **Overview cards per role** (doctor: patients, today, pending prescriptions, unread messages; nutritionist: pending diet reviews, video consultations, active clients, unread messages; trainer: workouts to review, video consultations, active trainees, unread messages).
* **Payments**: what patients paid you (earned, upcoming, waiting, pay-at-clinic, refunded, refund due), filters, and a CSV download. Test gateway only.
* **Video call room** (`/appointments/:id/call`): device check, Jitsi inside the portal, join/leave log, notes beside the call, "Mark completed" afterwards.
* **Messages** (`/messages`): a conversation per accepted appointment, unread counts in the menu, plain text only.
* **Alerts**: the menu counts waiting requests and unread messages; the browser can show a desktop alert while the portal is open.
* **Checks**: every form shows its problems next to the field before sending (the API checks again); a session that ends mid-use returns to sign-in with a message; a screen that fails shows a recovery page instead of a blank one.

## Run

1. `npm install`
2. Firebase **web app** config: Firebase console → Project settings → General → *Add app → Web*. Then `cp .env.example .env.local` and paste `apiKey` and `appId`. Email/Password sign-in must be on.
3. Start the API first (`../baymax-api`, `npm start`, port 4000). Its `PORTAL_ORIGIN` must include `http://localhost:3000`.
4. `npm run dev` and open http://localhost:3000.

`npm run typecheck` and `npm run build` check it.

## Safety

* The browser never reads the database; every call carries a Firebase ID token and the API decides what the person may see. A specialist reaches only their own patients and appointments (anyone else's answers 404).
* Opening a patient's shared data is logged on the server (`accessLog`).
* Meeting links are only ever opened as plain `https://` addresses in a new tab with `noopener`.

# Baymax Admin Panel

A separate web app for Baymax **administrators**: approve or reject specialist registrations, see how consultations are going, add or delete specialists.

It is its own project (own packages, own port, own deployment) and is separate from the specialist portal (`../baymax-portal`). It talks to the Baymax API (`../baymax-api`), whose `/api/admin/*` routes answer only to the `admin` role (403 for everyone else, checked on the server). It signs in with the same Firebase project as the app and the portal.

| Page | What it does |
|---|---|
| Overview | counts of specialists, waiting registrations and appointments by status |
| Registrations | shows each registration with the licence number; **Approve** (creates the role and the public profile, marked verified) or **Reject** with a reason |
| Specialists | list of everyone patients can book; add one directly; **delete** one (their future appointments are cancelled and the patients told; past notes stay) |

## Run

1. `npm install`
2. `cp .env.example .env.local` and fill in the Firebase **web app** values (the same ones the portal uses).
3. The API server's `PORTAL_ORIGIN` (in `../baymax-api/.env`) must include this panel: `PORTAL_ORIGIN=http://localhost:3000,http://localhost:3001`. Restart the server after changing it.
4. `npm run dev` and open http://localhost:3001.

## The administrator login

The login is created once, on your computer, by one command. It generates a strong password and saves the login to a private file in this folder, `.env.admin` (readable only by you, ignored by git). The password is not printed anywhere.

```bash
cd ../baymax-api
node scripts/create-admin.js --email you@example.com
```

Use an email you can open (it is where "Forgot your password?" sends a reset link). Then open `.env.admin` to read the password and sign in at http://localhost:3001.

* If the email already has an account, its password is **not** changed and nothing is saved. Add `--reset-password` to give it a new generated password, or run `node scripts/make-admin.js --email ...` to make it an administrator and keep its own password.
* A doctor, nutritionist or trainer account is never converted: use a separate email.
* Nobody can promote themselves from a browser, and the panel cannot make anyone an administrator.

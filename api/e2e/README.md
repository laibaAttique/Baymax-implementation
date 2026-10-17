# End-to-end checks

These run the real pieces together on the **local Firebase emulators** (fake Auth and Realtime Database on your Mac). Nothing here touches the real `baymax-148da` project, and no real account or data is created.

| File | What it proves |
|---|---|
| `rules.e2e.mjs` | The real database rules (`app/database.rules.json`), with real signed-in users: who can hold, pay for and cancel a booking, who can read what, that a member can never write plans, reviews, links or roles. |
| `flow.e2e.mjs` | The whole system: make-admin script, registration, approval, booking by the "phone", accept (video room), plans, food-log review, closing an account, admin delete. The real Express API with real token checks. |
| `admin-account.e2e.mjs` | `scripts/create-admin.js`: the login it saves really signs in and is accepted by the admin API; the file is private; the password is never printed; an existing account is not hijacked. |
| `seed-browser.mjs`, `book-as-member.mjs`, `start-web.sh` | Helpers for a manual browser walkthrough (specialist portal on 3010, admin panel on 3011, API on 4010, all on the emulators). |

## Run

```bash
cd emulator && cp "<app>/database.rules.json" . && firebase emulators:start --only auth,database --project demo-baymax
# in another terminal
cd e2e && npm install
node --test --test-force-exit rules.e2e.mjs flow.e2e.mjs
```

(The first emulator start downloads the Database emulator, about 50 MB.)

## Safety

The emulators answer only on 127.0.0.1. The web apps only talk to them when `NEXT_PUBLIC_USE_EMULATOR=true` is set, which `start-web.sh` does and nothing else does. After a browser run, check that your real project is unchanged.

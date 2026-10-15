# Baymax — AI-driven adaptive fitness & health monitoring

Final-year project (COMSATS University Islamabad). Flutter app + small Node backend + model-training scripts.

| Folder | What it is |
|---|---|
| `app/` | Flutter app (Android/iOS). Modules 1, 2, 3, 7, 8, 12 plus online consultation and payment (merged Modules 14 and 15, payment in test mode). Progress log: [`app/PROGRESS.md`](app/PROGRESS.md) |
| `backend/` | Node/Express server (label OCR proxy, legacy profile routes) and Firestore seed/verify tools |
| `portal/` | Specialist web portal for the consultation module: Next.js `web/` + Express `server/`, same Firebase project, separate packages. Setup: [`portal/README.md`](portal/README.md) |
| `app/ml/` | Phase 2 model training (Kaggle scripts, dataset links): [`app/ml/README.md`](app/ml/README.md) |

## Run the app

1. Install Flutter and the Firebase CLI, then `firebase login`.
2. The Firebase client config is **not** committed (this repo is public). Generate it:
   ```bash
   cd app
   flutterfire configure --project=baymax-148da   # creates lib/firebase_options.dart, google-services.json, GoogleService-Info.plist
   flutter pub get
   flutter run
   ```
   You need access to the `baymax-148da` Firebase project. In its console enable Authentication → Email/Password and Google.
3. Backend (only needed for the allergy-scanner photo reading): `cd backend && cp .env.example .env && npm install && npm start`.

## Data

* User data: Firebase Realtime Database, protected by `app/database.rules.json`.
* Food and exercise catalogues: Cloud Firestore, protected by `app/firestore.rules`; upload with `backend/tools/seed_firestore.js`.
* Deploy rules: `firebase deploy --only database,firestore:rules --project baymax-148da`.

Decision support only — Baymax does not diagnose or treat any condition.

## Note on `app/assets/data/foods_bulk.json`

The searchable food list (about 2,760 foods) is **not published here**: the usage licence of two of its sources is not yet verified. The file in this repo is an empty placeholder so the app still builds; the app reads the full list from Firestore. Regenerate it with `app/ml/food_catalog/build_catalog.py` once the licences are confirmed.

# Baymax — AI-driven adaptive fitness & health monitoring

Final-year project (COMSATS University Islamabad). Flutter app + small Node backend + model-training scripts.

| Folder | What it is |
|---|---|
| `app/` | Flutter app (Android/iOS). Modules 1, 2, 3, 7, 8, 12. Progress log: [`app/PROGRESS.md`](app/PROGRESS.md) |
| `backend/` | Node/Express server (label OCR proxy, legacy profile routes) and Firestore seed/verify tools |
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

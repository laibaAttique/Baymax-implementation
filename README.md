# Baymax — AI-driven adaptive fitness & health monitoring

Final-year project (COMSATS University Islamabad). Flutter app, Express API, two Next.js web applications (specialist portal and administrator panel) and model-training scripts. All use one Firebase project but are separate programs with their own packages.

| Folder | What it is |
|---|---|
| `app/` | Flutter app (Android/iOS): auth, health profile and classification, workout and nutrition plans, diet tracker, allergy scanner, gamification, chatbot, alerts, analytics, online consultation and payment (payment in test mode). Progress log: [`app/PROGRESS.md`](app/PROGRESS.md). Test cases with IDs: `app/test/atc/` |
| `api/` | Express 5 API behind both web apps (token check, roles, appointments, plans, registration approval). Unit/API tests in `api/test/`, end-to-end tests on the Firebase emulators in `api/e2e/`. Setup: [`api/README.md`](api/README.md) |
| `portal/` | Specialist web portal (Next.js, TypeScript). Setup: [`portal/README.md`](portal/README.md) |
| `admin/` | Administrator web panel (Next.js, TypeScript). Setup: [`admin/README.md`](admin/README.md) |
| `backend/` | Node/Express server (label OCR proxy) and Firestore seed/verify tools |
| `app/ml/` | Model training (Kaggle scripts, dataset links): [`app/ml/README.md`](app/ml/README.md) |
| `docs/` | Chapter 4 (implementation) and Chapter 5 (test cases, evidence, generator) of the report |

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

## Notes on the food data and the food photo model

* `app/assets/data/foods_bulk.json` is the searchable food list (about 2,760 foods) built from the team's own lists, the Indian Nutrient Databank and USDA FoodData Central SR Legacy. The team has **not independently verified the usage licences of the team list and the Indian Nutrient Databank**; check them before reusing this file elsewhere. Rebuild it with `app/ml/food_catalog/build_catalog.py`.
* `app/assets/models/food_classifier.tflite` is the experimental food photo model (EfficientNetV2-B0, 22 foods, trained on a cleaned Food-101 subset and two Kaggle Pakistani-dish datasets; the licences of the web-sourced photos are unverified). It failed its per-class check on aloo gobi and paratha, so release builds do not use it: it is loaded only in debug and profile builds. See `app/ml/README.md`.

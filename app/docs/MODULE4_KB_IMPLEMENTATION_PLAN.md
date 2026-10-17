# Module 4 — Dataset analysis and knowledge-base implementation plan

Goal: turn free-exercise-db into a knowledge base the workout generator can reason over, keyed by the **Module 2 health
classification** (Healthy, Overweight, Obese, At-Risk, Diabetic, Cardiac, plus risk level and risk factors).
Progress is tracked in [MODULE4_PHASE_LEDGER.md](MODULE4_PHASE_LEDGER.md); the architecture of what already exists is in
[MODULE4_WORKOUT_KNOWLEDGE_BASE.md](MODULE4_WORKOUT_KNOWLEDGE_BASE.md).

All numbers below were computed from the pinned dataset (`ml/exercise_catalog/cache/exercises-f00c92c….json`) and the built
catalogue (`assets/data/exercise_catalog.json`) on 2026-10-17. They are not estimates.

## 1. Dataset analysis (free-exercise-db @ f00c92c)

### 1.1 Shape and completeness (876 records, 11 fields, all present on every record)

| Field | Empty / null | Consequence for the knowledge base |
|---|---|---|
| secondaryMuscles | 272 (31%) | fine — only primary muscles drive joint and group derivation |
| mechanic | 87 (10%) | complexity falls back to 1; joint rules that need `compound` do not fire (conservative only for knee/back) |
| equipment | 77 (9%) | treated as body weight (`none`) |
| force | 30 (3%) | no isometric tag, no push/pull joint rules |
| instructions | 5 | **dropped** (cannot be shown) → 871 imported |
| images | 3 | shown with an icon |

### 1.2 Distributions

- **category:** strength 584 · stretching 123 · plyometrics 61 · powerlifting 38 · olympic weightlifting 35 · strongman 21 · cardio 14.
  Cardio is very thin (14, mostly machines) — aerobic work must keep coming from the curated library.
- **level:** beginner 525 · intermediate 294 · expert 57.
- **equipment:** barbell 170 · dumbbell 123 · other 122 · body only 111 (+77 none) · cable 81 · machine 67 · kettlebells 56 · bands 20 ·
  medicine ball 17 · exercise ball 12 · foam roll 11 · e-z bar 9. → only **186** need no equipment, which is why the curated
  body-weight library stays primary and catalogue entries are offered only for owned equipment.
- **force:** push 371 · pull 371 · static 104. **mechanic:** compound 491 · isolation 298.
- **primary muscles:** quadriceps 148, shoulders 129, abdominals 93, chest 84, hamstrings 79, triceps 73, biceps 53, lats 38,
  middle back 34, calves 28, lower back 27, forearms 25, glutes 22, traps 15, adductors 13, neck 8, abductors 8.

### 1.3 What the dataset does **not** contain (and how the knowledge base handles it)

| Missing | Handling |
|---|---|
| intensity / MET | mapped to the 2024 Compendium: 181 exact, 606 approximate, 84 unmatched (not scheduled) |
| impact | derived: plyometrics and running/jumping cardio → high (67); everything else low (804) |
| joint loading | derived from muscles + mechanic + force + impact: knee 213, shoulder 151, ankle 95, lower back 64, wrist 58 |
| body position, hand support | not available; wrist derived from forearm muscles or a hand-supported name (push-up, dip, plank, crawl…) |
| contraindications / medical suitability | **none in the dataset** — supplied by the safety rule repository, never by the dataset |
| sets/reps guidance | from the prescription rules by intensity, never from the dataset or MET |

### 1.4 Intensity bands (WHO 2020 definition: light < 3 MET, moderate 3–5.9, vigorous ≥ 6)

| Band | Catalogue | Mostly |
|---|---|---|
| light | 134 | stretching 112, strength 22 |
| moderate | 528 | strength 509 |
| vigorous | 125 | plyometrics 61, olympic 34, powerlifting 22, cardio 8 |
| no value | 84 | strength 49, strongman 21 |

This band is the bridge between the dataset and the classification: it is a published, citable property of each
exercise's mapped activity, and the classification already decides the plan intensity (Low / Moderate / High).

### 1.5 Data-quality findings and fixes

| # | Finding | Status |
|---|---|---|
| D1 | `wrist` was never derived for catalogue entries, so the INJ-WRIST rule could not reach any of them (the curated library had 21) | **fixed 2026-10-17** — 58 entries now tagged; test added |
| D2 | olympic / strongman / powerlifting are derived as `impact: low` although they are explosive | covered: all carry `maximal` and are excluded for everyone by PRG-NO-MAXIMAL; noted for review |
| D3 | 410 exercises share one approximate code (02054, resistance training) | expected: the Compendium has no per-exercise codes; marked approximate, pending review |
| D4 | cardio has only 14 records | aerobic sessions keep using curated exercises; no change |
| D5 | importer docstring pointed at a non-existent `workout_safety_rules.json` | fixed |

## 2. Classification → knowledge base: what exists and what is missing

| Module 2 output | Used today by | Gap |
|---|---|---|
| category Cardiac | intensity Low, MED-CARDIAC, screening gate | no explicit cap on **vigorous** activities (relies on impact/tag exclusions) |
| category Diabetic | MED-DIABETES | — |
| category At-Risk (condition) | intensity Low + condition rules | PCOS has no rule or note |
| category At-Risk (**model-flagged**, no condition reported) | intensity Low only | nothing explains to the user why the plan is gentler |
| category Obese / Overweight | BODY-* by BMI | — |
| riskLevel High / Moderate / Low | not used | not a fact the engine can read |
| riskFactors | shown in Module 2 only | not carried into plan explanations |
| (none) | — | **no explicit per-classification exercise profile** (frequency, intensity band, type mix, minutes); it is spread across `_intensity`, templates and rules |

## 3. Design of the classification profile layer

A versioned, cited data repository, `lib/services/workout_rules/classification_profiles.dart`, built exactly like the rule
repository (data, `reviewStatus: pending`, evidence keys). One profile per Module 2 category:

```
ClassificationProfile(
  category: 'Cardiac',
  intensityBands: {light, moderate},        // WHO MET bands allowed for scheduled exercises
  preferredCategories: [cardio, strength, stretching],
  weeklyAerobicMinutes: (min, max),          // WHO 2020 adult targets, scaled by plan intensity
  resistanceDays: (min, max),
  flexibility: true,
  emphasis: 'steady, low-impact aerobic work', // shown to the user
  evidence: ['who2020', 'acsm11', 'aha2024'],
)
```

Rules for using it (all enforced in code and tested):

1. **Restrict only, never relax.** A profile can narrow the bands or the pool; it cannot bring back anything a safety rule
   excluded. The engine's "most restrictive wins" merge is reused.
2. **Unknown is not safe.** An exercise without a MET value has no band; it is not scheduled under a profile that restricts
   bands (same rule as unknown impact).
3. **Bands come from the Compendium value only**, never from names or ranking scores.
4. **Order stays** gate → safety rules → profile filter → ranking → scheduling.
5. Every scheduled exercise carries the profile id in its explanation ("Chosen for your Cardiac profile: moderate intensity").
6. Same profile + rule + catalogue versions → identical plan.

Explanations (implemented as **profile notes**, not as safety rules, so the rule repository and its Module 3 oracle
stay exactly as they were):

- `PN-STAT-RISK` — model-flagged At-Risk: no extra restriction; says the plan starts at moderate effort because of a
  screening estimate, not a diagnosis.
- `PN-PCOS` — note only (2023 international PCOS guideline: regular aerobic + strength training).
- `PN-RISK-HIGH` — Module 2 risk level High: build up slowly, talk to the doctor before increasing effort.
- `Fact.riskLevel` and `Fact.statisticalRisk` are available to rules and notes. The draft idea "riskLevel High → max 4
  days" was **dropped**: no cited source supports it, and it would conflict with the ADA spread-across-the-week advice.

Implementation decisions taken while building (2026-10-17):

- The band cap is applied by the engine (`assess(facts, profile:)`), merged like every other restriction; without a
  profile the assessment is the rule repository alone.
- Profile version is recorded as `rulesVersion = rules-2026.10.1+profiles-2026.10.1` and the engine version was bumped to
  `workout-engine-2026.10.2`. **No database rule change was needed**, so nothing has to be deployed for Module 4.
- A specialist's week (Aamna's Module 14) is measured against the same profile; the gate still applies.
- The Module 4 adaptations (`ruleNotes`) now travel into Module 5 (`SessionExercise.safetyNotes`) and are shown on the
  mode-selection and manual-guidance screens.

## 4. Implementation phases (remaining work)

Each phase ends with tests green (`flutter test --concurrency=2`, TEMP on D:) and a ledger entry.

| Phase | Work | Done when |
|---|---|---|
| **K1** | Dataset analysis + D1/D5 fixes (this document) | done — see ledger |
| **K2** | `Exercise.intensityBand` (from the Compendium MET only), catalogue + curated | done — band counts equal §1.4 |
| **K3** | `ClassificationProfile` repository (6 profiles + 3 notes, cited, pending); `HealthFacts.riskLevel`, `statisticalRisk` | done — one profile per category, evidence resolves |
| **K4** | Band cap in `SafetyAssessment` (unknown intensity not scheduled under a cap) | done — 3,000-person property test; Module 3 oracle unchanged |
| **K5** | Weekly structure: rest-day limit (Diabetic), aerobic / strength / stretching tallies, walking suggestion | done — reported, not enforced as a medical target |
| **K6** | "Your training profile" card on the workout tab; intensity band on exercise detail; adaptations shown in Module 5 | done — widget tests |
| **K7** | Versions: `rulesVersion` carries the profile version, engine 2026.10.2; no DB rule change | done |
| **K8** | Review sheet `docs/review/module4_review_sheet.csv` generated from the code by `test/review_sheet_test.dart` | done — test fails if the sheet is stale |
| **K9** | Device verification on the Redmi Note 11 (needs a working Android build — see blocker B1 in the ledger) | blocked |
| **K10** | Docs, PROGRESS.md, requirement traceability | done |

Out of scope (owned by teammates or not asked for): Injury Risk module, diet module, specialist plans (Aamna's — only
read, never changed, except the shared merge points already listed in the ledger).

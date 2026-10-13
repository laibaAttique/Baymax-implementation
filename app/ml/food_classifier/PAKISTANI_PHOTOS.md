# Collecting Pakistani food photos (Module 7)

Food-101 has none of the dishes below, so the model can only learn them from the team's own photos.
Without them, the scan screen will never suggest biryani, karahi, nihari, haleem, etc.

## Folder layout

Start from `pakistani_photos_template.zip` (next to this project): one folder per catalogue id, and inside it **one sub-folder per
plate / meal / place ("session")**:

```
pakistani_photos/custom_photos/
  chicken_karahi/
    2026-10-14_ammi/        IMG_0001.jpg ...
    2026-10-16_restaurant/  IMG_0001.jpg ...
  haleem/
    ...
```

Folder names are the ids in `assets/data/foods.json`; a typo stops the notebook with a "did you mean ...?" message.

## Priority dishes (start here)

| Priority | Catalogue ids |
|---|---|
| 1 — Pakistani, not in Food-101 | `chicken_biryani`, `chicken_karahi`, `beef_nihari`, `haleem`, `daal`, `pulao`, `seekh_kebab`, `shami_kebab`, `halwa_puri`, `aloo_paratha`, `paratha`, `roti`, `naan` |
| 2 — common and easy to photograph | `chana_masala`, `bhindi`, `aloo_gobi`, `mutton_curry`, `khichdi`, `pakora`, `raita`, `gulab_jamun`, `kheer`, `suji_halwa`, `tea_milk`, `lassi_sweet` |

## How to photograph (this decides whether the model works)

- **Aim for 100+ photos per dish** as a working target (a rule of thumb, not a verified threshold; the held-out
  accuracy table from the notebook tells you whether it was enough).
- **Different plates, kitchens, restaurants and people** — not 100 shots of one plate. A model trained on one
  plate learns the plate.
- Vary angle (top-down and 45°), lighting (daylight, tube light, night), and portion size.
- Include realistic messy photos (a half-eaten plate, a hand in frame), because that is how users will shoot.
- One dish per photo. If a thali has several dishes, crop or photograph them separately.
- Keep originals at phone resolution; the cleaning script resizes them.

## How the notebook treats your photos

- Whole sessions go to train, selection or test (about 60 / 20 / 20), never single photos, so near-identical shots of one plate cannot
  inflate the accuracy. Photos without session folders are accepted but the notebook warns that the accuracy may look better than it is.
- A dish is **trained only with 100+ usable photos from enough sessions (about 6+) to leave 15+ test photos.** Otherwise it is listed as
  *NOT TRAINED*, the app keeps manual selection for it, and the other dishes are unaffected.
- Phone rotation is corrected; exact duplicates and near-identical pictures from different sessions are removed; HEIC files are skipped (set the
  iPhone camera to Most Compatible).
- Dishes that pass go through the same shipping gate as Food-101 (every class recall >= 70%). With only ~15-20 test photos per dish the
  recall is a rough estimate, not a precise one. Collect more sessions to tighten it.

## Privacy and licence

- Photograph food, not people. Do not include faces or identifiable documents.
- Only use photos the team took itself or that the owner allowed. Do not scrape search engines; that breaks
  the rule that every data source is cited and licensed.
- Ask the other team members before sharing photos taken in restaurants.

## After collecting

1. Zip the `pakistani_photos` folder and upload it to Kaggle as a **second dataset** (next to `food_dataset_kaggle.zip`).
2. In `module7_food_model_kaggle.ipynb` press *Add Input* for **both** datasets, set GPU + Internet, *Run All*.
3. Read the table printed under "1a" (photos found / used / sessions / train-selection-test per dish and which dishes were *NOT TRAINED*),
   then the per-class results and the shipping gate at the end.
4. If the gate passes, copy `food_classifier.tflite` and `food_classifier_labels.json` into `assets/models/` and device-test.

# Bulk food list from USDA FoodData Central (Module 8, mockup M23.1: a search over 1,000+ foods)

`build_usda_foods.py` turns the USDA **SR Legacy** dataset into `assets/data/foods_usda.json` (about 1,070 everyday foods).

* **Source:** U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, SR Legacy (April 2018 release),
  <https://fdc.nal.usda.gov/download-datasets>. USDA publishes FoodData Central under CC0 1.0 (public domain); it asks for a credit.
* **Download:** `FoodData_Central_sr_legacy_food_json_2018-04.zip` (13 MB). The dataset is not kept in the project; run
  `python3 -I build_usda_foods.py <sr_legacy.json> ../../assets/data/foods.json ../../assets/data/foods_usda.json`.
* **What is selected:** generic foods from everyday categories (fruit, vegetables, dairy and eggs, poultry, meat, fish, pulses, grains, baked
  goods, nuts, drinks, snacks ...), a quota per category, at most three variants of the same base food; brands, restaurant and baby foods,
  game meats and alcohol are left out. Foods already in the curated catalogue are skipped.
* **Nutrition:** USDA's own values (energy, protein, fat, carbohydrate per 100 g), scaled to the first household portion USDA lists (or 100 g).
* **Allergens are NOT in the USDA data.** They are guessed from the food's name and category by keyword rules that deliberately over-warn,
  and every item is flagged, so the app says "allergens estimated from the name". Read the label if an allergy is serious.
* Bulk foods have `role: usda` and no meal slots, so they never appear in generated meal plans; they are only for search and logging.

# Allergen dictionary (Module 10, and the allergen labels of the food lists)

`build_allergen_terms.py` turns two Open Food Facts taxonomy files into `assets/data/allergen_terms.json` (about 1,800 ingredient names, each with the
allergens it carries, plus 24 "not dairy" phrases such as coconut milk and a supplement of ~100 team-written food words).

1. Download (by hand, `ml/data/` is git-ignored) from https://github.com/openfoodfacts/openfoodfacts-server/tree/main/taxonomies :
   `allergens.txt` and `food/ingredients.txt` into `ml/data/openfoodfacts/`.
2. `python3 ml/allergen_data/build_allergen_terms.py` (standard library only).

How it works: `allergens.txt` lists the words of each EU allergen group. In `ingredients.txt` 76 ingredients carry an `allergens:en:` property and every
ingredient below them inherits it (cheddar below cheese below milk); all their English names become terms. Exclusions are narrow and per allergen.

**Licence not confirmed.** The repository is AGPL-3.0 and the Open Food Facts database is ODbL, but nothing in the repository says which licence covers the two
taxonomy files. Until that is checked, do not publish `assets/data/allergen_terms.json` in a public repository; cite "Open Food Facts" wherever it is used
(the Sources screen does).

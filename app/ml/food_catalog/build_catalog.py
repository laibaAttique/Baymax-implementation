#!/usr/bin/env python3
"""Builds the app's searchable food list (`assets/data/foods_bulk.json`) from the team's food data (amna.zip) and USDA FoodData Central.

    python3 -I build_catalog.py <csv_dir> <usda_sr_legacy.json> <curated foods.json> <out foods_bulk.json> [report.txt]

Inputs
  * <csv_dir>/Calorica_*.csv, beverages.csv, fruits.csv, vegetables.csv: the team's food list (per 100 g, with serving sizes, Pakistani /
    Indian names and spellings). Each row names its own origin (USDA, INDB, CURATED, brand official ...); the origin is kept as `sourceNote`.
  * <csv_dir>/ind.csv: the Indian Nutrient Databank (INDB), recipe-based values per 100 g and per serving.
  * <usda_sr_legacy.json>: ~1,070 everyday foods taken from USDA FoodData Central SR Legacy (public domain, CC0 1.0) by build_usda_foods.py.
  * <curated foods.json>: the app's 97 foods used for meal plans. They always win a name clash and are not written to the output.

Rules
  * No number is invented. Serving values are the per-100 g values scaled to the stated serving grams.
  * Nothing here carries allergen data. Allergens are GUESSED from the food's name (keywords incl. Urdu / Hindi dish words) and deliberately
    over-warn. The app shows "allergens estimated" for every food in this file.
  * Rows with an impossible value (negative, kcal/100 g above 900, no serving weight) are dropped and listed in the report.
"""
import csv, glob, json, os, re, sys, collections

csv_dir, usda_path, curated_path, out_path = sys.argv[1:5]
report_path = sys.argv[5] if len(sys.argv) > 5 else None
report = []


def log(msg):
    report.append(msg)


def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', s.lower()).strip()


def num(v):
    try:
        x = float(str(v).strip())
        return x if x == x else None
    except Exception:
        return None


def has(text, pattern):
    return re.search(pattern, text, re.I) is not None


# ---------------------------------------------------------------- allergen guesses (over-warning on purpose)
def guess_allergens(name, extra=''):
    t = (name + ' ' + extra).lower()
    out = set()
    dairy = (r"\b(milk|cheese|yogurt|yoghurt|dahi|curd|cream|butter|ghee|whey|casein|custard|kefir|lassi|raita|paneer|khoya|khoa|mawa|kheer|"
             r"rabri|rabdi|malai|kulfi|ice cream|pudding|lactose|buttermilk|chaas|chaach|ricotta|mozzarella|cheddar|parmesan|cottage|latte|"
             r"cappuccino|mocha|milkshake|shake|cheesecake|gulab jamun|rasmalai|rasgulla|barfi|burfi|peda|halwa)\b")
    dairy_not = (r"(peanut butter|cocoa butter|nut butter|almond butter|sunflower|apple butter|shea|butter bean|butternut|coconut (milk|cream)|"
                 r"almond milk|soy milk|soya milk|rice milk|oat milk|cream of tartar|soymilk|sesame butter|seed butter|margarine|butterscotch)")
    if has(t, dairy) and not has(t, dairy_not):
        out.add('dairy')
    if has(t, r"\b(egg|eggs|anda|omelet|omelette|mayonnaise|mayo|meringue|eggnog|custard|bhurji)\b") and not has(t, r"eggplant|egg ?less"):
        out.add('eggs')
    if has(t, r"\b(almond|badam|walnut|akhrot|cashew|kaju|pecan|pistachio|pista|hazelnut|filbert|macadamia|brazil nut|pine nut|chilgoza|"
              r"peanut|moongphali|mungfali|nuts|praline|marzipan|nutella|trail mix|mixed nut)") and not has(t, r"water chestnut|coconut|nutmeg|butternut|doughnut|donut|nut ?free"):
        out.add('nuts')
    fish = (r"\b(salmon|tuna|cod|haddock|halibut|tilapia|trout|sardine|mackerel|herring|anchovy|anchovies|catfish|bass|pollock|snapper|swordfish|"
            r"perch|flounder|sole|mahi|carp|pike|eel|bluefish|whitefish|fish|machli|machhli|rohu|hilsa|pomfret|bombay duck|roe|caviar|pompano|"
            r"mullet|grouper|shad|smelt|sturgeon|turbot|whiting|sushi|sashimi|unagi|worcestershire)\b")
    if has(t, fish):
        out.add('fish')
    shell = r"\b(shrimp|prawn|jhinga|crab|lobster|crayfish|crawfish|oyster|clam|mussel|scallop|squid|octopus|abalone|snail|whelk|mollusk|crustacean|cuttlefish|conch|surimi)\b"
    if has(t, shell):
        out.add('shellfish')
    if has(t, r"\b(soy|soya|soybean|tofu|tempeh|miso|edamame|natto|shoyu|teriyaki|tamari|textured vegetable|nuggets? \(soy)"):
        out.add('soy')
    if has(t, r"\b(sesame|til|tahini|tahina|halvah|halva|hummus|gajak|rewri|revdi|gomashio|benne)\b"):
        out.add('sesame')
    gluten = (r"\b(wheat|atta|maida|bread|bun|buns|bagel|roll|rolls|pasta|noodle|noodles|ramen|udon|macaroni|spaghetti|couscous|bulgur|semolina|"
              r"suji|sooji|rava|farina|barley|rye|oat|oats|oatmeal|malt|seitan|spelt|triticale|cracker|crackers|cookie|cookies|biscuit|biscuits|"
              r"cake|brownie|muffin|pie|pastry|donut|doughnut|croissant|waffle|pancake|pizza|pretzel|crouton|breadcrumb|breading|tortilla|"
              r"pita|naan|roti|chapati|chapatti|phulka|paratha|parantha|poori|puri|bhatura|kulcha|rusk|paav|pav|samosa|kachori|pakora|"
              r"dumpling|gyoza|lasagna|ravioli|burger|sandwich|wrap|shawarma|falafel|cereal|granola|muesli|cornflake|dalia|daliya|sheera|"
              r"seviyan|sewai|vermicelli|maggi|bhature|momo|momos|spring roll|nuggets?|fries battered|schnitzel|blini|pelmeni|vareniki|"
              r"borscht|tempura|katsu|ramen|soba|bao|baklava|kunafa|knafeh|fatayer|manakish|pide|lahmacun|kofta)\b")
    gluten_not = r"(rice|corn|potato|coconut|almond|soy|chickpea|tapioca|buckwheat|quinoa|millet|sorghum|jowar|bajra)\s+(flour|bread|pasta|noodle)|gluten.free|rice noodle|corn tortilla|corn flake|rice paper"
    if has(t, gluten) and not has(t, gluten_not):
        out.add('gluten')
    return sorted(out)


ICON = {
    'vegetable': '🥦', 'fruit': '🍎', 'homemade_everyday': '🍲', 'beverage': '🥤', 'dairy': '🥛', 'fast_food': '🍔', 'snacks': '🍟',
    'desserts': '🍰', 'middle_eastern_food': '🍲', 'french_food': '🍲', 'korean_food': '🍜', 'japanese_food': '🍜', 'bread': '🍞',
    'meat': '🍢', 'fish_seafood': '🐟', 'condiments': '🍲', 'russian_food': '🍲', 'pulses_legumes': '🥣', 'poultry': '🍗', 'grain': '🍚',
    'oils': '🫒', 'seeds': '🥜', 'cereal': '🥣', 'rice': '🍚', 'popcorn': '🍟', 'eggs': '🥚',
}


def split_names(*cells):
    out = []
    for c in cells:
        for part in re.split(r'[;|]', c or ''):
            p = part.strip()
            if p:
                out.append(p)
    return out


def unique_aliases(name, candidates, cap=14):
    seen = {norm(name)}
    out = []
    for c in candidates:
        k = norm(c)
        if not k or k in seen or len(c) > 60:
            continue
        seen.add(k)
        out.append(c)
        if len(out) >= cap:
            break
    return out


def r1(x):
    return round(x, 1)


# ---------------------------------------------------------------- 1. the team's Calorica lists
items = []
dropped = []


def add(item, why_name):
    for key in ('kcal', 'protein', 'carbs', 'fat'):
        if item[key] is None or item[key] < 0:
            dropped.append(f'{why_name}: {key} missing or negative')
            return
    if item['grams'] <= 0 or item['grams'] > 2000:
        dropped.append(f'{why_name}: unusable serving weight {item["grams"]}')
        return
    if item['kcal'] / item['grams'] * 100 > 905:
        dropped.append(f'{why_name}: {item["kcal"]/item["grams"]*100:.0f} kcal per 100 g is impossible')
        return
    items.append(item)


for path in sorted(glob.glob(os.path.join(csv_dir, 'Calorica_*.csv'))):
    for row in csv.DictReader(open(path, encoding='utf-8-sig')):
        name = row['primary_name'].strip()
        k100, p100, c100, f100 = (num(row.get(x)) for x in ('calories_100g', 'protein_100g', 'carbs_100g', 'fat_100g'))
        if None in (k100, p100, c100, f100):
            dropped.append(f'{name}: missing per-100 g values')
            continue
        # default serving = the "medium" one, else the first one that has a weight
        sv = None
        for size in ('medium', 'small', 'large'):
            g = num(row.get(f'serving_{size}_g'))
            if g and g > 0:
                sv = (row.get(f'serving_{size}_name', '').strip() or 'serving', g)
                break
        if sv is None:
            sv = ('100 g', 100.0)
        label, grams = sv
        k = grams / 100.0
        names = split_names(row.get('common_names'), row.get('pakistani_names'), row.get('indian_names'), row.get('urdu_hindi_transliteration'),
                            row.get('spelling_variations'), row.get('search_terms'))
        cat = row['category'].strip()
        add({
            'id': 'cal_' + row['code'].strip().lower(),
            'name': name,
            'aliases': unique_aliases(name, names),
            'icon': ICON.get(cat, '🍽️'),
            'serving': label,
            'grams': r1(grams),
            'kcal': r1(k100 * k), 'protein': r1(p100 * k), 'carbs': r1(c100 * k), 'fat': r1(f100 * k),
            'allergens': guess_allergens(name, ' '.join(names)),
            'meals': [], 'role': 'bulk', 'tags': [],
            'source': 'calorica',
            'sourceNote': (row.get('source') or '').strip()[:60],
        }, name)

# the three small lists (per 100 g, no serving sizes)
for fname, cat in (('beverages.csv', 'beverage'), ('fruits.csv', 'fruit'), ('vegetables.csv', 'vegetable')):
    p = os.path.join(csv_dir, fname)
    if not os.path.exists(p):
        continue
    for i, row in enumerate(csv.DictReader(open(p, encoding='utf-8-sig'))):
        name = row['name'].strip()
        vals = [num(row.get(x)) for x in ('calories', 'protein', 'carbs', 'fat')]
        if None in vals:
            dropped.append(f'{name}: missing values')
            continue
        add({
            'id': f'lst_{cat}_{i + 1:02d}', 'name': name, 'aliases': [], 'icon': ICON[cat], 'serving': '100 g', 'grams': 100.0,
            'kcal': r1(vals[0]), 'protein': r1(vals[1]), 'carbs': r1(vals[2]), 'fat': r1(vals[3]),
            'allergens': guess_allergens(name), 'meals': [], 'role': 'bulk', 'tags': [],
            'source': 'calorica', 'sourceNote': (row.get('source') or 'team list').strip()[:60],
        }, name)

# ---------------------------------------------------------------- 2. Indian Nutrient Databank
for row in csv.DictReader(open(os.path.join(csv_dir, 'ind.csv'), encoding='utf-8-sig')):
    full = row['food_name'].strip()
    k100, p100, c100, f100 = (num(row.get(x)) for x in ('energy_kcal', 'protein_g', 'carb_g', 'fat_g'))
    if None in (k100, p100, c100, f100):
        dropped.append(f'{full}: missing per-100 g values')
        continue
    # "Hot tea (Garam Chai)": the text in brackets is another name
    m = re.match(r'^(.*?)\s*\((.*)\)\s*$', full)
    name = (m.group(1) if m else full).strip()
    bracket = split_names(re.sub(r'\s*/\s*', ';', m.group(2))) if m else []
    unit = (row.get('servings_unit') or '').strip()
    sk, sp, sc, sf = (num(row.get(f'unit_serving_{x}')) for x in ('energy_kcal', 'protein_g', 'carb_g', 'fat_g'))
    if unit and sk and sk > 0 and k100 > 0 and None not in (sp, sc, sf):
        grams = sk / k100 * 100.0
        label, kcal, prot, carb, fat = f'1 {unit}', sk, sp, sc, sf
    else:
        grams, label, kcal, prot, carb, fat = 100.0, '100 g', k100, p100, c100, f100
    add({
        'id': 'indb_' + row['food_code'].strip().lower(),
        'name': name,
        'aliases': unique_aliases(name, bracket),
        'icon': '🍲',
        'serving': label,
        'grams': r1(grams),
        'kcal': r1(kcal), 'protein': r1(prot), 'carbs': r1(carb), 'fat': r1(fat),
        'allergens': guess_allergens(name, ' '.join(bracket)),
        'meals': [], 'role': 'bulk', 'tags': [],
        'source': 'indb', 'sourceNote': (row.get('primarysource') or '').strip()[:40],
    }, full)

# ---------------------------------------------------------------- 3. USDA SR Legacy foods (already selected, with household portions)
for f in json.load(open(usda_path)):
    f = dict(f)
    f['role'] = 'bulk'
    f['source'] = 'usda'
    f.setdefault('sourceNote', 'SR Legacy')
    add(f, f['name'])

# ---------------------------------------------------------------- 4. de-duplicate (curated > Calorica > small lists > INDB > USDA by order above)
curated = json.load(open(curated_path))
curated = curated if isinstance(curated, list) else list(curated.values())[0]
taken = {}
for c in curated:
    for k in [c['name']] + c.get('aliases', []):
        taken.setdefault(norm(k), 'curated:' + c['id'])
order = {'calorica': 0, 'indb': 1, 'usda': 2}
items.sort(key=lambda i: (order[i['source']], 0 if i['id'].startswith('cal_') else 1))
final, clashes, ids = [], [], set()
for it in items:
    key = norm(it['name'])
    if key in taken:
        clashes.append(f"{it['id']} '{it['name']}' dropped: same name as {taken[key]}")
        continue
    if it['id'] in ids:
        clashes.append(f"{it['id']} dropped: duplicate id")
        continue
    ids.add(it['id'])
    taken[key] = it['id']
    final.append(it)

# ---------------------------------------------------------------- 5. energy sanity check against the Atwater factors
# INDB recipe rows whose listed energy disagrees with their own protein / carbohydrate / fat by more than 35% are internally impossible
# (e.g. a soup with 31 kcal and 9.7 g protein + 11.7 g fat per 100 g), so they are dropped. For the other sources a large gap has a known
# reason (alcohol, dietary fibre in bran, USDA's own energy factors) and the food is kept and listed.
suspicious, inconsistent = [], []
kept = []
for it in final:
    est = 4 * it['protein'] + 4 * it['carbs'] + 9 * it['fat']
    gap = abs(it['kcal'] - est) / it['kcal'] if it['kcal'] > 0 else 0
    if it['source'] == 'indb' and est > 0 and (gap > 0.35 or (it['kcal'] < 10 and est > 30)):
        inconsistent.append(f"{it['id']} {it['name']}: {it['kcal']} kcal listed, macros add up to {est:.0f}")
        continue
    kept.append(it)
    if it['kcal'] >= 40 and est > 0 and gap > 0.5:
        suspicious.append(f"{it['id']} {it['name']}: {it['kcal']} kcal listed, macros add up to {est:.0f}")
final = kept

json.dump(final, open(out_path, 'w'), ensure_ascii=False, indent=0, separators=(',', ':'))

by = collections.Counter(i['source'] for i in final)
log(f'wrote {len(final)} foods to {out_path}: {dict(by)}')
log(f'dropped for bad values: {len(dropped)}')
log('\n'.join('  ' + d for d in dropped[:40]))
log(f'dropped as duplicates of an earlier / curated food: {len(clashes)}')
log('\n'.join('  ' + d for d in clashes[:15]))
log(f'INDB rows dropped because their energy contradicts their own macros: {len(inconsistent)}')
log('\n'.join('  ' + d for d in inconsistent[:60]))
log(f'energy differs from the macros by >50% (kept; alcohol / fibre / USDA factors): {len(suspicious)}')
log('\n'.join('  ' + d for d in suspicious[:40]))
log('allergen guesses: ' + str(dict(collections.Counter(a for i in final for a in i['allergens']))))
txt = '\n'.join(report)
print(txt)
if report_path:
    open(report_path, 'w').write(txt + '\n')

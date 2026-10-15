#!/usr/bin/env python3
"""Builds the app's bulk food list from USDA FoodData Central SR Legacy (public domain, CC0 1.0).

    python3 -I build_usda_foods.py <sr_legacy.json> <curated foods.json> <output foods_usda.json>

Selection: generic (non-brand) foods from everyday categories, a quota per category, at most a few variants of the same base food.
Nutrition values are USDA's own, per 100 g, scaled to the first household portion USDA lists (or 100 g).
Allergens are NOT in the USDA data: they are guessed from the food's name and category by keyword rules that deliberately over-warn,
and every item is marked so the app says "allergens estimated from the name".
"""
import json, re, sys, collections

src, curated_path, out_path = sys.argv[1:4]
data = json.load(open(src))['SRLegacyFoods']
curated = json.load(open(curated_path))
curated = curated if isinstance(curated, list) else list(curated.values())[0]

QUOTA = {
    'Fruits and Fruit Juices': 120, 'Vegetables and Vegetable Products': 200, 'Dairy and Egg Products': 80, 'Poultry Products': 70,
    'Beef Products': 60, 'Pork Products': 40, 'Lamb, Veal, and Game Products': 30, 'Finfish and Shellfish Products': 70,
    'Legumes and Legume Products': 60, 'Cereal Grains and Pasta': 60, 'Baked Products': 70, 'Nut and Seed Products': 40,
    'Beverages': 40, 'Sweets': 40, 'Snacks': 35, 'Fats and Oils': 25, 'Breakfast Cereals': 15, 'Soups, Sauces, and Gravies': 25,
    'Sausages and Luncheon Meats': 20,
}
ICON = {
    'Fruits and Fruit Juices': '🍎', 'Vegetables and Vegetable Products': '🥦', 'Dairy and Egg Products': '🥛', 'Poultry Products': '🍗',
    'Beef Products': '🍢', 'Pork Products': '🍢', 'Lamb, Veal, and Game Products': '🍢', 'Finfish and Shellfish Products': '🐟',
    'Legumes and Legume Products': '🥣', 'Cereal Grains and Pasta': '🍚', 'Baked Products': '🍞', 'Nut and Seed Products': '🥜',
    'Beverages': '🥤', 'Sweets': '🍫', 'Snacks': '🍟', 'Fats and Oils': '🧈', 'Breakfast Cereals': '🥣', 'Soups, Sauces, and Gravies': '🍲',
    'Sausages and Luncheon Meats': '🍢',
}
# brand names and institutional / odd entries are left out
EXCLUDE = re.compile(r"\b(pillsbury|kellogg|general mills|campbell|kraft|nabisco|keebler|post|quaker|nestle|mcdonald|burger king|wendy|taco bell|"
                     r"kfc|pizza hut|subway|domino|little caesar|arby|carl|jack in|popeyes|starbucks|usda commodity|school lunch|babyfood|baby food|"
                     r"infant|formula|restaurant|oscar mayer|hormel|tyson|armour|ocean spray|snapple|gatorade|powerade|red bull|pepsi|coca|"
                     r"mountain dew|sprite|fanta|mission|pepperidge|entenmann|hostess|little debbie|girl scout|lender|bagel bites|"
                     r"heinz|hunt's|ragu|prego|knorr|lipton|maruchan|nissin|stouffer|swanson|healthy choice|lean cuisine|weight watchers|"
                     r"jimmy dean|jones|johnsonville|bob evans|smithfield|hillshire|ball park|hebrew national|nathan|ranch style)", re.I)
ODD = re.compile(r"\b(game meat|bison|beaver|bear|moose|elk|caribou|deer|antelope|squirrel|rabbit|raccoon|opossum|whale|seal|walrus|emu|ostrich|"
                 r"muktuk|oopik|agutuk|alaska native|shoshone|navajo|hopi|apache|pima|cheyenne|alcoholic|liqueur|whiskey|vodka|rum|"
                 r"school|imitation|dietetic|infant|baby|geese|goose|pheasant|quail|partridge|duck|frog|turtle|snail|crocodile|"
                 r"fish oil|liver oil|shortening|lard|tallow|cod liver|pectin|gelatin|yeast extract|spirulina)", re.I)
REMOVE = [', broilers or fryers', ', meat only', ', all grades', ', separable lean and fat', ', separable lean only', ', trimmed to 0" fat',
          ', trimmed to 1/8" fat', ', trimmed to 1/4" fat', ', choice', ', select', ', prime', ', all varieties', ', commercial', ', year round average',
          ', mature seeds', ', cooked, boiled, drained, without salt', ', cooked, boiled, drained, with salt', ', raw, includes skin', ' (includes foods for USDA\'s Food Distribution Program)']

def nutrient(food, number):
    for n in food['foodNutrients']:
        if n['nutrient'].get('number') == number and 'amount' in n:
            return n['amount']
    return None

def clean_name(desc):
    d = desc
    for r in REMOVE:
        d = d.replace(r, '')
    d = re.sub(r'\s+', ' ', d).strip(' ,')
    return d[:1].upper() + d[1:]

def singular(w):
    if w.endswith('ies') and len(w) > 4: return w[:-3] + 'y'
    if w.endswith('oes') and len(w) > 4: return w[:-2]
    if w.endswith('s') and not w.endswith('ss') and len(w) > 3: return w[:-1]
    return w

# --- allergen guesses (the USDA data has none). Over-warns on purpose.
def has(text, pattern): return re.search(pattern, text, re.I) is not None
def guess_allergens(desc, cat):
    t = desc.lower()
    out = set()
    dairy_words = r"\b(milk|cheese|yogurt|yoghurt|cream|butter|whey|casein|custard|kefir|ghee|ice cream|pudding|lactose|buttermilk|ricotta|mozzarella|cheddar|parmesan|cottage)\b"
    dairy_not = r"(peanut butter|cocoa butter|nut butter|almond butter|sunflower|apple butter|shea|butter bean|butterhead|coconut (milk|cream)|almond milk|soy milk|rice milk|oat milk|cream of tartar|soymilk|sesame butter|seed butter|margarine)"
    if has(t, dairy_words) and not has(t, dairy_not): out.add('dairy')
    if cat == 'Dairy and Egg Products' and not has(t, r"^egg|\begg\b|(coconut|soy|almond|rice|oat)"): out.add('dairy')
    if has(t, r"\begg(s)?\b|mayonnaise|meringue|omelet|omelette|custard|eggnog"): out.add('eggs')
    nut_words = r"\b(almond|walnut|cashew|pecan|pistachio|hazelnut|filbert|macadamia|brazil nut|pine nut|chestnut|peanut|nuts|praline|marzipan|mixed nut)"
    if has(t, nut_words) and not has(t, r"water chestnut|coconut|nutmeg|butternut|doughnut|donut"): out.add('nuts')
    fish_words = r"\b(salmon|tuna|cod|haddock|halibut|tilapia|trout|sardine|mackerel|herring|anchovy|anchovies|catfish|bass|pollock|snapper|swordfish|perch|flounder|sole|mahi|carp|pike|eel|bluefish|whitefish|fish|roe|caviar|pompano|mullet|grouper|orange roughy|shad|smelt|sturgeon|turbot|whiting)\b"
    if has(t, fish_words) or cat == 'Finfish and Shellfish Products': out.add('fish')
    shell_words = r"\b(shrimp|prawn|crab|lobster|crayfish|crawfish|oyster|clam|mussel|scallop|squid|octopus|abalone|snail|whelk|mollusk|crustacean|cuttlefish|conch|surimi)\b"
    if has(t, shell_words): out.add('shellfish'); out.discard('fish') if not has(t, fish_words.replace('|fish|', '|')) else None
    if has(t, r"\b(soy|soya|soybean|tofu|tempeh|miso|edamame|natto|textured vegetable)"): out.add('soy')
    if has(t, r"\b(sesame|tahini|halvah|halva|hummus)"): out.add('sesame')
    gluten_words = r"\b(wheat|bread|bun|buns|bagel|roll|rolls|pasta|noodle|noodles|macaroni|spaghetti|couscous|bulgur|semolina|farina|barley|rye|oat|oats|malt|seitan|spelt|triticale|cracker|crackers|cookie|cookies|cake|brownie|muffin|pie|pastry|donut|doughnut|croissant|waffle|pancake|biscuit|pizza|pretzel|crouton|breadcrumb|breading|tortilla|pita|flatbread|cereal|granola|lasagna|ravioli|dumpling)\b"
    if has(t, gluten_words) and not has(t, r"(rice|corn|potato|coconut|almond|soy|chickpea|tapioca|buckwheat|quinoa|millet|sorghum)\s+(flour|bread|pasta|noodle)|gluten.free|rice noodle|corn tortilla|corn flake"): out.add('gluten')
    if cat in ('Baked Products', 'Breakfast Cereals') and not has(t, r"gluten.free|rice cake|corn"): out.add('gluten')
    if cat == 'Baked Products' and has(t, r"cake|cookie|brownie|muffin|pie|pastry|donut|doughnut|croissant|waffle|pancake|biscuit|cracker"): out.update({'dairy', 'eggs'})
    if cat == 'Sweets' and has(t, r"chocolate|candy|fudge|toffee|caramel|ice|pudding|frosting|milk"): out.add('dairy')
    return sorted(out)

def portion(food):
    for p in food.get('foodPortions', []):
        g = p.get('gramWeight')
        if not g or g <= 0 or g > 600: continue
        amt = p.get('amount') or p.get('value') or 1
        mod = (p.get('modifier') or '').strip()
        unit = (p.get('measureUnit') or {}).get('name', '')
        label = mod if mod and mod != 'serving' else (unit if unit and unit != 'undetermined' else 'serving')
        if label == 'serving' and amt == 1: label = 'serving'
        a = f'{amt:g}'
        return f'{a} {label}'.strip(), round(float(g), 1)
    return '100 g', 100.0

# --- pick
by_cat = collections.defaultdict(list)
for f in data:
    cat = f['foodCategory']['description']
    if cat not in QUOTA: continue
    desc = f['description']
    if EXCLUDE.search(desc) or ODD.search(desc): continue
    if re.search(r"\b[A-Z]{3,}\b", desc.replace('USDA', '').replace('NFS', '')): continue   # BUDWEISER, OCEAN SPRAY ...: a brand
    if 28000 <= (f.get('ndbNumber') or 0) <= 29999: continue                                    # SR Legacy's branded-product range
    if re.search(r"\b\w+'s\b", desc.split(',')[0]) and cat in ('Baked Products', 'Snacks', 'Sweets', 'Beverages', 'Breakfast Cereals'): continue
    kcal = nutrient(f, '208')
    if kcal is None or nutrient(f, '203') is None or nutrient(f, '204') is None or nutrient(f, '205') is None: continue
    by_cat[cat].append(f)

curated_keys = set()
for c in curated:
    for k in [c['name']] + c.get('aliases', []): curated_keys.add(re.sub(r'[^a-z0-9]+', ' ', k.lower()).strip())

selected = []
for cat, foods in by_cat.items():
    # simpler descriptions first, raw/cooked before exotic preparations
    foods.sort(key=lambda f: (f['description'].count(','), len(f['description']), f['ndbNumber'] if isinstance(f.get('ndbNumber'), int) else 0))
    per_base = collections.Counter()
    picked = []
    for f in foods:
        depth = 2 if cat in ('Beef Products', 'Pork Products', 'Lamb, Veal, and Game Products', 'Poultry Products', 'Finfish and Shellfish Products', 'Nut and Seed Products', 'Beverages', 'Soups, Sauces, and Gravies', 'Snacks', 'Breakfast Cereals', 'Sweets') else 1
        base = ','.join(f['description'].split(',')[:depth]).lower().strip()
        if per_base[base] >= 3: continue
        name = clean_name(f['description'])
        if len(name) > 70: continue
        if re.sub(r'[^a-z0-9]+', ' ', name.lower()).strip() in curated_keys: continue
        per_base[base] += 1
        picked.append(f)
        if len(picked) >= QUOTA[cat]: break
    selected += [(cat, f) for f in picked]

out = []
for cat, f in selected:
    desc = f['description']
    name = clean_name(desc)
    kcal100 = nutrient(f, '208'); p100 = nutrient(f, '203'); fat100 = nutrient(f, '204'); carb100 = nutrient(f, '205')
    sugar = nutrient(f, '269') or 0; sodium = nutrient(f, '307') or 0
    label, grams = portion(f)
    k = grams / 100.0
    tags = []
    if sugar >= 15: tags.append('highSugar')
    if sodium >= 600: tags.append('highSodium')
    if 'fried' in desc.lower(): tags.append('fried')
    if cat == 'Sausages and Luncheon Meats': tags.append('processed')
    base = name.split(',')[0].strip().lower()
    aliases = sorted({base, singular(base)} - {name.lower()})
    out.append({
        'id': f"usda_{f['fdcId']}", 'name': name, 'aliases': aliases, 'icon': ICON[cat], 'serving': label, 'grams': grams,
        'kcal': round(kcal100 * k, 1), 'protein': round(p100 * k, 1), 'carbs': round(carb100 * k, 1), 'fat': round(fat100 * k, 1),
        'allergens': guess_allergens(desc, cat), 'meals': [], 'role': 'usda', 'tags': tags, 'source': 'usda', 'fdcId': str(f['fdcId']),
    })
out.sort(key=lambda x: x['name'].lower())
json.dump(out, open(out_path, 'w'), ensure_ascii=False, indent=0, separators=(',', ':'))
c = collections.Counter(cat for cat, _ in selected)
print(len(out), 'foods')
for k, v in c.most_common(): print(f'  {v:4d} {k}')
print('with an allergen guess:', sum(1 for o in out if o['allergens']))

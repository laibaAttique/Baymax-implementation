#!/usr/bin/env python3
"""Builds assets/data/allergen_terms.json from the Open Food Facts taxonomies (stdlib only).

Input (git-ignored, downloaded by hand): ml/data/openfoodfacts/allergens.txt and ingredients.txt, from
https://github.com/openfoodfacts/openfoodfacts-server/tree/main/taxonomies (allergens.txt and food/ingredients.txt).

What it does
  1. allergens.txt lists, for each of the EU's allergen groups, the ingredient words that belong to it.
  2. ingredients.txt is a graph of ~20,000 ingredients; 76 of them carry an `allergens:en:` property and every ingredient below them
     (cheddar below cheese below milk) inherits it. All English names of those ingredients become terms.
  3. Ingredients that contain an allergen word but are NOT that allergen (coconut milk, peanut butter, cocoa butter) are kept as
     terms with no allergens, so the matcher can see that the longer phrase wins over the shorter word.

Output terms use the same normalisation as the app (lower case, a-z and 0-9 only), so the app can look them up directly.
Allergen keys follow the app: gluten, dairy, nuts, peanuts, soy, shellfish, eggs, fish, sesame, celery, mustard, lupin, sulphites.
Peanut terms carry both `peanuts` and `nuts`, so a person who ticked "Nuts" is still warned about peanuts.
"""
import json, re, sys, collections, pathlib

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parent.parent
SRC = APP / 'ml' / 'data' / 'openfoodfacts'
OUT = APP / 'assets' / 'data' / 'allergen_terms.json'

OFF_TO_APP = {
    'en:gluten': ['gluten'], 'en:milk': ['dairy'], 'en:eggs': ['eggs'], 'en:fish': ['fish'],
    'en:crustaceans': ['shellfish'], 'en:molluscs': ['shellfish'], 'en:peanuts': ['peanuts', 'nuts'], 'en:nuts': ['nuts'],
    'en:soybeans': ['soy'], 'en:sesame-seeds': ['sesame'], 'en:celery': ['celery'], 'en:mustard': ['mustard'],
    'en:lupin': ['lupin'], 'en:sulphur-dioxide-and-sulphites': ['sulphites'],
}


def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9\s]', ' ', s.lower())).strip()


def blocks(path):
    cur = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('#'):
            continue
        if line.strip() == '':
            if cur:
                yield cur
            cur = []
        else:
            cur.append(line.rstrip())
    if cur:
        yield cur


def split_syn(v):
    return [x.strip() for x in v.split(',') if x.strip()]


terms = collections.defaultdict(set)  # normalised phrase -> allergens


def add(phrase, allergens):
    p = norm(phrase)
    if not p or len(p) < 2 or len(p.split()) > 6:
        return
    terms[p] |= set(allergens)


# ---- 1. allergens.txt -------------------------------------------------------------------------------------------------------
for b in blocks(SRC / 'allergens.txt'):
    en = next((l for l in b if l.startswith('en:')), None)
    if not en or b[0].startswith(('stopwords', 'synonyms')):
        continue
    names = split_syn(en[3:])
    tag = 'en:' + names[0].lower().replace(' ', '-')
    # the tag of an allergens.txt entry is its first English name
    key = {'gluten': 'en:gluten', 'milk': 'en:milk', 'eggs': 'en:eggs', 'fish': 'en:fish', 'crustaceans': 'en:crustaceans', 'molluscs': 'en:molluscs',
           'peanuts': 'en:peanuts', 'nuts': 'en:nuts', 'soybeans': 'en:soybeans', 'sesame seeds': 'en:sesame-seeds', 'celery': 'en:celery',
           'mustard': 'en:mustard', 'lupin': 'en:lupin', 'sulphur dioxide and sulphites': 'en:sulphur-dioxide-and-sulphites'}.get(names[0].lower())
    if key:
        for n in names:
            add(n, OFF_TO_APP[key])

# ---- 2. ingredients.txt: graph with inherited allergens -----------------------------------------------------------------------
nodes = {}        # id -> {'parents': [...], 'en': [...], 'own': set}
by_name = {}      # 'en:normalised name' -> id
order = []
for b in blocks(SRC / 'ingredients.txt'):
    if b[0].startswith(('stopwords', 'synonyms')):
        continue
    parents, langs, own = [], {}, set()
    for l in b:
        if l.startswith('<'):
            parents.append(l[1:].strip())
        elif re.match(r'^allergens:en:', l):
            own |= {x.strip() for x in l.split(':', 2)[2].split(',') if x.strip()}
        elif re.match(r'^[a-z_]{2,3}:', l) and not re.match(r'^[a-z_]+:[a-z]{2}:', l):
            code, _, rest = l.partition(':')
            langs.setdefault(code, []).extend(split_syn(rest))
    if not langs:
        continue
    first_lang = 'en' if 'en' in langs else next(iter(langs))
    nid = f'{first_lang}:{norm(langs[first_lang][0])}'
    n = nodes.setdefault(nid, {'parents': [], 'en': [], 'own': set()})
    n['parents'] += [f"{p.split(':', 1)[0]}:{norm(p.split(':', 1)[1])}" for p in parents if ':' in p]
    n['en'] += langs.get('en', [])
    n['own'] |= own
    order.append(nid)
    for name in langs.get('en', []):
        by_name.setdefault(f'en:{norm(name)}', nid)

memo = {}


def inherited(nid, seen=()):
    if nid in memo:
        return memo[nid]
    if nid in seen:
        return set()
    n = nodes.get(nid)
    if not n:
        return set()
    out = set(n['own'])
    for p in n['parents']:
        out |= inherited(by_name.get(p, p), seen + (nid,))
    memo[nid] = out
    return out


allergen_nodes = 0
for nid, n in nodes.items():
    tags = inherited(nid)
    apps = set()
    for t in tags:
        apps |= set(OFF_TO_APP.get(t, []))
    if apps:
        allergen_nodes += 1
    for name in n['en']:
        add(name, apps)

# ---- 2b. supplement written by the project team --------------------------------------------------------------------------------
# Common foods and South Asian dish words the Open Food Facts taxonomies do not list as allergen carriers. Each is a standard
# ingredient of that food (wheat in roti, milk in dahi, egg in mayonnaise); the lists err toward warning. They are counted
# separately in the output file so the app can say which part comes from Open Food Facts and which from the team.
SUPPLEMENT = {
    'eggs': ['mayonnaise', 'mayo', 'aioli', 'meringue', 'omelette', 'omelet', 'quiche', 'souffle', 'egg noodles', 'anda', 'bhurji', 'egg bhurji', 'eggnog', 'egg nog', 'custard', 'french toast'],
    'dairy': ['curd', 'dahi', 'lassi', 'raita', 'khoya', 'mawa', 'malai', 'rabri', 'kulfi', 'kheer', 'ice cream', 'yogurt', 'yoghurt', 'cheesecake', 'custard', 'milkshake', 'paneer', 'ghee', 'makhan', 'chaas', 'doodh', 'cottage cheese', 'cream cheese', 'sour cream'],
    'gluten': ['naan', 'roti', 'chapati', 'chapatti', 'paratha', 'parantha', 'puri', 'poori', 'bhatura', 'kulcha', 'samosa', 'pasta', 'spaghetti', 'macaroni', 'noodles', 'bread', 'biscuit', 'biscuits', 'cake', 'pizza', 'couscous', 'seitan', 'bulgur', 'sooji', 'suji', 'rava', 'daliya', 'dalia', 'pakora batter', 'tortilla', 'bun', 'burger bun', 'croissant', 'cracker', 'crackers', 'pastry', 'pie crust', 'dumpling', 'wonton', 'pita', 'toast', 'cereal', 'muesli', 'granola', 'beer'],
    'nuts': ['badam', 'kaju', 'pista', 'akhrot', 'chilgoza', 'marzipan', 'praline', 'nutella', 'gianduja'],
    'peanuts': ['moongphali', 'mungfali', 'peanut oil', 'monkey nut'],
    'sesame': ['til', 'gajak', 'rewri', 'revdi', 'halva', 'halwa tahini', 'hummus'],
    'fish': ['machli', 'machhi', 'worcestershire sauce', 'caesar dressing', 'surimi', 'fish fingers', 'fish fingers'],
    'shellfish': ['jhinga', 'jheenga', 'kekda', 'seafood', 'sea food', 'crab stick'],
    'soy': ['soya chunks', 'soya nuggets', 'soy chunks', 'soy milk', 'soya milk', 'soy sauce', 'natto', 'tamari', 'bean curd'],
}
supplement_count = 0
for allergen, phrases in SUPPLEMENT.items():
    for ph in phrases:
        before = set(terms.get(norm(ph), set()))
        add(ph, [allergen] + (['nuts'] if allergen == 'peanuts' else []))
        if allergen not in before:
            supplement_count += 1

# ---- 3. exclusions: ingredients that contain an allergen word but are not that allergen ----------------------------------------
# Exclusions are per allergen and deliberately narrow: a phrase that contains a dairy word but has a plant qualifier ("coconut milk",
# "almond milk", "cocoa butter", "oat milk") is not dairy. It says nothing about any other allergen (hazelnut spread is still a nut).
# Anything else that merely contains an allergen word ("milk lactose") is left to the allergen word: a missing warning is worse
# than an extra one.
PLANT = {'coconut', 'almond', 'oat', 'rice', 'soy', 'soya', 'cashew', 'hazelnut', 'cocoa', 'cacao', 'shea', 'hemp', 'flax', 'sunflower',
         'vegetable', 'plant', 'vegan', 'pea', 'peanut', 'nut', 'walnut', 'pistachio', 'macadamia', 'quinoa'}
DAIRY_WORDS = {'milk', 'butter', 'cream', 'cheese', 'yogurt', 'yoghurt'}
final = {p: sorted(a) for p, a in terms.items() if a}
not_dairy = sorted(p for p, a in terms.items() if not a and len(p.split()) > 1 and any(t in DAIRY_WORDS for t in p.split())
                   and any(t in PLANT for t in p.split()) and 'free' not in p.split() and 'dairy' not in (final.get(p) or []))
# a plant-qualified phrase that the taxonomy itself marks as a dairy product stays dairy, and anything that could hold real milk
# next to the plant word (a coating, a spread, a chocolate, "milk and hazelnut") is not excluded
MIXED = {'and', 'with', 'spread', 'coating', 'chocolate', 'flavor', 'flavour', 'filling', 'mass', 'cocoa cream', 'rice cream'}
not_dairy = [p for p in not_dairy if p not in final and not (set(p.split()) & MIXED) and p not in MIXED]
# the team's own additions: well-known phrases that contain a dairy word and are not dairy
not_dairy = sorted(set(not_dairy) | {'cream of tartar', 'butter bean', 'butter beans', 'butterfly pea', 'cream of coconut', 'cream soda', 'peanut butter', 'almond butter', 'nut butter'})

data = {
    'version': 1,
    'source': 'Open Food Facts allergens and ingredients taxonomies (openfoodfacts-server/taxonomies), English names only',
    'sourceUrl': 'https://github.com/openfoodfacts/openfoodfacts-server/tree/main/taxonomies',
    'supplementTerms': supplement_count,
    'note': 'exclusions: phrases that contain a dairy word but are not dairy (coconut milk, cocoa butter). They never cancel any other allergen.',
    'terms': dict(sorted(final.items())),
    'exclusions': {'dairy': not_dairy},
}
OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
per = collections.Counter(a for v in final.values() for a in v)
print('ingredient nodes:', len(nodes), '| nodes with an allergen (own or inherited):', allergen_nodes)
print('terms written:', len(final), '| dairy exclusions:', len(not_dairy))
print('supplement terms added by the team:', supplement_count)
print('terms per allergen:', dict(per))
print('file size:', OUT.stat().st_size, 'bytes')

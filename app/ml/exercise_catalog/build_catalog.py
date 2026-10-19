#!/usr/bin/env python3
"""Builds the Baymax exercise catalogue (Module 4 knowledge base) from free-exercise-db.

  python ml/exercise_catalog/build_catalog.py                      # from the app folder
  python ml/exercise_catalog/build_catalog.py --commit <sha> --check

Source: free-exercise-db, https://github.com/yuhonas/free-exercise-db (Unlicense / public domain). The dataset is read at a
PINNED commit, so every run produces the same catalogue; the download is cached in ml/exercise_catalog/cache/ and is only
fetched again for a different commit. The script is idempotent: records are keyed by the dataset's own `id`, sorted, and
written deterministically, so re-running it never duplicates anything.

What is kept from the dataset, unchanged (under `dataset`): id, name, force, level, mechanic, equipment, primaryMuscles,
secondaryMuscles, instructions, category, images.

What is DERIVED here (under `derived`, never mixed with dataset fields, each with its rule in `provenance`):
  group, impact, tags, joints, levelNumber, complexity, equipmentKey, timed  - team rules below, pending professional review
  movement (pattern for camera tracking)                                  - movement_patterns.py, pending review
  met                                                                      - 2024 Adult Compendium mapping (met_mapping_rules.json)
Nothing here is a medical judgement; the app's safety rules (lib/services/workout_rules/safety_rule_repository.dart) decide eligibility.

Output: assets/data/exercise_catalog.json
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import movement_patterns  # noqa: E402  (camera tracking patterns, Module 5)

DEFAULT_COMMIT = 'f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5'  # 2026-09-27, latest at import time
REPO = 'yuhonas/free-exercise-db'
DATASET_FIELDS = ['id', 'name', 'force', 'level', 'mechanic', 'equipment', 'primaryMuscles', 'secondaryMuscles',
                  'instructions', 'category', 'images']
LEVELS = {'beginner': 1, 'intermediate': 2, 'expert': 3}
HAND_SUPPORT = re.compile(r'push-?ups?\b|\bdips?\b|plank|handstand|body-up|crawl|mountain climber|burpee', re.I)
EQUIPMENT_KEYS = {
    None: 'none', 'body only': 'none', 'barbell': 'barbell', 'dumbbell': 'dumbbell', 'cable': 'cable', 'machine': 'machine',
    'kettlebells': 'kettlebell', 'bands': 'bands', 'medicine ball': 'medicine_ball', 'exercise ball': 'exercise_ball',
    'foam roll': 'foam_roller', 'e-z curl bar': 'ez_bar', 'other': 'other',
}
GROUP_BY_MUSCLE = {
    'quadriceps': 'legs', 'hamstrings': 'legs', 'glutes': 'legs', 'calves': 'legs', 'adductors': 'legs', 'abductors': 'legs',
    'chest': 'push', 'triceps': 'push', 'shoulders': 'push',
    'lats': 'back', 'middle back': 'back', 'lower back': 'back', 'traps': 'back', 'biceps': 'back', 'forearms': 'back',
    'neck': 'back', 'abdominals': 'core',
}
HIGH_IMPACT_CARDIO = re.compile(r'running|jogging|rope|sprint|skating', re.I)
LOW_IMPACT_CARDIO = re.compile(r'bicycl|bike|elliptical|rowing|stair|step mill|walking', re.I)
ICON = {'push': '💪', 'legs': '🦵', 'core': '🧘', 'cardio': '🏃', 'mobility': '🤸', 'back': '🏋️'}


def fetch(url, path):
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print(f'downloading {url}')
    with urllib.request.urlopen(url, timeout=120) as r:
        data = r.read()
    with open(path + '.part', 'wb') as f:
        f.write(data)
    os.replace(path + '.part', path)


def load_dataset(commit):
    cache = os.path.join(HERE, 'cache')
    ex = os.path.join(cache, f'exercises-{commit}.json')
    tree = os.path.join(cache, f'tree-{commit}.json')
    fetch(f'https://raw.githubusercontent.com/{REPO}/{commit}/dist/exercises.json', ex)
    fetch(f'https://api.github.com/repos/{REPO}/git/trees/{commit}?recursive=1', tree)
    with open(ex, encoding='utf-8') as f:
        records = json.load(f)
    with open(tree, encoding='utf-8') as f:
        t = json.load(f)
    if t.get('truncated'):
        sys.exit('GitHub returned a truncated file list; image paths cannot be validated.')
    files = {e['path'] for e in t['tree'] if e['type'] == 'blob'}
    return records, files


def validate(rec):
    """Returns (problems, warnings). Problems drop the record; warnings keep it with the gap recorded."""
    problems, warnings = [], []
    for f in ('id', 'name', 'category'):
        if not isinstance(rec.get(f), str) or not rec[f].strip():
            problems.append(f'missing {f}')
    if not isinstance(rec.get('instructions'), list) or not any(isinstance(s, str) and s.strip() for s in rec.get('instructions', [])):
        problems.append('no instructions')
    if not isinstance(rec.get('primaryMuscles'), list) or not rec['primaryMuscles']:
        problems.append('no primary muscle')
    if rec.get('level') not in LEVELS:
        problems.append(f'unknown level {rec.get("level")!r}')
    if rec.get('equipment') not in EQUIPMENT_KEYS:
        problems.append(f'unknown equipment {rec.get("equipment")!r}')
    for f in ('force', 'mechanic'):
        if rec.get(f) is None:
            warnings.append(f'{f} not stated')
    return problems, warnings


def match_met(rec, rules, compendium):
    name = rec['name'].lower()
    for r in rules:
        if 'category' in r and rec.get('category') not in r['category']:
            continue
        if 'equipment' in r and rec.get('equipment') not in r['equipment']:
            continue
        if 'force' in r and rec.get('force') not in r['force']:
            continue
        if 'mechanic' in r and rec.get('mechanic') not in r['mechanic']:
            continue
        if 'nameAny' in r and not any(re.search(p, name) for p in r['nameAny']):
            continue
        code = r['code']
        out = {'match': r['match'], 'rule': r['id'], 'why': r['why'], 'reviewStatus': 'pending',
               'source': '2024 Adult Compendium of Physical Activities', 'validated': None}
        if code is None:
            out.update(value=None, code=None, description=None)
        else:
            act = compendium[code]
            out.update(value=act['met'], code=code, description=act['description'], url=act['url'])
        return out
    return {'match': 'unmatched', 'rule': None, 'why': 'No mapping rule applies.', 'value': None, 'code': None,
            'description': None, 'reviewStatus': 'pending', 'source': '2024 Adult Compendium of Physical Activities', 'validated': None}


def derive(rec):
    """Team-derived planning fields. Every value says which rule produced it."""
    cat = rec['category']
    primary = [m.lower() for m in rec['primaryMuscles']]
    name = rec['name']
    prov = {}
    if cat == 'stretching':
        group, prov['group'] = 'mobility', 'category stretching'
    elif cat in ('cardio', 'plyometrics'):
        group, prov['group'] = 'cardio', f'category {cat}'
    else:
        group = GROUP_BY_MUSCLE.get(primary[0], 'core')
        prov['group'] = f'first primary muscle {primary[0]}'

    if cat == 'plyometrics':
        impact, prov['impact'] = 'high', 'category plyometrics'
    elif cat == 'cardio' and HIGH_IMPACT_CARDIO.search(name):
        impact, prov['impact'] = 'high', 'running / jumping / sprinting cardio'
    elif cat == 'cardio' and LOW_IMPACT_CARDIO.search(name):
        impact, prov['impact'] = 'low', 'machine or walking cardio'
    elif cat == 'cardio':
        impact, prov['impact'] = 'unknown', 'cardio type not recognised'
    else:
        impact, prov['impact'] = 'low', f'category {cat} without jumping'

    tags = []
    if cat == 'plyometrics':
        tags.append('plyo')
    if rec.get('force') == 'static' and cat == 'strength':
        tags.append('isometric')
    if cat in ('powerlifting', 'olympic weightlifting', 'strongman'):
        tags.append('maximal')
    if EQUIPMENT_KEYS[rec.get('equipment')] not in ('none', 'other', 'foam_roller', 'exercise_ball'):
        tags.append('externalLoad')
    prov['tags'] = 'plyo: category plyometrics; isometric: dataset force=static; maximal: lifting-sport category; externalLoad: equipment'

    joints = set()
    if any(m in ('quadriceps', 'hamstrings', 'glutes') for m in primary) and rec.get('mechanic') == 'compound':
        joints.add('knee')
    if 'calves' in primary or impact == 'high':
        joints.add('ankle')
    if impact == 'high':
        joints.add('knee')
    if any(m in ('shoulders', 'chest') for m in primary) and rec.get('force') == 'push':
        joints.add('shoulder')
    if 'lower back' in primary or (rec.get('mechanic') == 'compound' and 'hamstrings' in primary and rec.get('force') == 'pull'):
        joints.add('lowerBack')
    # Wrist: forearm work, or body weight carried on the hands (push-ups, dips, planks, crawls). The dataset has no field for
    # hand support, so the name is used here, together with the category, as the curated library does for the same movements.
    if 'forearms' in primary or (HAND_SUPPORT.search(rec['name']) and not re.search(r'squat', rec['name'], re.I)):
        joints.add('wrist')
    prov['joints'] = 'from primary muscles, mechanic, force and impact; wrist from forearm muscles or a hand-supported movement name'

    level = LEVELS[rec['level']]
    complexity = 3 if level == 3 else (2 if rec.get('mechanic') == 'compound' else 1)
    timed = cat in ('cardio', 'stretching') or 'isometric' in tags
    pattern, reason, rule = movement_patterns.classify(rec)
    movement = {'pattern': pattern, 'reason': reason, 'rule': rule}
    prov['movement'] = 'movement_patterns.py rule ' + rule
    return {
        'group': group,
        'impact': impact,
        'tags': sorted(tags),
        'joints': sorted(joints),
        'levelNumber': level,
        'complexity': complexity,
        'equipmentKey': EQUIPMENT_KEYS[rec.get('equipment')],
        'timed': timed,
        'icon': ICON[group],
        'movement': movement,
        'provenance': prov,
        'reviewStatus': 'pending',
    }


def build(commit):
    with open(os.path.join(HERE, 'met_mapping_rules.json'), encoding='utf-8') as f:
        mapping = json.load(f)
    with open(os.path.join(HERE, 'compendium_2024_subset.json'), encoding='utf-8') as f:
        comp = json.load(f)
    compendium = {a['code']: a for a in comp['activities']}
    for r in mapping['rules']:
        if r['code'] is not None and r['code'] not in compendium:
            sys.exit(f'mapping rule {r["id"]} uses Compendium code {r["code"]} that is not in compendium_2024_subset.json')
    with open(os.path.join(APP, 'assets', 'data', 'exercises.json'), encoding='utf-8') as f:
        curated = json.load(f)
    curated_by_ref = {}
    for c in curated:
        if c.get('referenceId'):
            curated_by_ref.setdefault(c['referenceId'], []).append({'id': c['id'], 'match': c.get('referenceMatch')})

    records, files = load_dataset(commit)
    out, dropped, warnings, seen = [], [], {}, set()
    bad_images = 0
    for rec in records:
        problems, warns = validate(rec)
        if rec.get('id') in seen:
            problems.append('duplicate id')
        if problems:
            dropped.append({'id': rec.get('id'), 'problems': problems})
            continue
        seen.add(rec['id'])
        images = []
        for p in rec.get('images') or []:
            if isinstance(p, str) and f'exercises/{p}' in files:
                images.append(p)
            else:
                bad_images += 1
                warns.append(f'image not in repository: {p}')
        if warns:
            warnings[rec['id']] = warns
        out.append({
            'id': rec['id'],
            'dataset': {k: rec.get(k) for k in DATASET_FIELDS},
            'imageUrls': [f'https://raw.githubusercontent.com/{REPO}/{commit}/exercises/{p}' for p in images],
            'derived': derive(rec),
            'met': match_met(rec, mapping['rules'], compendium),
            'curatedAs': curated_by_ref.get(rec['id'], []),
        })
    out.sort(key=lambda e: e['id'])

    counts = {'exact': 0, 'approximate': 0, 'unmatched': 0}
    for e in out:
        counts[e['met']['match']] += 1
    meta = {
        'dataset': 'free-exercise-db',
        'repository': f'https://github.com/{REPO}',
        'license': 'Unlicense (public domain)',
        'commit': commit,
        'built': date.today().isoformat(),
        'metSource': comp['source'],
        'metCitation': comp['citation'],
        'metMappingVersion': mapping['version'],
        'records': len(records),
        'imported': len(out),
        'dropped': dropped,
        'warnings': warnings,
        'invalidImageReferences': bad_images,
        'metMatches': counts,
        'curatedLinks': sum(1 for e in out if e['curatedAs']),
    }
    return {'meta': meta, 'exercises': out}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--commit', default=DEFAULT_COMMIT, help='free-exercise-db commit to import')
    ap.add_argument('--out', default=os.path.join(APP, 'assets', 'data', 'exercise_catalog.json'))
    ap.add_argument('--check', action='store_true', help='fail if the written catalogue would change')
    args = ap.parse_args()
    catalog = build(args.commit)
    text = json.dumps(catalog, ensure_ascii=False, indent=None, separators=(',', ':'), sort_keys=False) + '\n'
    if args.check:
        with open(args.out, encoding='utf-8') as f:
            current = json.load(f)
        current['meta'].pop('built', None)
        catalog['meta'].pop('built', None)
        if current != catalog:
            sys.exit('exercise_catalog.json is out of date; re-run build_catalog.py')
        print('exercise_catalog.json is up to date')
        return
    with open(args.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    m = catalog['meta']
    print(f"{m['imported']} of {m['records']} exercises imported ({len(m['dropped'])} dropped), "
          f"MET: {m['metMatches']}, invalid image refs: {m['invalidImageReferences']}, "
          f"linked to curated library: {m['curatedLinks']}, size {len(text) // 1024} KB")
    for d in m['dropped']:
        print('  dropped', d)


if __name__ == '__main__':
    main()

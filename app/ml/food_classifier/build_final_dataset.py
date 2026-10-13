#!/usr/bin/env python3
"""Builds the FINAL Module 7 Kaggle package: the cleaned Food-101 subset + web-scraped Pakistani dish sets.

  python build_final_dataset.py --base <extracted food_dataset_kaggle> \
      --extra kaggle_pakistani_dishes_1=<folder> --extra kaggle_pakistani_dishes_2=<folder> --out <final folder>

Why this is not just clean_images.py again
  The Kaggle "Pakistani dishes" sets are not independent photos. One set holds 765 images per dish that are
  rotated / zoomed / flipped / smeared copies of far fewer originals (visible as streaked edges). If those copies are split
  randomly, the same photo lands in training AND test and the accuracy is fake. So:
    1. every image gets a CNN fingerprint (MobileNetV2, ImageNet) computed for 8 views (4 rotations x mirror);
    2. two images are "the same picture" if their fingerprints match under any of those views (rotation/flip proof);
    3. same-picture groups are collapsed to ONE image (the un-augmented-looking one, preferring the first --extra source);
    4. the surviving unique pictures are split train / selection / test (60/20/20) so no picture exists twice anywhere;
    5. extra images that match a Food-101 image of the same food are dropped; the same picture under two different foods drops both.
  A dish is only included if enough unique pictures remain to test it fairly (--min-unique).
Nothing in the source folders is modified.
"""
import argparse
import csv
import hashlib
import json
import os
import random
import shutil
from collections import Counter, defaultdict

import numpy as np
from PIL import Image, ImageFile, ImageOps

from class_map import FOOD101, SYNONYMS, normalise

ImageFile.LOAD_TRUNCATED_IMAGES = False
EXTS = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')
MIN_SIDE, MAX_ASPECT = 96, 4.0


def resolve(name):
    key = normalise(name)
    return FOOD101.get(key) or SYNONYMS.get(key)


def load_rgb(path, size=None):
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert('RGB')
        im.load()
    return im if size is None else im.resize((size, size), Image.BILINEAR)


def embed_views(paths, cache_file):
    """(n, 8, 1280) float16 L2-normalised MobileNetV2 fingerprints: 4 rotations x (plain, mirrored). Cached by path+size."""
    from concurrent.futures import ThreadPoolExecutor
    import tensorflow as tf

    key = lambda p: f'{p}|{os.path.getsize(p)}'
    cache = {}
    if cache_file and os.path.exists(cache_file):
        z = np.load(cache_file, allow_pickle=True)
        cache = dict(zip(z['keys'].tolist(), z['emb']))
    todo = [p for p in paths if key(p) not in cache]
    print(f'fingerprints: {len(paths) - len(todo)} cached, {len(todo)} to compute')
    if todo:
        model = tf.keras.applications.MobileNetV2(include_top=False, weights='imagenet', pooling='avg', input_shape=(224, 224, 3))
        arr = lambda p: np.asarray(load_rgb(p, 224), dtype=np.float32)
        with ThreadPoolExecutor(8) as ex:
            for i in range(0, len(todo), 64):
                chunk = todo[i:i + 64]
                batch = np.stack(list(ex.map(arr, chunk)))
                views = []
                for k in range(4):
                    r = np.rot90(batch, k, axes=(1, 2))
                    views += [r, r[:, :, ::-1, :]]
                x = tf.keras.applications.mobilenet_v2.preprocess_input(np.concatenate(views).copy())
                e = model.predict(x, batch_size=128, verbose=0)
                e /= np.linalg.norm(e, axis=1, keepdims=True)
                e = e.reshape(8, len(chunk), 1280).transpose(1, 0, 2).astype(np.float16)
                for p, v in zip(chunk, e):
                    cache[key(p)] = v
                if (i // 64) % 20 == 0:
                    print(f'  {i + len(chunk)}/{len(todo)}', flush=True)
        if cache_file:
            np.savez(cache_file, keys=np.array(list(cache)), emb=np.stack(list(cache.values())))
    return np.stack([cache[key(p)] for p in paths])


def robust_sim(emb8, idx):
    """Symmetric (len(idx) x len(idx)) similarity = best cosine over the 8 views of the second image."""
    e0 = emb8[idx, 0, :].astype(np.float32)
    s = np.full((len(idx), len(idx)), -1, dtype=np.float32)
    for t in range(8):
        s = np.maximum(s, e0 @ emb8[idx, t, :].astype(np.float32).T)
    return np.maximum(s, s.T)


def cross_food_pairs(emb8, labels, thr):
    """Image pairs filed under two different foods that are the same picture (best view cosine >= thr)."""
    n = len(emb8)
    lab = np.array(labels)
    e0 = emb8[:, 0, :].astype(np.float32)
    out = set()
    for t in range(8):
        et = emb8[:, t, :].astype(np.float32)
        for lo in range(0, n, 1000):
            s = e0[lo:lo + 1000] @ et.T
            ii, jj = np.where(s >= thr)
            for a, b in zip(ii, jj):
                i = lo + int(a)
                if lab[i] != lab[b]:
                    out.add((min(i, int(b)), max(i, int(b))))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', required=True, help='extracted cleaned Food-101 package (images/, split.csv)')
    ap.add_argument('--extra', action='append', required=True, help='NAME=FOLDER with <dish>/*.jpg; earlier sources win ties')
    ap.add_argument('--out', required=True)
    ap.add_argument('--sim', type=float, default=0.75, help='average-linkage similarity cut for "same picture" within one food (best of 8 views)')
    ap.add_argument('--sim-cross', type=float, default=0.92, help='best-view similarity for the same picture filed under two different foods')
    ap.add_argument('--skip', default='omelette,french_fries', help='extra dish folders to ignore (Food-101 already has plenty)')
    ap.add_argument('--exclude', default=None, help='file with one image md5 per line (# comments ok): the whole same-picture group is dropped as a wrong-food label')
    ap.add_argument('--twin', type=float, default=0.85, help='drop validation pictures this similar to any training picture')
    ap.add_argument('--min-unique', type=int, default=100, help='unique pictures needed for a dish to be trained and tested')
    ap.add_argument('--split', default='0.6,0.2,0.2', help='train,selection,test fractions of the unique pictures')
    ap.add_argument('--max-side', type=int, default=384)
    ap.add_argument('--cache', default=None, help='npz file to cache fingerprints between runs')
    ap.add_argument('--seed', type=int, default=7)
    args = ap.parse_args()
    random.seed(args.seed)
    f_train, f_sel, f_test = [float(x) for x in args.split.split(',')]
    skip = {normalise(s) for s in args.skip.split(',') if s}
    exclude = set()
    if args.exclude:
        for line in open(args.exclude):
            line = line.split('#')[0].strip()
            if line:
                exclude.add(line.split()[0])

    # ---------------- collect extra images
    base_rows = list(csv.DictReader(open(os.path.join(args.base, 'split.csv'))))
    base_md5 = {r['md5'] for r in base_rows}
    issues = Counter()
    per_folder = defaultdict(Counter)            # (source, folder) -> counters
    unmapped, skipped = defaultdict(int), defaultdict(int)
    recs, seen = [], set(base_md5)
    for prio, spec in enumerate(args.extra):
        source, root = spec.split('=', 1)
        root = os.path.expanduser(root)
        for folder in sorted(os.listdir(root)):
            d = os.path.join(root, folder)
            if not os.path.isdir(d):
                continue
            files = [f for f in sorted(os.listdir(d)) if f.lower().endswith(EXTS)]
            if normalise(folder) in skip:
                skipped[(source, folder)] = len(files); continue
            target = resolve(folder)
            if not target:
                unmapped[(source, folder)] = len(files); continue
            for fn in files:
                p = os.path.join(d, fn)
                c = per_folder[(source, folder)]
                c['found'] += 1
                try:
                    im = load_rgb(p)
                except Exception:
                    c['unreadable'] += 1; continue
                w, h = im.size
                if min(w, h) < MIN_SIDE or max(w, h) / min(w, h) > MAX_ASPECT:
                    c['too small / odd shape'] += 1; continue
                md5 = hashlib.md5(open(p, 'rb').read()).hexdigest()
                if md5 in seen:
                    c['exact duplicate'] += 1; continue
                seen.add(md5)
                recs.append({'src': source, 'prio': prio, 'folder': folder, 'target': target, 'path': p, 'md5': md5,
                             'bpp': os.path.getsize(p) / (w * h), 'is_base': False})
    print(f'{len(recs)} valid extra images; unmapped folders: {sorted(set(f for _, f in unmapped))}')

    # Food-101 images of the same foods take part in the duplicate search (so extras copied from Food-101 are removed)
    extra_targets = {r['target'] for r in recs}
    for r in base_rows:
        if r['label'] in extra_targets:
            recs.append({'src': 'food101', 'prio': -1, 'folder': r['source_class'], 'target': r['label'],
                         'path': os.path.join(args.base, r['path']), 'md5': r['md5'], 'bpp': 0, 'is_base': True})
    emb8 = embed_views([r['path'] for r in recs], args.cache)
    labels = [r['target'] for r in recs]

    # ---------------- same-picture groups: average-linkage clustering per food (single linkage chains different photos together)
    from scipy.cluster.hierarchy import fcluster, linkage
    from scipy.spatial.distance import squareform
    gid_of = [None] * len(recs)
    groups = defaultdict(list)
    for tgt in sorted(set(labels)):
        idx = [i for i, l in enumerate(labels) if l == tgt]
        if len(idx) == 1:
            cl = np.array([1])
        else:
            d = np.clip(1 - robust_sim(emb8, idx), 0, None)
            np.fill_diagonal(d, 0)
            cl = fcluster(linkage(squareform(d, checks=False), 'average'), 1 - args.sim, 'distance')
        for i, c in zip(idx, cl):
            gid_of[i] = f'{tgt}#{int(c)}'
            groups[gid_of[i]].append(i)
    ambiguous = set()
    for i, j in cross_food_pairs(emb8, labels, args.sim_cross):
        ambiguous.add(gid_of[i]); ambiguous.add(gid_of[j])

    kept = defaultdict(list)                       # target -> list of (record, group id, group size)
    lost = Counter()
    for gid, members in groups.items():
        extra_members = [m for m in members if not recs[m]['is_base']]
        if not extra_members:
            continue
        tgt = recs[members[0]]['target']
        if any(recs[m]['is_base'] for m in members):
            lost[(tgt, 'matches a Food-101 image')] += len(extra_members); continue
        if any(recs[m]['md5'] in exclude for m in members):
            lost[(tgt, 'reviewed by hand: not this dish')] += len(extra_members); continue
        if gid in ambiguous:
            lost[(tgt, 'same picture filed under two different foods')] += len(extra_members); continue
        extra_members.sort(key=lambda m: (recs[m]['prio'], -recs[m]['bpp']))     # first source, least compressed (= least smeared)
        rep = extra_members[0]
        kept[tgt].append((rep, gid, len(extra_members)))
        lost[(tgt, 'extra copies of a picture already kept')] += len(extra_members) - 1

    # ---------------- split by unique picture, write
    out_img = os.path.join(args.out, 'images')
    os.makedirs(out_img, exist_ok=True)
    for r in base_rows:                                          # base package copied as is
        dst = os.path.join(args.out, r['path'])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(args.base, r['path']), dst)
    out_rows = [{'path': r['path'], 'label': r['label'], 'split': r['split'], 'source_class': r['source_class'], 'md5': r['md5'],
                 'source': 'food101', 'grp': '', 'half': ''} for r in base_rows]
    stats, too_few = {}, {}
    existing = Counter(r['label'] for r in base_rows)
    for tgt in sorted(kept):
        items = kept[tgt]
        if len(items) < args.min_unique:
            too_few[tgt] = len(items); continue
        random.shuffle(items)
        items.sort(key=lambda it: recs[it[0]]['prio'])          # stable: first --extra source first, random inside a source
        n = len(items)
        n_tr, n_se = int(round(n * f_train)), int(round(n * f_sel))
        n_te = n - n_tr - n_se
        os.makedirs(os.path.join(out_img, tgt), exist_ok=True)
        cnt = Counter()
        # test and selection pictures are taken from the first source (the un-augmented originals) wherever a dish has them
        parts = ['test' if k < n_te else ('select' if k < n_te + n_se else 'train') for k in range(n)]
        sim_rep = robust_sim(emb8, [m for m, _, _ in items])
        twins = {k for k in range(n) if parts[k] != 'train' and
                 max(sim_rep[k, j] for j in range(n) if parts[j] == 'train') >= args.twin}
        if twins:
            lost[(tgt, 'validation image too similar to a training image')] += len(twins)
        for k, (m, gid, size) in enumerate(items):
            part = parts[k]
            if k in twins:
                continue
            rec = recs[m]
            rel = f'images/{tgt}/p{existing[tgt] + k:04d}.jpg'
            im = load_rgb(rec['path'])
            im.thumbnail((args.max_side, args.max_side), Image.LANCZOS)
            im.save(os.path.join(args.out, rel), 'JPEG', quality=90, optimize=True)
            out_rows.append({'path': rel, 'label': tgt, 'split': 'train' if part == 'train' else 'val',
                             'source_class': f"{rec['src']}:{rec['folder']}", 'md5': rec['md5'], 'source': rec['src'],
                             'grp': f'{tgt}#{gid}', 'half': '' if part == 'train' else part})
            cnt[part] += 1
        stats[tgt] = dict(cnt)

    # Final pass on the exact pictures the model will see (the saved thumbnails; fingerprints of an original and of its
    # resized copy can differ by ~0.1): drop any validation picture that has a near-twin among the training pictures.
    new_rows = [r for r in out_rows if r['source'] != 'food101']
    if new_rows:
        e8_out = embed_views([os.path.join(args.out, r['path']) for r in new_rows], None)
        lab_out = np.array([r['label'] for r in new_rows])
        drop_paths = set()
        for tgt in sorted(set(lab_out)):
            idx = np.where(lab_out == tgt)[0]
            sim = robust_sim(e8_out, idx)
            is_tr = np.array([new_rows[i]['split'] == 'train' for i in idx])
            for a_i in np.where(~is_tr)[0]:
                if sim[a_i, is_tr].max() >= args.twin:
                    drop_paths.add(new_rows[idx[a_i]]['path'])
                    stats[tgt][new_rows[idx[a_i]]['half']] -= 1
                    lost[(tgt, 'validation image too similar to a training image')] += 1
        for pth in drop_paths:
            os.remove(os.path.join(args.out, pth))
        out_rows = [r for r in out_rows if r['path'] not in drop_paths]

    with open(os.path.join(args.out, 'split.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=['path', 'label', 'split', 'source_class', 'md5', 'source', 'grp', 'half'])
        w.writeheader(); w.writerows(out_rows)
    labels_out = sorted({r['label'] for r in out_rows})
    per_class = {}
    for r in out_rows:
        c = per_class.setdefault(r['label'], {'train': 0, 'val': 0, 'sources': set()})
        c['train' if r['split'] == 'train' else 'val'] += 1
        c['sources'].add(r['source'])
    json.dump({'labels': labels_out, 'official_split': True,
               'classes': {k: {'train': v['train'], 'val': v['val'], 'sources': sorted(v['sources'])} for k, v in per_class.items()},
               'dishes_not_included_too_few_unique_pictures': too_few}, open(os.path.join(args.out, 'labels.json'), 'w'), indent=1)

    # ---------------- preview sheets for a visual check
    os.makedirs(os.path.join(args.out, 'preview'), exist_ok=True)
    by_label = defaultdict(list)
    for r in out_rows:
        if r['source'] != 'food101':
            by_label[r['label']].append(r['path'])
    for lab, ps in by_label.items():
        random.shuffle(ps)
        sheet = Image.new('RGB', (6 * 160, 4 * 160), 'white')
        for k, p in enumerate(ps[:24]):
            im = Image.open(os.path.join(args.out, p)).convert('RGB'); im.thumbnail((158, 158))
            sheet.paste(im, ((k % 6) * 160, (k // 6) * 160))
        sheet.save(os.path.join(args.out, 'preview', f'{lab}.jpg'), quality=80)

    # ---------------- reports
    n_tr = sum(1 for r in out_rows if r['split'] == 'train')
    lines = ['# Final Module 7 dataset — build report', '',
             f'**{len(out_rows)} images in {len(labels_out)} classes — {n_tr} train / {len(out_rows) - n_tr} validation.** '
             'Food-101 images are copied from the earlier cleaned package unchanged (official split, validation halved by file hash in the notebook). '
             'Pakistani-dish images come from the web-scraped Kaggle sets below and are split **by unique picture** 60 / 20 / 20 '
             '(train / selection / test) after duplicate and augmentation-copy removal; test and selection pictures are preferably the un-augmented originals (first Kaggle set).', '',
             '## What was removed from the Kaggle sets', '',
             '| Dish folder | Source | Found | Unreadable | Too small/odd | Exact duplicates |', '|---|---|---:|---:|---:|---:|']
    for (src, folder), c in sorted(per_folder.items()):
        lines.append(f"| {folder} | {src} | {c['found']} | {c['unreadable']} | {c['too small / odd shape']} | {c['exact duplicate']} |")
    lines += ['', '| Food (catalogue id) | Reason | Images removed |', '|---|---|---:|']
    for (tgt, why), v in sorted(lost.items()):
        lines.append(f'| {tgt} | {why} | {v} |')
    lines += ['', '## Pakistani dishes in the final set (unique pictures)', '',
              '| Food (catalogue id) | Train | Selection | Test |', '|---|---:|---:|---:|']
    for tgt, c in sorted(stats.items()):
        lines.append(f"| {tgt} | {c.get('train', 0)} | {c.get('select', 0)} | {c.get('test', 0)} |")
    if too_few:
        lines += ['', f'**Not included — fewer than {args.min_unique} unique pictures left:** ' +
                  ', '.join(f'{k} ({v})' for k, v in sorted(too_few.items())) + '. Add your own photos for these.']
    lines += ['', '## Folders not used (no matching catalogue food, or skipped on purpose)', '']
    lines += [f'* {f} ({s}): {n} images — no catalogue food' for (s, f), n in sorted(unmapped.items())]
    lines += [f'* {f} ({s}): {n} images — skipped, Food-101 already covers it' for (s, f), n in sorted(skipped.items())]
    lines += ['', '## Limits you must know', '',
              f'* "Same picture" = average-linkage clusters of the best 8-view fingerprint similarity (cut {args.sim}; {args.sim_cross} across different foods). It is a heuristic: '
              'a few distinct but very similar photos may have been merged (costs images, not honesty); a heavily distorted copy could still survive.',
              '* The Pakistani images are **web photos, not phone photos**. Accuracy measured on their test split says how well the model recognises '
              'web photos of these dishes; it does not prove the same accuracy on your users\' camera. Keep your own photos for the final test.',
              '* Labels are the scrapers\' folder names and were not individually checked (see `preview/` for a sample per dish; "biryani" folders mix chicken, '
              'mutton and vegetable biryani and are all mapped to `chicken_biryani`).',
              '* Licence of the Kaggle sets is **unverified** (see ATTRIBUTION.md).']
    open(os.path.join(args.out, 'cleaning_report.md'), 'w').write('\n'.join(lines) + '\n')
    open(os.path.join(args.out, 'ATTRIBUTION.md'), 'w').write(
        '# Sources\n\n'
        '* **Food-101** (Bossard, Guillaumin, Van Gool; ETH Zurich) — https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/ . '
        'Via a Kaggle copy ("foodarchive"). The images come from foodspotting.com; the authors state they are not owned by the dataset authors.\n'
        '* **Kaggle "Pakistani Dishes Dataset"** — https://www.kaggle.com/datasets/useractivated/dataset (two folders: `dataset/` and '
        '`pakistani_dishes_dataset_2/`). **Licence not verified.** The images appear to be scraped from the web (watermarks and recipe-site '
        'captions are visible), so the original image owners\' rights may apply. Check the "License" box on the Kaggle page before the trained '
        'model or this package is shared outside the team. Do not publish this package in the public GitHub repository.\n')
    print('\n'.join(lines[:4]))
    print('Pakistani dishes:', {k: sum(v.values()) for k, v in stats.items()}, '| too few:', too_few)
    print('removed:', dict(lost))


if __name__ == '__main__':
    main()

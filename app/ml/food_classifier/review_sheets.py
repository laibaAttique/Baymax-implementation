#!/usr/bin/env python3
"""Numbered contact sheets of the web-sourced images of one dish, for checking labels by eye.

  python review_sheets.py <final package folder> <catalogue_id> <out folder>

Writes <out>/<id>_<k>.jpg (24 images per sheet, each captioned with its number) and <out>/<id>_index.csv (number -> md5).
Write the numbers of images that are NOT this dish into a list, look up their md5 in the index and put them in the
exclude file for build_final_dataset.py --exclude.
"""
import csv
import os
import sys

from PIL import Image, ImageDraw

pkg, dish, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
rows = [r for r in csv.DictReader(open(os.path.join(pkg, 'split.csv'))) if r['label'] == dish and r['source'] != 'food101']
rows.sort(key=lambda r: r['path'])
with open(os.path.join(out, f'{dish}_index.csv'), 'w', newline='') as fh:
    w = csv.writer(fh); w.writerow(['number', 'md5', 'path', 'split', 'source'])
    for i, r in enumerate(rows):
        w.writerow([i, r['md5'], r['path'], r['split'], r['source']])
CELL = 200
for sheet_no, lo in enumerate(range(0, len(rows), 24)):
    sheet = Image.new('RGB', (6 * CELL, 4 * CELL), 'white')
    dr = ImageDraw.Draw(sheet)
    for k, r in enumerate(rows[lo:lo + 24]):
        im = Image.open(os.path.join(pkg, r['path'])).convert('RGB')
        im.thumbnail((CELL - 4, CELL - 4))
        x, y = (k % 6) * CELL, (k // 6) * CELL
        sheet.paste(im, (x + 2, y + 2))
        dr.rectangle([x, y, x + 34, y + 16], fill='black')
        dr.text((x + 3, y + 2), str(lo + k), fill='yellow')
    sheet.save(os.path.join(out, f'{dish}_{sheet_no}.jpg'), quality=82)
print(len(rows), 'images,', (len(rows) + 23) // 24, 'sheets ->', out)

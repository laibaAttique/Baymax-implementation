"""Summarises the on-device photo validation log (integration_test/dataset_pose_validation_test.dart).

  python ml/validation/summarize_photo_validation.py <log> docs/review/photo_validation.json

Reads the "[val] {...}" lines, writes per-exercise results and per-pattern rates to JSON, and prints a Markdown table.
"""
import collections
import json
import sys

log, out = sys.argv[1], sys.argv[2]
rows = []
for line in open(log, encoding='utf-8', errors='replace'):
    i = line.find('[val] ')
    if i >= 0:
        rows.append(json.loads(line[i + 6:]))

by = collections.defaultdict(list)
for r in rows:
    by[r['pattern']].append(r)


def rate(n, d):
    return None if d == 0 else round(100 * n / d)


patterns = {}
for p, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    n = len(rs)
    detected = sum(1 for r in rs if all(r['detected']))
    measurable = [r for r in rs if all(r.get('measurable', [False]))]
    hold = any('inPosition' in r for r in rs)
    span = sum(1 for r in measurable if r.get('span'))
    counted = sum(1 for r in measurable if r.get('repCounted'))
    in_pos = sum(1 for r in measurable if any(r.get('inPosition', [])))
    alarms = collections.Counter(a for r in measurable for a in r.get('falseAlarms', []))
    na = collections.Counter(a for r in measurable for a in r.get('notApplicable', []))
    patterns[p] = {
        'exercises': n,
        'personDetectedBothPhotos': rate(detected, n),
        'landmarksMeasurable': rate(len(measurable), n),
        'measurableCount': len(measurable),
        'repSpan': None if hold else rate(span, len(measurable)),
        'repCounted': None if hold else rate(counted, len(measurable)),
        'holdInPosition': rate(in_pos, len(measurable)) if hold else None,
        'falseAlarmsByCheck': {k: rate(v, len(measurable)) for k, v in alarms.items()},
        'notApplicableByCheck': {k: rate(v, len(measurable)) for k, v in na.items()},
    }

json.dump({'exercises': rows, 'patterns': patterns}, open(out, 'w', encoding='utf-8'), indent=1)
print('| Pattern | Exercises | Person detected | Landmarks measurable | Rep span / in position | Rep counted | False alarms on correct form |')
print('|---|---|---|---|---|---|---|')
for p, s in patterns.items():
    alarms = ', '.join(f'{k} {v}%' for k, v in sorted(s['falseAlarmsByCheck'].items())) or 'none'
    span = f"{s['holdInPosition']}% in position" if s['holdInPosition'] is not None else f"{s['repSpan']}%"
    counted = '—' if s['repCounted'] is None else f"{s['repCounted']}%"
    print(f"| {p} | {s['exercises']} | {s['personDetectedBothPhotos']}% | {s['landmarksMeasurable']}% ({s['measurableCount']}) | {span} | {counted} | {alarms} |")
print(f'\nexercises: {len(rows)}')

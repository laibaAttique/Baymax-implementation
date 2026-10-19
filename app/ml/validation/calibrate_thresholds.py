"""Suggests per-pattern thresholds from REAL poses (calibration half only).

  python ml/validation/calibrate_thresholds.py build/real_pose_measures.json [device log]

Rep thresholds: the rest threshold is moved so ~85 % of real rest photos count as "at rest", the turning-point
threshold so ~85 % of real end photos count as "reached", keeping a hysteresis gap. Check thresholds are relaxed only
as far as needed for ~90 % of correctly demonstrated photos to pass, and never past a cap (so a check keeps meaning).
Only pairs with a visible movement (>= 20° between the photos) are used. The output is a suggestion; the values are
copied into lib/services/posture/movement_patterns.dart by hand and checked on the held-out half by
test/real_pose_replay_test.dart.
"""
import collections
import json
import sys

rows = [r for r in json.load(open(sys.argv[1], encoding='utf-8')) if r['split'] == 'calibration' and 'rest' in r]
device = {}
if len(sys.argv) > 2:
    for line in open(sys.argv[2], encoding='utf-8', errors='replace'):
        i = line.find('[val] ')
        if i >= 0:
            r = json.loads(line[i + 6:])
            if r.get('angles'):
                device[r['id']] = r['angles']


def pct(values, q):
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    return v[min(len(v) - 1, max(0, round(q * (len(v) - 1))))]


by = collections.defaultdict(list)
for r in rows:
    if abs(r['rest']['primary'] - r['turn']['primary']) >= 20:
        by[r['pattern']].append(r)

for p, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    rest = [r['rest']['primary'] for r in rs]
    turn = [r['turn']['primary'] for r in rs]
    opening = sum(t > r for r, t in zip(rest, turn)) > len(rs) / 2
    print(f'== {p}  pairs={len(rs)}  {"opening" if opening else "closing"}')
    if opening:
        print(f'   rest angle p85={pct(rest, .85):.0f} (rest <=)   turn p15={pct(turn, .15):.0f} (peak >=)')
    else:
        print(f'   rest angle p15={pct(rest, .15):.0f} (rest >=)   turn p85={pct(turn, .85):.0f} (peak <=)')
    sway = [r['sway'] for r in rs]
    both = lambda k: [r['rest'][k] for r in rs] + [r['turn'][k] for r in rs]
    print(f'   sway p90={pct(sway, .9)}  lean p90={pct(both("lean"), .9)}  upperArm p90={pct(both("upperArm"), .9)}  '
          f'elbow p10={pct(both("elbow"), .1)}  knee p10={pct(both("knee"), .1)} turnKnee p10={pct([r["turn"]["knee"] for r in rs], .1)}  '
          f'asym p90={pct(both("asym"), .9)}  kneeRatio p10={pct(both("kneeRatio"), .1)}  hipOffset p10/p90={pct(both("hipOffset"), .1)}/{pct(both("hipOffset"), .9)}')
    dev = [device[r['id']] for r in rs if r['id'] in device]
    if dev:
        lo = [min(a) for a in dev]
        hi = [max(a) for a in dev]
        print(f'   device angles: low p85={pct(lo, .85)} high p15={pct(hi, .15)} (n={len(dev)})')

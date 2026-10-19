"""Converts `flutter test --reporter json` output into JUnit XML (one <testsuite> per test file).

  python tools/flutter_json_to_junit.py results/flutter_m456_reporter.json results/flutter_m456_junit.xml
"""
import json
import sys
from collections import OrderedDict
from xml.sax.saxutils import escape, quoteattr

src, dst = sys.argv[1], sys.argv[2]
suites, tests, groups = {}, {}, {}
done = OrderedDict()
for line in open(src, encoding='utf-8', errors='replace'):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get('type')
    if t == 'suite':
        suites[e['suite']['id']] = e['suite']['path'].replace('\\', '/').split('/app/')[-1]
    elif t == 'testStart':
        tests[e['test']['id']] = e['test']
    elif t == 'error':
        tests.setdefault(e['testID'], {}).setdefault('errors', []).append(e['error'])
    elif t == 'testDone' and not e.get('hidden'):
        done[e['testID']] = e

by_suite = OrderedDict()
for tid, e in done.items():
    by_suite.setdefault(suites.get(tests[tid]['suiteID'], '?'), []).append((tests[tid], e))
out = ['<?xml version="1.0" encoding="UTF-8"?>']
total = sum(len(v) for v in by_suite.values())
fails = sum(1 for v in by_suite.values() for _, e in v if e['result'] != 'success')
skips = sum(1 for v in by_suite.values() for _, e in v if e['skipped'])
out.append(f'<testsuites tests="{total}" failures="{fails}" skipped="{skips}">')
for path, items in by_suite.items():
    f = sum(1 for _, e in items if e['result'] != 'success')
    s = sum(1 for _, e in items if e['skipped'])
    out.append(f'  <testsuite name={quoteattr(path)} tests="{len(items)}" failures="{f}" skipped="{s}">')
    for t, e in items:
        dur = (e['time'] - t.get('time', e['time'])) / 1000
        out.append(f'    <testcase classname={quoteattr(path)} name={quoteattr(t["name"])} time="{dur:.3f}">')
        if e['skipped']:
            out.append('      <skipped/>')
        elif e['result'] != 'success':
            msg = '\n'.join(t.get('errors', []))
            out.append(f'      <failure message={quoteattr(msg[:200])}>{escape(msg)}</failure>')
        out.append('    </testcase>')
    out.append('  </testsuite>')
out.append('</testsuites>')
open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print(f'{total} tests, {fails} failures, {skips} skipped -> {dst}')

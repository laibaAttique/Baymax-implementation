"""Converts a real-device run's device_results.json (Flutter integration_test reportData) into JUnit XML.
This is a format conversion for CI/report tools; the tests are Flutter integration_test, not Java JUnit.
  python tools/device_results_to_junit.py device_evidence/<run>
"""
import json
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

run = Path(sys.argv[1])
cases = json.loads((run / 'device_results.json').read_text(encoding='utf-8'))['cases']
fails = sum(c['status'] == 'Failed' for c in cases)
skips = sum(c['status'] == 'Blocked' for c in cases)
out = ['<?xml version="1.0" encoding="UTF-8"?>', f'<testsuites tests="{len(cases)}" failures="{fails}" skipped="{skips}">',
       f'  <testsuite name={quoteattr(run.name)} tests="{len(cases)}" failures="{fails}" skipped="{skips}">']
for c in cases:
    out.append(f'    <testcase classname={quoteattr(c["file"])} name={quoteattr(c["test"])} time="{c["durationMs"] / 1000:.3f}">')
    if c['status'] == 'Failed':
        out.append(f'      <failure message={quoteattr(c["actual"][:200])}/>')
    elif c['status'] == 'Blocked':
        out.append(f'      <skipped message={quoteattr(c["actual"][:300])}/>')
    out.append(f'      <system-out>{json.dumps(c, ensure_ascii=False).replace("&", "&amp;").replace("<", "&lt;")}</system-out>')
    out.append('    </testcase>')
out += ['  </testsuite>', '</testsuites>']
(run / 'device_junit.xml').write_text('\n'.join(out) + '\n', encoding='utf-8')
print(f'{run.name}: {len(cases)} cases, {fails} failed, {skips} blocked -> device_junit.xml')

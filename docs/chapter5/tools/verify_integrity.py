"""Checks that the completed Chapter 5 keeps every element of the original unchanged and in order.

Allowed differences: the count cells of Table 5.1 (original body element 2) and Table 5.31 (element 232). Everything else in the original
must appear byte-for-byte (as XML) in the new document, in the same relative order. Writes results/integrity_report.json.
"""
import hashlib
import json
import re
from pathlib import Path

import docx
from docx.table import Table
from docx.text.paragraph import Paragraph
from lxml import etree

HERE = Path(__file__).resolve().parent.parent
ORIG = HERE / 'Baymax_Chapter5_Test_Cases.original.docx'
NEW = HERE / 'Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx'
DOWNLOADS = Path.home() / 'Downloads' / 'Baymax_Chapter5_Test_Cases.docx'
ALLOWED = {2: {(1, 2), (1, 3), (1, 5), (2, 2), (2, 3), (2, 5), (3, 2), (3, 3), (3, 5), (4, 2), (4, 3), (4, 5), (5, 2), (5, 3), (5, 5)},
           232: {(1, 1), (1, 2), (4, 1), (4, 2)}}

od, nd = docx.Document(str(ORIG)), docx.Document(str(NEW))
oe, ne = list(od.element.body.iterchildren()), list(nd.element.body.iterchildren())
xml = lambda e: etree.tostring(e, encoding='unicode')
nx = [xml(e) for e in ne]

report = {'original_elements': len(oe), 'new_elements': len(ne), 'problems': []}
pos = 0
matched = []
for i, e in enumerate(oe):
    if i in ALLOWED:
        # find the next table and compare all cells except the allowed count cells
        while pos < len(ne) and not ne[pos].tag.endswith('}tbl'):
            pos += 1
        ot, nt = Table(e, od), Table(ne[pos], nd)
        diffs = []
        for r, (orow, nrow) in enumerate(zip(ot.rows, nt.rows)):
            for c, (oc, nc) in enumerate(zip(orow.cells, nrow.cells)):
                if oc.text != nc.text:
                    diffs.append({'row': r, 'col': c, 'old': oc.text, 'new': nc.text})
                    if (r, c) not in ALLOWED[i]:
                        report['problems'].append(f'element {i}: cell {r},{c} changed outside the allowed count cells')
        if len(ot.rows) != len(nt.rows):
            report['problems'].append(f'element {i}: row count changed')
        report[f'changed_cells_element_{i}'] = diffs
        matched.append(pos)
        pos += 1
        continue
    x = xml(e)
    try:
        j = nx.index(x, pos)
    except ValueError:
        report['problems'].append(f'original element {i} not found unchanged after new position {pos}')
        continue
    matched.append(j)
    pos = j + 1
report['original_elements_found_in_order'] = len(matched)

def texts(d):
    out = []
    for e in d.element.body.iterchildren():
        if e.tag.endswith('}p'):
            out.append(Paragraph(e, d).text)
        elif e.tag.endswith('}tbl'):
            out.extend(c.text for r in Table(e, d).rows for c in r.cells)
    return '\n'.join(out)

ot, ntx = texts(od), texts(nd)
oids, nids = set(re.findall(r'ATC-[A-Z0-9]+-[A-Z]*\d+', ot)), set(re.findall(r'ATC-[A-Z0-9]+-[A-Z]*\d+', ntx))
report['original_test_ids'] = len(oids)
report['original_test_ids_missing'] = sorted(oids - nids)
report['new_test_ids'] = sorted(nids - oids)
caps = [Paragraph(e, nd).text for e in ne if e.tag.endswith('}p') and Paragraph(e, nd).style.name == 'Caption']
nums = [m.group(1) for c in caps for m in [re.match(r'Table 5\.(\d+)', c)] if m]
report['table_numbers'] = nums
dup = sorted({n for n in nums if nums.count(n) > 1}, key=int)
if dup:
    report['problems'].append(f'duplicate table numbers: {dup}')
ocaps = [Paragraph(e, od).text for e in oe if e.tag.endswith('}p') and Paragraph(e, od).style.name in ('Caption', 'Heading 1', 'Heading 2', 'Heading 3')]
ncaps = [Paragraph(e, nd).text for e in ne if e.tag.endswith('}p') and Paragraph(e, nd).style.name in ('Caption', 'Heading 1', 'Heading 2', 'Heading 3')]
it = iter(ncaps)
if not all(any(c == n for n in it) for c in ocaps):
    report['problems'].append('original headings/captions not preserved in order')
results = [json.loads(l)['id'] for l in (HERE / 'results' / 'atc_m456.jsonl').read_text(encoding='utf-8').splitlines()]
report['recorded_cases_missing_from_doc'] = [i for i in results if i not in nids]
if report['recorded_cases_missing_from_doc'] or report['original_test_ids_missing']:
    report['problems'].append('test ids missing')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report['original_copy_sha256'] = sha(ORIG)
if DOWNLOADS.exists():
    report['downloads_original_sha256'] = sha(DOWNLOADS)
    report['downloads_original_unchanged'] = sha(DOWNLOADS) == sha(ORIG)
    if not report['downloads_original_unchanged']:
        report['problems'].append('the original in Downloads differs from the reference copy')
report['ok'] = not report['problems']
(HERE / 'results' / 'integrity_report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({k: v for k, v in report.items() if k not in ('table_numbers', 'new_test_ids')}, indent=1, ensure_ascii=False)[:3000])
print('tables:', nums[0], '...', nums[-1], 'count', len(nums), '| new ids', len(report['new_test_ids']))

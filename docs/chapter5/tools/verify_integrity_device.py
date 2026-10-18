"""Integrity check of the completed Chapter 5 against the team's merged base (base_Baymax_Chapter5complete_Test_Cases.docx).

Every body element of the base must appear unchanged (as XML) and in the same order in the new document, except the count cells of
Table 5.1 and Table 5.31. Also checks: all base test IDs kept, new IDs unique, no duplicate table/figure numbers, Table 5.1 and 5.31
arithmetic, the Downloads copy unchanged. Writes results/integrity_report.json.
"""
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

import docx
from docx.table import Table
from docx.text.paragraph import Paragraph
from lxml import etree

HERE = Path(__file__).resolve().parent.parent
BASE = HERE / 'base_Baymax_Chapter5complete_Test_Cases.docx'
NEW = HERE / 'Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx'
DOWNLOADS = Path.home() / 'Downloads' / 'Baymax_Chapter5complete_Test_Cases.docx'

bd, nd = docx.Document(str(BASE)), docx.Document(str(NEW))
be, ne = list(bd.element.body.iterchildren()), list(nd.element.body.iterchildren())
xml = lambda e: etree.tostring(e, encoding='unicode')
nx = [xml(e) for e in ne]
txt = lambda e, d: Paragraph(e, d).text if e.tag.endswith('}p') else None

def table_after(elems, d, caption):
    k = next(i for i, e in enumerate(elems) if txt(e, d) == caption)
    while not elems[k].tag.endswith('}tbl'):
        k += 1
    return k

allowed = {table_after(be, bd, 'Table 5.1  Summary of the automated test cases'): ({1, 2, 3, 4, 5}, {2, 3, 4, 5}),
           table_after(be, bd, 'Table 5.31  Execution results (from the latest run)'): ({1, 4}, {1, 2, 3, 4})}
rep = {'base_elements': len(be), 'new_elements': len(ne), 'problems': [], 'changed_cells': []}
pos = 0
found = 0
for i, e in enumerate(be):
    if i in allowed:
        while not ne[pos].tag.endswith('}tbl'):
            pos += 1
        rows_ok, cols_ok = allowed[i]
        ot, nt = Table(e, bd), Table(ne[pos], nd)
        if len(ot.rows) != len(nt.rows):
            rep['problems'].append(f'base element {i}: row count changed')
        for r, (orow, nrow) in enumerate(zip(ot.rows, nt.rows)):
            for c, (oc, nc) in enumerate(zip(orow.cells, nrow.cells)):
                if oc.text != nc.text:
                    rep['changed_cells'].append({'table': txt(be[i - 1], bd), 'row': r, 'col': c, 'old': oc.text, 'new': nc.text})
                    if r not in rows_ok or c not in cols_ok or not nc.text.isdigit():
                        rep['problems'].append(f'base element {i}: cell {r},{c} changed outside the count cells')
        found += 1
        pos += 1
        continue
    try:
        j = nx.index(xml(e), pos)
    except ValueError:
        rep['problems'].append(f'base element {i} ({(txt(e, bd) or "table")[:60]}) not found unchanged after position {pos}')
        continue
    found += 1
    pos = j + 1
rep['base_elements_found_in_order'] = found

# Table 5.1 arithmetic: column sums equal the Total row; passed + failed + not run = cases.
t51 = Table(ne[table_after(ne, nd, 'Table 5.1  Summary of the automated test cases')], nd)
vals = [[c.text for c in r.cells] for r in t51.rows]
for c in (2, 3, 4, 5):
    if sum(int(vals[r][c]) for r in range(1, 5)) != int(vals[5][c]):
        rep['problems'].append(f'Table 5.1 column {c} does not add up')
for r in range(1, 6):
    if int(vals[r][3]) + int(vals[r][4]) + int(vals[r][5]) != int(vals[r][2]):
        rep['problems'].append(f'Table 5.1 row {r}: passed + failed + not run != cases')
t531 = Table(ne[table_after(ne, nd, 'Table 5.31  Execution results (from the latest run)')], nd)
v31 = [[c.text for c in r.cells] for r in t531.rows]
for c in (1, 2, 3, 4):
    if sum(int(v31[r][c]) for r in range(1, 4)) != int(v31[4][c]):
        rep['problems'].append(f'Table 5.31 column {c} does not add up')
rep['table_5_1'] = vals
rep['table_5_31'] = v31

def alltext(d):
    out = []
    for e in d.element.body.iterchildren():
        if e.tag.endswith('}p'):
            out.append(Paragraph(e, d).text)
        elif e.tag.endswith('}tbl'):
            out.extend(c.text for r in Table(e, d).rows for c in r.cells)
    return '\n'.join(out)

idre = r'ATC-[A-Z0-9]+-[A-Z0-9]*-?[A-Z]*\d+'
bids, nids = set(re.findall(idre, alltext(bd))), set(re.findall(idre, alltext(nd)))
rep['base_test_ids'] = len(bids)
rep['base_test_ids_missing'] = sorted(bids - nids)
new_ids = sorted(nids - bids)
rep['new_test_ids'] = new_ids
# A new ID must be listed exactly once in each section table it belongs to; check the new device cases are unique there.
dev_rows = []
for e in ne:
    if e.tag.endswith('}tbl'):
        for r in Table(e, nd).rows:
            cells = [c.text for c in r.cells]
            if len(cells) == 7 and cells[1].startswith('ATC-DEV'):
                dev_rows.append(cells[1])
dups = [k for k, v in Counter(dev_rows).items() if v > 1]
if dups:
    rep['problems'].append(f'device case IDs listed twice in section tables: {dups}')
caps = [Paragraph(e, nd).text for e in ne if e.tag.endswith('}p') and Paragraph(e, nd).style.name == 'Caption']
tnums = [m.group(1) for c in caps for m in [re.match(r'Table 5\.(\d+)\s', c)] if m]
fnums = [m.group(1) for c in caps for m in [re.match(r'Figure 5\.(\d+)', c)] if m]
for kind, nums in (('table', tnums), ('figure', fnums)):
    d2 = sorted({n for n in nums if nums.count(n) > 1}, key=int)
    if d2:
        rep['problems'].append(f'duplicate {kind} numbers: {d2}')
rep['table_numbers'] = f'{len(tnums)} captions, 5.{min(map(int, tnums))}–5.{max(map(int, tnums))}'
rep['figure_numbers'] = fnums
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
rep['base_sha256'] = sha(BASE)
if DOWNLOADS.exists():
    rep['downloads_base_unchanged'] = sha(DOWNLOADS) == sha(BASE)
    if not rep['downloads_base_unchanged']:
        rep['problems'].append('the base document in Downloads differs from the reference copy')
rep['ok'] = not rep['problems']
(HERE / 'results' / 'integrity_report.json').write_text(json.dumps(rep, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({k: v for k, v in rep.items() if k not in ('new_test_ids', 'table_5_1', 'table_5_31', 'changed_cells')}, indent=1, ensure_ascii=False))
print('changed cells:', len(rep['changed_cells']), '| new ids:', len(new_ids))

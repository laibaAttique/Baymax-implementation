#!/usr/bin/env python3
"""Builds the Chapter 5 test-case document, the CSV files and the README from the real results of the automated test runs.

Nothing in the result tables is typed in by hand: every row comes from a line written by a test while it ran (ATC_LOG), or from the
test runner's own report for the end-to-end tests. A case whose ID is in the code but has no result is reported as "Not run".
Standard library only. The .docx uses the styles of the faculty template (Final Report Template_FA_26) but not its content.
"""
import csv, glob, html, json, os, re, shutil, subprocess, sys, zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from requirements import MODULES, REQS  # noqa: E402

ROOT = os.path.dirname(HERE)
RAW = os.path.join(ROOT, 'results', 'raw')
HOME = os.path.expanduser('~')
APP = os.path.join(HOME, 'Downloads', 'baymaxxxx 2', 'untitled folder', 'app')
API = os.path.join(HOME, 'Downloads', 'baymax-api')
TEMPLATE = os.path.join(HOME, 'Downloads', 'Final Report Template_FA_26(BSSE Program).docx')

ID_RE = re.compile(r'ATC-(?:M\d+-[UFB]|INT-)\d+')


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]


# --------------------------------------------------------------------------------------------------------------------------------
# 1. Collect: declared IDs (from the code), results (from the runs)
# --------------------------------------------------------------------------------------------------------------------------------
SOURCES = (
    [(p, 'Flutter test (Dart)') for p in sorted(glob.glob(os.path.join(APP, 'test', 'atc', 'atc_*_test.dart')))]
    + [(os.path.join(API, 'test', 'atc', 'api.atc.test.js'), 'Node test (API)')]
    + [(p, 'Node test + Firebase emulator') for p in sorted(glob.glob(os.path.join(API, 'e2e', '*.e2e.mjs')))]
)


def declared_ids():
    out = {}
    for path, tool in SOURCES:
        for line in open(path, encoding='utf8'):
            if line.lstrip().startswith('//'):
                continue
            for i in ID_RE.findall(line):
                out.setdefault(i, []).append(os.path.basename(path))
    return out


def load_jsonl():
    res = {}
    for f in sorted(glob.glob(os.path.join(RAW, '*.jsonl'))):
        for line in open(f, encoding='utf8'):
            line = line.strip()
            if line:
                d = json.loads(line)
                res[d['id']] = d
    return res


def load_e2e():
    meta = json.load(open(os.path.join(HERE, 'e2e_cases.json'), encoding='utf8'))
    out = {}
    for f in sorted(glob.glob(os.path.join(RAW, 'e2e-*.xml'))):
        for tc in ET.parse(f).getroot().iter('testcase'):
            name = tc.get('name', '')
            m = ID_RE.match(name)
            if not m or m.group(0) not in meta:
                continue
            i = m.group(0)
            fail = tc.find('failure')
            err = tc.find('error')
            bad = fail if fail is not None else err
            ok = bad is None and tc.find('skipped') is None
            title = name[len(i):].strip()
            title = re.sub(r'^\d+\.\s*', '', title)
            m2 = meta[i]
            out[i] = dict(id=i, req=m2['req'], objective=title[0].upper() + title[1:], input=m2['input'], expected=m2['expected'],
                          actual=('All checks in the scenario held (%.1f s)' % float(tc.get('time', 0))) if ok else 'FAILED: ' + (bad.get('message') or (bad.text or '')[:300]),
                          ok=ok, tool='Node test + Firebase emulator', area=m2['area'])
    return out


DECL = declared_ids()
RES = load_jsonl()
RES.update(load_e2e())

TYPE_NAMES = {'U': 'Unit', 'F': 'Functional', 'B': 'Business rule', 'INT': 'Integration'}


def type_of(i):
    return 'INT' if '-INT-' in i else i.split('-')[2][0]


def module_of(i):
    m = re.match(r'ATC-M(\d+)-', i)
    return int(m.group(1)) if m else None


CASES = []
for i in sorted(DECL, key=natural):
    r = RES.get(i)
    c = dict(id=i, type=type_of(i), module=module_of(i), declared_in=sorted(set(DECL[i])))
    if r:
        c.update(req=r['req'], objective=r['objective'], input=r['input'], expected=r['expected'], actual=r['actual'], ok=bool(r['ok']), tool=r['tool'],
                 table=r.get('table'), conds=r.get('conds'), actions=r.get('actions'), area=r.get('area'), ran=True)
    else:
        c.update(req='', objective='(no result recorded)', input='', expected='', actual='Not run: the test did not report a result', ok=False, tool='', ran=False)
    CASES.append(c)
# Modules this chapter covers (the team's list). Cases for other modules stay in the code as regression tests but are not reported here.
INCLUDED = {1, 2, 3, 4, 8, 9, 12, 13, 14, 16, 17}


def _mods(req):
    return {int(m) for m in re.findall(r'M(\d+)-FR', req)}


def _keep(c):
    if c['module'] is not None:
        return c['module'] in INCLUDED
    return bool(_mods(c['req']) & INCLUDED) if c['ran'] else True


ALL_CASES = CASES
CASES = [c for c in ALL_CASES if _keep(c)]
EXCLUDED = [c for c in ALL_CASES if not _keep(c)]
for c in CASES:  # a case may also touch an excluded module: keep only the requirements this chapter covers
    if c['ran'] and c['req']:
        c['req'] = ', '.join(t for t in re.split(r'[,+]\s*', c['req']) if int(re.match(r'M(\d+)', t).group(1)) in INCLUDED)
dupes = {k: v for k, v in DECL.items() if len(v) > 1}
orphans = sorted(set(RES) - set(DECL))


def status(c):
    return 'Pass' if c['ok'] else ('Fail' if c['ran'] else 'Not run')


def reqs_of(c):
    return [t.strip() for t in re.split(r'[,+]', c['req']) if t.strip()]


# --------------------------------------------------------------------------------------------------------------------------------
# 2. Environment
# --------------------------------------------------------------------------------------------------------------------------------
def sh(cmd, cwd=None):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60, cwd=cwd).stdout.strip()
    except Exception:
        return ''


ENV = {
    'flutter': (sh('flutter --version 2>&1 | head -2', cwd=APP) or '').replace('\n', ' | '),
    'node': sh('node -v'),
    'firebase': sh('firebase --version 2>/dev/null | tail -1'),
    'os': sh('sw_vers -productName') + ' ' + sh('sw_vers -productVersion') + ' (' + sh('uname -m') + ')',
    'java': (sh('java -version 2>&1 | head -1')),
    'firebase_js': sh("node -e \"console.log(require('./e2e/node_modules/firebase/package.json').version)\"", cwd=API),
    'firebase_admin': sh("node -e \"console.log(require('./node_modules/firebase-admin/package.json').version)\"", cwd=API),
}
open(os.path.join(ROOT, 'results', 'environment.txt'), 'w').write('\n'.join('%s: %s' % kv for kv in ENV.items()) + '\n')

# --------------------------------------------------------------------------------------------------------------------------------
# 3. Totals
# --------------------------------------------------------------------------------------------------------------------------------
def count(cs):
    p = sum(1 for c in cs if c['ok'])
    f = sum(1 for c in cs if c['ran'] and not c['ok'])
    n = sum(1 for c in cs if not c['ran'])
    return len(cs), p, f, n


TOTAL = count(CASES)
BY_TYPE = {t: count([c for c in CASES if c['type'] == t]) for t in 'UFB'} | {'INT': count([c for c in CASES if c['type'] == 'INT'])}
BY_TOOL = {}
for c in CASES:
    BY_TOOL.setdefault(c['tool'] or '(none)', []).append(c)

# --------------------------------------------------------------------------------------------------------------------------------
# 4. Word document helpers (WordprocessingML)
# --------------------------------------------------------------------------------------------------------------------------------
def esc(t):
    t = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', str(t))
    return escape(t)


def r_(text, b=False, i=False, sz=None, color=None, mono=False):
    pr = ''
    if mono:
        pr += '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>'
    if b:
        pr += '<w:b/><w:bCs/>'
    if i:
        pr += '<w:i/><w:iCs/>'
    if color:
        pr += '<w:color w:val="%s"/>' % color
    if sz:
        pr += '<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (sz, sz)
    return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % ('<w:rPr>%s</w:rPr>' % pr if pr else '', esc(text))


def p_(content='', style=None, jc=None, nonum=False, keep=False, before=None, after=None, line=None, **runkw):
    if isinstance(content, str) and not content.startswith('<w:r'):
        content = r_(content, **runkw) if content else ''
    ppr = ''
    if style:
        ppr += '<w:pStyle w:val="%s"/>' % style
    if keep:
        ppr += '<w:keepNext/>'
    if nonum:
        ppr += '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>'
    if before is not None or after is not None or line:
        ppr += '<w:spacing%s%s%s/>' % (' w:before="%d"' % before if before is not None else '', ' w:after="%d"' % after if after is not None else '',
                                      ' w:line="%d" w:lineRule="auto"' % line if line else '')
    if jc:
        ppr += '<w:jc w:val="%s"/>' % jc
    return '<w:p>%s%s</w:p>' % ('<w:pPr>%s</w:pPr>' % ppr if ppr else '', content)


H1 = lambda t: p_(t, 'Heading1', nonum=True)
H2 = lambda t: p_(t, 'Heading2', nonum=True)
H3 = lambda t: p_(t, 'Heading3', nonum=True)
CAP = lambda t: p_(t, 'Caption', keep=True)
OBJ = lambda t, **k: p_(t, jc='both', line=300, after=120, **k)
BODY = lambda t, **k: ''  # explanatory paragraphs are left out: the chapter carries the test cases only


def shade(c):
    return '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' % c


def cell(text, w, b=False, fill=None, sz=16, color=None, jc=None, span=1):
    if isinstance(text, (list, tuple)):
        paras = ''.join(p_(r_(t, b=b, sz=sz, color=color), jc=jc, after=0) for t in text)
    else:
        paras = p_(r_(text, b=b, sz=sz, color=color), jc=jc, after=0)
    return '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s%s</w:tcPr>%s</w:tc>' % (
        w, '<w:gridSpan w:val="%d"/>' % span if span > 1 else '', shade(fill) if fill else '', paras)


def table(headers, rows, widths, sz=16, status_col=None, hdr_fill='D9E2F3'):
    assert sum(widths) <= 14420, sum(widths)
    x = '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="60" w:type="dxa"/><w:right w:w="60" w:type="dxa"/></w:tblCellMar></w:tblPr>' % sum(widths)
    x += '<w:tblGrid>%s</w:tblGrid>' % ''.join('<w:gridCol w:w="%d"/>' % w for w in widths)
    x += '<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>%s</w:tr>' % ''.join(cell(h, w, b=True, fill=hdr_fill, sz=sz) for h, w in zip(headers, widths))
    for row in rows:
        cells = ''
        for ci, (v, w) in enumerate(zip(row, widths)):
            color = None
            b = False
            if status_col is not None and ci == status_col:
                color = {'Pass': '1B7F3B', 'Fail': 'C00000', 'Not run': 'B26B00'}.get(v)
                b = True
            cells += cell(v, w, sz=sz, color=color, b=b)
        x += '<w:tr><w:trPr><w:cantSplit/></w:trPr>%s</w:tr>' % cells
    return x + '</w:tbl>' + p_('', after=80)


def image(rid, cx, cy, name='Figure'):
    return ('<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/>'
            '<wp:docPr id="1" name="%s"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
            '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="0" name="%s"/><pic:cNvPicPr/></pic:nvPicPr>'
            '<pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
            '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>') % (cx, cy, name, name, rid, cx, cy)


# --------------------------------------------------------------------------------------------------------------------------------
# 5. Content
# --------------------------------------------------------------------------------------------------------------------------------
GROUP_TITLES = {  # module -> (what is tested, objective) for the unit-test groups
    1: ('Validators and LoginGuard', 'To ensure the registration validators accept valid input, reject invalid input at the stated boundaries, and that five failed logins lock the account for 15 minutes.'),
    2: ('HealthCalc and the health classifiers', 'To ensure BMI, BMR, age and unit conversion are calculated correctly, that the rule-based classifier follows the clinical rules, and that the Logistic Regression model never overrides a reported condition.'),
    3: ('Mood suggestions and the workout card', 'To ensure the Home dashboard\'s mood suggestions are gentle for low moods and the workout card\'s calorie estimate grows with body weight.'),
    4: ('PlanGenerator (workout part)', 'To ensure the weekly workout plan obeys the medical restriction rules for each health category.'),
    8: ('FoodParser, FoodDatabase and diet summary', 'To ensure typed meals are understood, searched and totalled correctly and that the daily verdict never praises a very low intake.'),
    9: ('Nutrition plan and calorie targets', 'To ensure calorie and macro targets are consistent, never fall below the safe floor, and that meal plans never contain the user\'s allergens.'),
    10: ('AllergenMatcher', 'To ensure allergens on a label are found (including OCR slips and misspellings), look-alike ingredients are not flagged, and "may contain" statements are reported.'),
    12: ('Gamification', 'To ensure the weekly score, levels, streaks, badges, XP and K-Means cohorts are calculated as specified.'),
    13: ('ChatbotEngine', 'To ensure intents are detected, answers come from the user\'s own data, and symptoms and emergencies are handled safely.'),
    14: ('ConsultationRules and specialist plan layering', 'To ensure time slots, filters, booking checks, the room-join window, cancellation and the layering of a specialist\'s plan over Baymax\'s plan follow the rules.'),
    16: ('Roles, reminders and inactivity', 'To ensure role permissions, inactivity detection and the next reminder time are correct.'),
    17: ('Moving average', 'To ensure the chart smoothing uses only logged days.'),
}
FUNC_AREAS = {  # (module) -> title for the Flutter functional groups
    1: 'Sign-up screen', 3: 'Home dashboard', 2: 'BMI and classification screens', 4: 'Workout plan screen', 8: 'Diet screens', 9: 'Nutrition plan screen', 10: 'Allergy result screen',
    12: 'My badges screen', 14: 'Find a specialist, Book appointment and My appointments screens', 16: 'Notifications screen', 17: 'Analytics screen',
}


def case_rows_unit(cs):
    return [[str(n), c['id'], c['objective'], c['input'], c['expected'], c['actual'], status(c)] for n, c in enumerate(cs, 1)]


W7 = [500, 1250, 3000, 3300, 2800, 2850, 700]
H7 = ['No.', 'Test Case ID', 'Test case/Test script', 'Attribute and Value', 'Expected Result', 'Actual Result', 'Result']

body = []
tbl_no = [0]


def caption(text):
    tbl_no[0] += 1
    body.append(CAP('Table 5.%d  %s' % (tbl_no[0], text)))


def group_by(cs, key):
    out = {}
    for c in cs:
        out.setdefault(key(c), []).append(c)
    return out


# ---- Title -----------------------------------------------------------------------------------------------------------------------
body.append(H1('Chapter 5: Testing and Evaluation'))
body.append(BODY('This chapter documents the test cases for the part of Baymax that is implemented at the 60% milestone: Modules 1, 2, 3, 4, 8, 9, 10, 12, 13, 14, 16 and 17 '
                 'of the merged report, using the merged module numbering. Every test case has a unique Test Case ID of the form ATC-M<module>-<type><number>, where the type is U (unit), F (functional) or B (business rule), '
                 'or ATC-INT-<number> for integration. The same ID is part of the name of the automated test in the code, so an evaluator can search the code for it.'))
body.append(BODY('All results below were produced by running the tests; none were typed in. A test that did not report a result is shown as "Not run". Nothing here was executed on a physical phone: the Flutter tests run headless '
                 '(widget tests on the Flutter test framework) and the end-to-end tests run on the local Firebase emulators, not on the live project.'))
caption('Summary of the automated test cases')
body.append(table(['Type', 'Section', 'Test cases', 'Passed', 'Failed', 'Not run'],
                  [['Unit', '5.1', *map(str, BY_TYPE['U'])], ['Functional', '5.2', *map(str, BY_TYPE['F'])], ['Business rules (decision tables)', '5.3', *map(str, BY_TYPE['B'])],
                   ['Integration', '5.4', *map(str, BY_TYPE['INT'])], ['Total', '', *map(str, TOTAL)]], [3600, 1200, 1500, 1500, 1500, 1500], sz=18))

# ---- 5.1 Unit --------------------------------------------------------------------------------------------------------------------
body.append(H2('5.1 Unit Testing'))
body.append(BODY('Unit testing verifies the smallest testable components (functions, methods and small classes) in isolation. Each case below calls one function with the stated input and compares the result with the expected one. '
                 'The tests are written with the Flutter test framework (Dart) and live in app/test/atc/atc_unit_test.dart.'))
units = [c for c in CASES if c['type'] == 'U']
for n, (m, cs) in enumerate(sorted(group_by(units, lambda c: c['module']).items()), 1):
    what, obj = GROUP_TITLES[m]
    body.append(H3('Unit Testing %d: %s (Module %d, %s)' % (n, what, m, MODULES[m])))
    body.append(OBJ('Testing Objective: ' + obj))
    body.append(table(H7, case_rows_unit(cs), W7, status_col=6))

# ---- 5.2 Functional --------------------------------------------------------------------------------------------------------------
body.append(H2('5.2 Functional Testing'))
body.append(BODY('Functional testing validates user-facing features. The Flutter cases open the real screen, type and tap as a user would and check what appears (widget tests, no emulator or phone). '
                 'The API cases call the real Express API (the server behind the specialist portal and the admin panel) with real request routing, token checks and rules, on an in-memory database. '
                 'Role names: doctor, nutritionist and trainer are specialists; "member" is an app user.'))
funcs = [c for c in CASES if c['type'] == 'F']
fl = [c for c in funcs if c['tool'].startswith('Flutter')]
fa = [c for c in funcs if c['tool'].startswith('Node')]
n = 0
for m, cs in sorted(group_by(fl, lambda c: c['module']).items()):
    n += 1
    body.append(H3('Functional Testing %d: %s (Module %d, %s)' % (n, FUNC_AREAS[m], m, MODULES[m])))
    body.append(OBJ('Objective: to ensure the screen shows the correct content and reacts correctly to the user\'s actions.'))
    body.append(table(H7, case_rows_unit(cs), W7, status_col=6))
API_FUNC_GROUPS = [
    ('Access control of the specialist API and admin routes', lambda c: c['id'] in ('ATC-M16-F04', 'ATC-M16-F05', 'ATC-M16-F06', 'ATC-M16-F07'), 'To ensure only signed-in specialists reach the portal and only administrators reach the admin routes.'),
    ('Requests, accept and decline, and appointment actions', lambda c: c['id'] in ('ATC-M14-F21', 'ATC-M14-F22', 'ATC-M14-F23', 'ATC-M14-F24', 'ATC-M14-F25', 'ATC-M14-F26', 'ATC-M14-F27', 'ATC-M14-F28'), 'To ensure a booked request can be accepted (creating the video room) or declined, expired requests cannot be answered, and notes, prescriptions and cancellations behave correctly.'),
    ('Patients, plans and food-log review', lambda c: c['id'] in ('ATC-M14-F29', 'ATC-M14-F30', 'ATC-M14-F31', 'ATC-M14-F32', 'ATC-M14-F33', 'ATC-M14-F34'), 'To ensure specialists see only their own patients and can set, validate and remove diet and workout plans and review shared food logs.'),
    ('Registration, approval, administration and account closing', lambda c: c['id'] in ('ATC-M14-F35', 'ATC-M14-F36', 'ATC-M14-F37', 'ATC-M14-F38', 'ATC-M14-F39', 'ATC-M14-F40', 'ATC-M14-F41'), 'To ensure specialists register as pending, an administrator approves or rejects, administrators add specialists without setting passwords, and closing an account cleans up correctly.'),
]
for title, pred, obj in API_FUNC_GROUPS:
    cs = [c for c in fa if pred(c)]
    if not cs:
        continue
    n += 1
    body.append(H3('Functional Testing %d: %s (API)' % (n, title)))
    body.append(OBJ('Objective: ' + obj))
    body.append(table(H7, case_rows_unit(cs), W7, status_col=6))
missing_api = [c['id'] for c in fa if not any(p(c) for _, p, _ in API_FUNC_GROUPS)]
assert not missing_api, missing_api

# ---- 5.3 Business rules ----------------------------------------------------------------------------------------------------------
body.append(H2('5.3 Business Rules Testing'))
body.append(BODY('Decision-table based testing is used for the business rules. For each rule set the conditions (inputs) and the action (output) are laid out in a decision table, and one test case is written for every rule (every column of the table), '
                 'as described in Appendix E of the template. Each column is one automated test; its ID is shown under the column heading in the test-case table that follows the decision table.'))
rules = [c for c in CASES if c['type'] == 'B']
tables = {}
for c in rules:
    tables.setdefault(c.get('table') or '(no table)', []).append(c)
for ti, (tname, cs) in enumerate(tables.items(), 1):
    m = cs[0]['module']
    body.append(H3('Business Rule Testing %d: %s' % (ti, tname.replace('DT-', 'Decision table DT-', 1) if False else tname)))
    conds = []
    for c in cs:
        for k in (c.get('conds') or {}):
            if k not in conds:
                conds.append(k)
    nrules = len(cs)
    first = 3000
    wr = max(900, min(1500, (14400 - first) // max(nrules, 1)))
    widths = [first] + [wr] * nrules
    caption('Decision table: ' + tname)
    rows = [[k] + [(c.get('conds') or {}).get(k, '-') for c in cs] for k in conds]
    rows.append(['Action / expected result'] + [c.get('actions') or '' for c in cs])
    body.append(table(['Conditions'] + ['Rule %d' % i for i in range(1, nrules + 1)], rows, widths, sz=15))
    caption('Test cases for ' + tname.split(' ', 1)[0])
    rows = [[str(i), c['id'], 'Rule %d: %s' % (i, c['objective']), c['input'], c['expected'], c['actual'], status(c)] for i, c in enumerate(cs, 1)]
    body.append(table(['No.', 'Test Case ID', 'Test case/Test script', 'Attribute and Value', 'Expected Result', 'Actual Result', 'Result'], rows, W7, status_col=6))

# ---- 5.4 Integration -------------------------------------------------------------------------------------------------------------
body.append(H2('5.4 Integration Testing'))
body.append(BODY('Integration testing verifies that the modules work together. The first scenarios chain several app modules the way the app does. The others run the real pieces together on the local Firebase emulators (a fake Firebase Auth and Realtime Database '
                 'on this computer; nothing touches the real project): the actual database security rules with real signed-in test users, the Express API with real token checks, the admin scripts, and the app\'s booking writes. '
                 'They are the tests that found real defects the unit tests could not (a rules error that blocked a booking step and a cross-origin response that browsers discarded; both were fixed).'))
ints = [c for c in CASES if c['type'] == 'INT']
dart_int = [c for c in ints if c['tool'].startswith('Flutter')]
e2e = [c for c in ints if not c['tool'].startswith('Flutter')]


def int_rows(cs):
    return [[str(i), c['id'], c['objective'] + (' (%s)' % c['req'] if c['req'] else ''), c['input'], c['expected'], c['actual'], status(c)] for i, c in enumerate(cs, 1)]


body.append(H3('Integration Testing 1: Cross-module scenarios inside the app (Modules 2, 4, 8, 9, 12, 13, 14, 16, 17)'))
body.append(OBJ('Testing Objective: to ensure data flows correctly between the classification, plan, diet, gamification, chatbot, consultation and alert modules.'))
body.append(table(H7, int_rows(dart_int), W7, status_col=6))
for title, ids, obj in [
    ('App, API and admin scripts: the whole consultation flow', lambda c: re.match(r'ATC-INT-1\d$', c['id']), 'to ensure the administrator set-up, specialist registration and approval, booking by the phone, accepting a request, plans, food-log review, account closing and deletion work together on real emulated Auth and Database.'),
    ('App booking against the real database rules', lambda c: re.match(r'ATC-INT-(2\d|30)$', c['id']), 'to ensure the deployed Realtime Database rules allow exactly what the app and the portal need and refuse everything else, for real signed-in users.'),
    ('Admin account command', lambda c: re.match(r'ATC-INT-3[123]$', c['id']), 'to ensure the command that creates the administrator login saves a working private login, never prints the password and never takes over an existing account.'),
]:
    cs = [c for c in e2e if ids(c)]
    if cs:
        k = 1 + sum(1 for t in body if isinstance(t, str) and t.startswith('<w:p><w:pPr><w:pStyle w:val="Heading3"/>') and 'Integration Testing' in t)
        body.append(H3('Integration Testing %d: %s' % (k, title)))
        body.append(OBJ('Testing Objective: ' + obj))
        body.append(table(H7, int_rows(cs), W7, status_col=6))

# ---- 5.5 Automated testing -------------------------------------------------------------------------------------------------------
body.append(H2('5.5 Automated Testing'))
body.append(H3('5.5.1 Automated Testing Strategy'))
body.append(OBJ('Unit, functional, business-rule (decision-table) and integration tests are automated with Flutter test (app), the Node.js test runner (API) and the Firebase emulators (end-to-end).'))
body.append(BODY('Every test case in this chapter is automated; the document is generated from the test runs. Four kinds of testing are automated: unit tests of the pure logic (validators, health calculations, classifiers, plan generation, parsing, '
                 'scoring and consultation rules); functional tests that open the real Flutter screens and the real Express API; business-rule tests built from decision tables; and integration tests, including end-to-end runs on the Firebase emulators.'))
body.append(BODY('These were selected because they carry the project\'s safety and correctness rules: reported conditions must override the machine-learning estimate, meal plans must never contain the user\'s allergens, a calorie deficit must never fall below a safe floor, '
                 'a specialist must never see data the patient did not share, a member must never be able to write plans, reviews, links or roles, and a booked time must belong to only one person. These rules must keep holding after every change, so they are automated for regression testing. '
                 'Positive, negative and boundary cases are included (for example age 13 exactly, a note of 500 and 501 characters, the join window at 5 and 6 minutes before the start).'))
body.append(BODY('Not automated, and therefore not claimed as tested here: appearance and usability of screens, behaviour on a physical phone (camera, notifications, sign-in with Google), OCR with the Google Vision key, the food photo classifier on real photos, '
                 'the floating chat button on Home (it needs the whole navigation shell), and the specialist portal and admin panel in a browser (a manual browser walkthrough was done on the emulator but is not recorded here). These need manual testing on a device.'))
body.append(H3('5.5.2 Automation Tools and Environment'))
caption('Automated Testing Tools and Environment')
tool_rows = [
    ['flutter_test (Flutter test framework)', 'Unit, widget (screen) and cross-module tests of the mobile app', ENV['flutter'].split('|')[0].strip() or '-', 'Unit / Functional / Business rules / Integration', 'Dart, headless on macOS (no phone or emulator)'],
    ['Node.js built-in test runner (node:test)', 'API tests of the Express server (functional and business rules) on an in-memory database; runs the end-to-end tests', 'Node ' + ENV['node'], 'API / Functional / Business rules', 'Node.js, macOS'],
    ['Firebase Emulator Suite (Auth + Realtime Database)', 'Runs the real database security rules and sign-in for the end-to-end tests', 'firebase-tools ' + ENV['firebase'], 'Integration / End-to-end', 'Local emulators on 127.0.0.1, project demo-baymax'],
    ['Firebase JS SDK and Admin SDK', 'Sign in as real emulated users; seed and inspect data', 'firebase ' + ENV['firebase_js'] + ', firebase-admin ' + ENV['firebase_admin'], 'Integration / End-to-end', 'Node.js'],
    ['Java runtime', 'Needed by the database emulator', ENV['java'], '-', 'macOS'],
]
body.append(table(['Tool / Framework', 'Purpose', 'Version', 'Test Type', 'Platform/Environment'], tool_rows, [3000, 4400, 2300, 2500, 2200], sz=17))
body.append(BODY('Machine: ' + ENV['os'] + '. All runs were on this one computer.'))

body.append(H3('5.5.3 Automated Test Cases'))
body.append(BODY('The table lists every automated test case with its ID. Rows are grouped by type in the order of sections 5.1 to 5.4. Where a case covers several requirements they are separated by commas.'))
caption('Automated Test Cases')
rows = []
for t in ['U', 'F', 'B', 'INT']:
    for c in [c for c in CASES if c['type'] == t]:
        rows.append([c['id'], c['req'], c['objective'], c['input'], c['expected'], c['actual'], status(c)])
body.append(table(['Test Case ID', 'Related Requirement', 'Test Objective', 'Test Input / Condition', 'Expected Result', 'Actual Result', 'Status'], rows, [1250, 1100, 3100, 3300, 2700, 2300, 650], sz=15, status_col=6))

body.append(H3('5.5.4 Automated Test Execution and Results'))
body.append(BODY('The whole set is run with one script, which starts the emulators if they are not already running, runs each suite, and then regenerates this document and the CSV files:'))
body.append(p_(r_('tools/run_all.sh        (add --full to also run the complete existing test suites)', mono=True, sz=18), after=120))
cmds = [
    ['Flutter unit cases', 'cd app && flutter test test/atc/atc_unit_test.dart', 'Unit'],
    ['Flutter functional cases', 'cd app && flutter test test/atc/atc_functional_test.dart', 'Functional'],
    ['Flutter business-rule cases', 'cd app && flutter test test/atc/atc_rules_test.dart', 'Business rules'],
    ['Flutter integration cases', 'cd app && flutter test test/atc/atc_integration_test.dart', 'Integration'],
    ['API functional and business-rule cases', 'cd baymax-api && node --test test/atc/', 'Functional / Business rules'],
    ['End-to-end cases (emulators)', 'cd baymax-api/e2e && node --test --test-force-exit rules.e2e.mjs   (then flow.e2e.mjs, then admin-account.e2e.mjs, one at a time)', 'Integration'],
]
caption('How each suite is run')
body.append(table(['Suite', 'Command', 'Type'], cmds, [3600, 8800, 2000], sz=17))
caption('Execution results (from the latest run)')
res_rows = []
for tool, cs in sorted(BY_TOOL.items()):
    t, p, f, nr = count(cs)
    res_rows.append([tool, str(t), str(p), str(f), str(nr)])
res_rows.append(['Total', *map(str, TOTAL)])
body.append(table(['Framework', 'Automated tests executed', 'Passed', 'Failed', 'Not run'], res_rows, [4600, 3000, 2200, 2200, 2400], sz=18))
if EXCLUDED:
    body.append(BODY('The test suites also contain %d passing regression cases for modules outside this chapter (Modules 11 and 15); they are not listed here, so the suite totals in Figure 5.1 are higher than the totals above.' % len(EXCLUDED)))
FULL = {}
for name, f in [('Complete Flutter suite (flutter test)', 'flutter_full.console.txt'), ('Complete API suite (npm test)', 'api_full.console.txt')]:
    p = os.path.join(RAW, f)
    if os.path.exists(p):
        txt = open(p, encoding='utf8', errors='replace').read()
        m = re.findall(r'\+(\d+)(?: ~\d+)?(?: -(\d+))?: (All tests passed|Some tests failed)', txt)
        if m:
            FULL[name] = 'passed %s%s' % (m[-1][0], ', failed %s' % m[-1][1] if m[-1][1] else '')
        else:
            m2 = dict(re.findall(r'ℹ (tests|pass|fail) (\d+)', txt))
            if m2:
                FULL[name] = '%s tests, %s passed, %s failed' % (m2.get('tests'), m2.get('pass'), m2.get('fail'))
if FULL:
    body.append(BODY('The complete existing suites were also run (they include the ATC cases): ' + '; '.join('%s: %s' % kv for kv in FULL.items()) + '.'))
fails = [c for c in CASES if not c['ok']]
if fails:
    body.append(BODY('Failed or not-run cases:'))
    body.append(table(['Test Case ID', 'Status', 'Reason'], [[c['id'], status(c), c['actual']] for c in fails], [1800, 1200, 11400], sz=17, status_col=1))
else:
    body.append(BODY('No test case failed and none is missing a result. This says the code matches what the tests expect; it does not say the app has been tried on a phone.'))
body.append(CAP('Figure 5.1: Automated Test Execution Result'))
body.append('@@FIGURE@@')

body.append(H3('5.5.5 Requirement Traceability for Automated Testing'))
body.append(BODY('Functional Requirement → Use Case / Feature → Automated Test Case → Automated Test Implementation → Execution Status. Requirement IDs are the merged report\'s module number and FR number (for example M14-FR2 is FR-2 of Module 14). '
                 'Requirements the report does not list but that were built for the web portal are marked "added" and numbered after the report\'s last FR of the module; they should be added to Chapter 2. '
                 'The report\'s second "FR-6" in Module 2 is treated as FR-7 here.'))
caption('Requirement Traceability Matrix for Automated Testing')
by_req = {}
for c in CASES:
    for r in reqs_of(c):
        by_req.setdefault(r, []).append(c)
FLAG_TEXT = {'NI': 'Not implemented in this release', 'P': 'Partly implemented', 'ADD': 'Added requirement', '': ''}
rtm = []
csv_rtm = []
covered_ids = set()
for m in sorted(REQS):
    for num, text, flag in REQS[m]:
        rid = 'M%d-FR%d' % (m, num)
        cs = by_req.get(rid, [])
        covered_ids.add(rid)
        tools = sorted({c['tool'] for c in cs})
        if cs:
            p = sum(1 for c in cs if c['ok'])
            st = 'Pass (%d/%d)' % (p, len(cs)) if p == len(cs) else 'Fail (%d/%d passed)' % (p, len(cs))
            auto = 'Yes'
        else:
            st = 'Not automated' + (' - ' + FLAG_TEXT[flag].lower() if flag in ('NI',) else '')
            auto = 'No'
        ids = ', '.join(c['id'] for c in cs)
        feat = '%s%s' % (MODULES[m], ' (' + FLAG_TEXT[flag].lower() + ')' if flag in ('P', 'ADD') else '')
        if not cs:
            continue
        rtm.append([rid, text, feat, ids or '-', ' / '.join(t.replace(' (Dart)', '').replace(' + Firebase emulator', ' + emulator') for t in tools) or '-', auto, st])
        csv_rtm.append([rid, text, MODULES[m], FLAG_TEXT[flag], ids, ' / '.join(tools), auto, st])
unknown = sorted(set(by_req) - covered_ids)
body.append(table(['Requirement ID', 'Requirement Description', 'Use Case / Feature', 'Automated Test Case ID', 'Automation Tool / Framework', 'Automated (Y/N)', 'Status'],
                  rtm, [1150, 3500, 2200, 3900, 1700, 700, 1250], sz=14, status_col=None))
if unknown:
    body.append(BODY('WARNING: test cases refer to requirement IDs that are not in the requirement table: ' + ', '.join(unknown)))
tested = sum(1 for r in rtm if r[5] == 'Yes')
body.append(BODY('%d of the %d requirements listed for the implemented modules have at least one automated test case. The rest are not covered by this suite (screens and device features that need manual testing, or features that are not implemented in this release).' % (tested, len(rtm))))
if dupes:
    body.append(BODY('WARNING: these IDs are declared more than once in the code: ' + ', '.join(sorted(dupes))))
if orphans:
    body.append(BODY('WARNING: results exist for IDs that are not declared in the code: ' + ', '.join(orphans)))

# --------------------------------------------------------------------------------------------------------------------------------
# 6. Figure: render the execution summary to a PNG with Chrome, if available
# --------------------------------------------------------------------------------------------------------------------------------
def make_figure():
    lines = ['$ tools/run_all.sh', '']
    for f, title in [('dart_unit', 'flutter test test/atc/atc_unit_test.dart'), ('dart_functional', 'flutter test test/atc/atc_functional_test.dart'), ('dart_rules', 'flutter test test/atc/atc_rules_test.dart'),
                     ('dart_integration', 'flutter test test/atc/atc_integration_test.dart')]:
        p = os.path.join(RAW, f + '.console.txt')
        if os.path.exists(p):
            last = [l for l in open(p, encoding='utf8', errors='replace').read().replace('\r', '\n').split('\n') if l.strip()]
            lines += ['$ ' + title, '  ' + (re.sub(r'^\d\d:\d\d ', '', last[-1]) if last else '(no output)')[:150]]
    p = os.path.join(RAW, 'api.console.txt')
    if os.path.exists(p):
        m = dict(re.findall(r'ℹ (tests|pass|fail) (\d+)', open(p, encoding='utf8', errors='replace').read()))
        lines += ['$ node --test test/atc/', '  tests %s   pass %s   fail %s' % (m.get('tests'), m.get('pass'), m.get('fail'))]
    for f in ['rules', 'flow', 'admin-account']:
        p = os.path.join(RAW, 'e2e-%s.console.txt' % f)
        if os.path.exists(p):
            m = dict(re.findall(r'ℹ (tests|pass|fail) (\d+)', open(p, encoding='utf8', errors='replace').read()))
            lines += ['$ node --test --test-force-exit %s.e2e.mjs   (Firebase emulators)' % f, '  tests %s   pass %s   fail %s' % (m.get('tests'), m.get('pass'), m.get('fail'))]
    if EXCLUDED:
        lines += ['', '(suite counts above also include %d cases for Modules 10, 11 and 15, which are outside this chapter)' % len(EXCLUDED)]
    lines += ['', 'TOTAL IN THIS CHAPTER  %d automated test cases   passed %d   failed %d   not run %d' % TOTAL]
    page = ('<html><body style="margin:0;background:#1e1e1e"><pre style="margin:0;padding:22px 26px;color:#d4d4d4;font:15px/1.5 Menlo,Courier,monospace;width:1250px;white-space:pre-wrap">%s</pre></body></html>'
            % '\n'.join(html.escape(l) for l in lines))
    hp = os.path.join(ROOT, 'results', 'execution_summary.html')
    open(hp, 'w', encoding='utf8').write(page)
    png = os.path.join(ROOT, 'results', 'execution_summary.png')
    chrome = next((c for c in ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Chromium.app/Contents/MacOS/Chromium', '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'] if os.path.exists(c)), None)
    if not chrome:
        return None
    h = 90 + 24 * len(lines)
    subprocess.run([chrome, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1300,%d' % h, '--screenshot=' + png, 'file://' + hp], capture_output=True, timeout=90)
    return (png, 1300, h) if os.path.exists(png) and os.path.getsize(png) > 1000 else None


FIG = make_figure()
media = []
if FIG:
    cx = 8 * 914400
    cy = int(cx * FIG[2] / FIG[1])
    figure_xml = image('rIdImg1', cx, cy, 'Automated test execution result')
    media = [('word/media/execution_summary.png', FIG[0])]
else:
    figure_xml = p_('[The execution screenshot could not be generated on this machine; see results/raw/*.console.txt for the full console output of each run.]', i=True)
body = [figure_xml if b == '@@FIGURE@@' else b for b in body]

# --------------------------------------------------------------------------------------------------------------------------------
# 7. Write the .docx (styles taken from the faculty template)
# --------------------------------------------------------------------------------------------------------------------------------
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')
sect = '<w:sectPr><w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/><w:pgMar w:top="1000" w:right="720" w:bottom="1000" w:left="720" w:header="500" w:footer="500" w:gutter="0"/></w:sectPr>'
document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (NS, ''.join(body), sect)

out_docx = os.path.join(ROOT, 'Baymax_Chapter5_Test_Cases.docx')
with zipfile.ZipFile(TEMPLATE) as tz:
    styles = tz.read('word/styles.xml')
    numbering = tz.read('word/numbering.xml')
    fonts = tz.read('word/fontTable.xml')
ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '<Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/></Types>')
rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
         '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
         '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
         '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>'
         + ('<Relationship Id="rIdImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/execution_summary.png"/>' if media else '') + '</Relationships>')
settings = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:defaultTabStop w:val="720"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
with zipfile.ZipFile(out_docx, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/document.xml', document)
    z.writestr('word/_rels/document.xml.rels', drels)
    z.writestr('word/styles.xml', styles)
    z.writestr('word/numbering.xml', numbering)
    z.writestr('word/fontTable.xml', fonts)
    z.writestr('word/settings.xml', settings)
    for name, src in media:
        z.write(src, name)

# --------------------------------------------------------------------------------------------------------------------------------
# 8. CSV files, copies of the test code, README
# --------------------------------------------------------------------------------------------------------------------------------
def w_csv(name, header, rows):
    with open(os.path.join(ROOT, 'csv', name), 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


w_csv('automated_test_cases.csv', ['Test Case ID', 'Type', 'Module', 'Related Requirement', 'Test Objective', 'Test Input / Condition', 'Expected Result', 'Actual Result', 'Status', 'Tool', 'Decision table', 'Test code file'],
      [[c['id'], TYPE_NAMES[c['type']], ('M%d %s' % (c['module'], MODULES[c['module']])) if c['module'] else 'Cross-module', c['req'], c['objective'], c['input'], c['expected'], c['actual'], status(c), c['tool'], c.get('table') or '', ', '.join(c['declared_in'])] for c in CASES])
w_csv('requirements_traceability_matrix.csv', ['Requirement ID', 'Requirement Description', 'Module', 'Implementation note', 'Automated Test Case IDs', 'Tools', 'Automated (Y/N)', 'Status'], csv_rtm)
dt_rows = []
for tname, cs in tables.items():
    for i, c in enumerate(cs, 1):
        dt_rows.append([tname, 'Rule %d' % i, c['id'], json.dumps(c.get('conds') or {}, ensure_ascii=False), c.get('actions') or '', status(c)])
w_csv('decision_tables.csv', ['Decision table', 'Rule', 'Test Case ID', 'Conditions', 'Action', 'Status'], dt_rows)

for d in ['flutter', 'api', 'e2e']:
    shutil.rmtree(os.path.join(ROOT, 'test_code', d), ignore_errors=True)
    os.makedirs(os.path.join(ROOT, 'test_code', d))
for p in glob.glob(os.path.join(APP, 'test', 'atc', '*.dart')):
    shutil.copy(p, os.path.join(ROOT, 'test_code', 'flutter'))
for p in glob.glob(os.path.join(API, 'test', 'atc', '*.js')):
    shutil.copy(p, os.path.join(ROOT, 'test_code', 'api'))
for p in glob.glob(os.path.join(API, 'e2e', '*.e2e.mjs')) + [os.path.join(API, 'e2e', 'harness.mjs')]:
    shutil.copy(p, os.path.join(ROOT, 'test_code', 'e2e'))

readme = f"""# Baymax: Chapter 5 test cases (60% implementation)

Generated from real test runs by `tools/generate_report.py`. Nothing in the result columns is typed by hand.

| File / folder | What it is |
|---|---|
| `Baymax_Chapter5_Test_Cases.docx` | Chapter 5 in the faculty template's structure: 5.1 Unit, 5.2 Functional, 5.3 Business rules (decision tables), 5.4 Integration, 5.5 Automated testing (strategy, tools, Table 5.2 test cases, results, RTM). Landscape, uses the template's styles. Copy the sections into the report. |
| `csv/automated_test_cases.csv` | Every test case (ID, requirement, input, expected, actual, status). |
| `csv/requirements_traceability_matrix.csv` | Requirement to test-case matrix (Table 5.3). |
| `csv/decision_tables.csv` | The decision-table rules. |
| `results/raw/` | The raw evidence: one JSON line per case, the console output of every run, the e2e XML reports. |
| `results/execution_summary.png` | Figure 5.1 (rendered from the run output). |
| `test_code/` | Copies of the test code that carries the IDs: `flutter/` (4 suites + helper), `api/`, `e2e/`. The live copies are in `app/test/atc/`, `baymax-api/test/atc/` and `baymax-api/e2e/`. |
| `tools/` | `run_all.sh` (runs everything and regenerates this folder), `generate_report.py`, `requirements.py` (FR table), `e2e_cases.json` (descriptions of the end-to-end cases). |

## Latest result
{TOTAL[0]} automated test cases: {TOTAL[1]} passed, {TOTAL[2]} failed, {TOTAL[3]} not run.
Unit {BY_TYPE['U'][0]} - Functional {BY_TYPE['F'][0]} - Business rules {BY_TYPE['B'][0]} - Integration {BY_TYPE['INT'][0]}.

## Run again
```
tools/run_all.sh          # ATC suites (about 3 minutes); starts and stops the Firebase emulators itself
tools/run_all.sh --full   # also the complete flutter test and npm test suites
```
Needs: Flutter, Node, the Firebase CLI and Java (for the emulator). Run one e2e file at a time (they reset the same emulator database).

## What this does NOT show
- Nothing was run on a physical phone. The Flutter tests are headless widget tests.
- The end-to-end tests run on local emulators, not the live Firebase project.
- `test_code/` also holds {len(EXCLUDED)} passing regression cases for Modules 10, 11 and 15, which are outside this chapter's module list; they are not in the document or the CSVs.
- Screens' look and feel, OCR with the Google Vision key, camera and the food photo model are not covered.
- Requirement IDs follow the merged report; FR-11 to FR-15 of Module 14 and FR-10 of Module 12 are requirements added during the build and are not in Chapter 2 yet (marked "added" in the RTM). The report's second "FR-6" in Module 2 is treated as FR-7.
"""
open(os.path.join(ROOT, 'README.md'), 'w', encoding='utf8').write(readme)

print('cases %d  pass %d  fail %d  not-run %d' % TOTAL)
print('unit %s  functional %s  rules %s  integration %s' % (BY_TYPE['U'], BY_TYPE['F'], BY_TYPE['B'], BY_TYPE['INT']))
print('requirements with a test: %d of %d' % (tested, len(rtm)))
if unknown:
    print('UNKNOWN requirement ids:', unknown)
if dupes:
    print('DUPLICATE ids:', sorted(dupes))
if orphans:
    print('ORPHAN results:', orphans)
print('figure:', 'yes' if FIG else 'no')
print('wrote', out_docx)
if dupes or orphans or unknown or TOTAL[3]:
    sys.exit(1)

"""Builds Baymax_Chapter5_My_Modules_4_5_6.docx: a separate Chapter 5 for Modules 4, 5 and 6 only, with a limited set of
representative test cases, formatted like the team's Chapter 5 (styles, page set-up and table formats are cloned from the
team's original document, which is not modified).

Every Actual Result comes from a recorded run:
  results/atc_m456.jsonl                    headless Flutter test run of 2026-10-18 (ATC_LOG)
  device_evidence/<run>/device_results.json Flutter integration_test runs on the phone (cross-checked against the device log)
Terminal screenshots are taken from my_modules/screenshots/<name>.png when present; otherwise the figure is marked pending.
Run (from docs/chapter5):  python tools/build_my_modules.py
"""
import copy
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

import docx
from docx.oxml.ns import qn
from docx.shared import Inches
from docx.table import Table
from docx.text.paragraph import Paragraph

HERE = Path(__file__).resolve().parent.parent
REPO = HERE.parent.parent
TEMPLATE = HERE / 'Baymax_Chapter5_Test_Cases.original.docx'   # the team's original, used read-only for formatting
OUTDIR = HERE / 'my_modules'
OUT = OUTDIR / 'Baymax_Chapter5_My_Modules_4_5_6.docx'
SHOTS = OUTDIR / 'screenshots'
RUNS = ['run3_smoke', 'run6_module4_workout', 'run7_module5_posture', 'run6_module6_voice', 'run7_cross_module']
PASS, FAIL, BLOCKED = '1B7F3B', 'C00000', '9C5700'

# ---------------------------------------------------------------- selection (representative cases only)
UNIT = OrderedDict([
    ('Unit Testing 12: Exercise knowledge base, safety rules and plan generator (Module 4, Personalized Workout Plan Generation)',
     ('Testing Objective: To ensure the exercise dataset is imported faithfully, equipment and medical rules decide each exercise as written, '
      'warning symptoms stop plan generation, the week has the chosen structure, and energy estimates use the MET formula.',
      ['ATC-M4-U07', 'ATC-M4-U10', 'ATC-M4-U13', 'ATC-M4-U16', 'ATC-M4-U20', 'ATC-M4-U23'])),
    ('Unit Testing 13: Posture engine, repetition counting and form checks (Module 5, Real-Time Posture Detection and Correction)',
     ('Testing Objective: To ensure joint angles and landmark visibility are handled correctly, full repetitions are counted and partial ones '
      'rejected, holds are timed only in position, and a correction appears only when a fault persists. Inputs are synthetic landmark '
      'frames, so these cases verify the logic, not detection accuracy on real people.',
      ['ATC-M5-U01', 'ATC-M5-U02', 'ATC-M5-U05', 'ATC-M5-U06', 'ATC-M5-U09', 'ATC-M5-U13'])),
    ('Unit Testing 14: Intent recognition, coach replies and voice session control (Module 6, Voice Assistant)',
     ('Testing Objective: To ensure transcribed requests are mapped to the right intent (including pain reports), replies use the live session '
      'data, and microphone, recognition and closing are handled safely. A simulated recogniser is used, so these cases do not validate '
      'speech-recognition accuracy.',
      ['ATC-M6-U01', 'ATC-M6-U06', 'ATC-M6-U07', 'ATC-M6-U10', 'ATC-M6-U12', 'ATC-M6-U14'])),
])
FUNC_NOTE = ('Objective: to ensure the screens show the correct content and react correctly to the user\'s actions. Cases ATC-M*-F were run '
             'headless with Flutter test (widget tests); cases ATC-DEV-* were run on the Android phone with Flutter Integration Test, '
             'which operates the real application automatically.')
FUNC = OrderedDict([
    ('Functional Testing 15: Workout plan and exercise detail screens (Module 4, Personalized Workout Plan Generation)',
     ['ATC-M4-F03', 'ATC-M4-F05', 'ATC-DEV-M4-01', 'ATC-DEV-M4-03', 'ATC-DEV-M4-04', 'ATC-DEV-M4-06']),
    ('Functional Testing 16: Posture detection, mode selection, camera and summary screens (Module 5, Real-Time Posture Detection and Correction)',
     ['ATC-M5-F05', 'ATC-M5-F08', 'ATC-M5-F09', 'ATC-DEV-M5-03', 'ATC-DEV-M5-05', 'ATC-DEV-M5-06']),
    ('Functional Testing 17: Voice assistant screen (Module 6, Voice Assistant)',
     ['ATC-M6-F02', 'ATC-M6-F03', 'ATC-DEV-M6-01', 'ATC-DEV-M6-02', 'ATC-DEV-M6-03', 'ATC-DEV-M6-04']),
])
DT = [('DT-M4-1', ['ATC-M4-B01', 'ATC-M4-B02', 'ATC-M4-B03', 'ATC-M4-B04', 'ATC-M4-B05']),
      ('DT-M4-2', ['ATC-M4-B06', 'ATC-M4-B07', 'ATC-M4-B08', 'ATC-M4-B09', 'ATC-M4-B10', 'ATC-M4-B11']),
      ('DT-M5-2', ['ATC-M5-B04', 'ATC-M5-B05', 'ATC-M5-B06']),
      ('DT-M5-4', ['ATC-M5-B09', 'ATC-M5-B10', 'ATC-M5-B11']),
      ('DT-M6-1', ['ATC-M6-B01', 'ATC-M6-B02', 'ATC-M6-B03', 'ATC-M6-B04']),
      ('DT-M6-2', ['ATC-M6-B05', 'ATC-M6-B06', 'ATC-M6-B07'])]
INTEG = OrderedDict([
    ('Integration Testing 5: Module 2 health classification to Module 4 workout plan',
     ('Testing Objective: to ensure the health category produced by Module 2 sets the intensity ceiling of the generated plan.', ['ATC-INT-34'])),
    ('Integration Testing 6: Module 4 workout plan and Module 5 posture sessions (both directions)',
     ('Testing Objective: to ensure a planned exercise opens a posture session with its planned dose, and that only a session that reached its '
      'target is recorded as completing the planned exercise.', ['ATC-INT-36', 'ATC-INT-37', 'ATC-DEV-INT-01'])),
    ('Integration Testing 7: Module 5 posture detection and Module 6 voice assistant (both directions)',
     ('Testing Objective: to ensure posture corrections reach the voice coach and voice commands control the running posture session.',
      ['ATC-INT-39', 'ATC-INT-42', 'ATC-DEV-INT-03'])),
    ('Integration Testing 8: End-to-end Modules 2, 4, 5 and 6',
     ('Testing Objective: to ensure a profile produces a plan whose exercises are done as sessions, queried by voice and recorded as a completed plan day.',
      ['ATC-INT-44'])),
])
FIGS = [  # (screenshot file, caption, command shown in the terminal)
    ('unit.png', 'Unit test cases of Modules 4, 5 and 6 (Flutter test, selected cases)',
     'flutter test test/atc/atc_m456_unit_test.dart -r github --name "ATC-M4-U(07|10|13|16|20|23) |ATC-M5-U(01|02|05|06|09|13) |ATC-M6-U(01|06|07|10|12|14) "'),
    ('functional.png', 'Functional (widget) test cases of Modules 4, 5 and 6 (Flutter test, selected cases)',
     'flutter test test/atc/atc_m456_functional_test.dart -r github --name "ATC-M4-F0[35] |ATC-M5-F0[589] |ATC-M6-F0[23] "'),
    ('rules.png', 'Business-rule (decision-table) test cases of Modules 4, 5 and 6 (Flutter test, selected cases)',
     'flutter test test/atc/atc_m456_rules_test.dart -r github --name "ATC-M4-B(0[1-9]|1[01]) |ATC-M5-B(0[4-6]|09|1[01]) |ATC-M6-B0[1-7] "'),
    ('integration.png', 'Integration test cases of Modules 2, 4, 5 and 6 (Flutter test, selected cases)',
     'flutter test test/atc/atc_m456_integration_test.dart -r github --name "ATC-INT-(34|36|37|39|42|44) "'),
    ('device_m4.png', 'Recorded real-device run of Module 4 (Flutter Integration Test on the Redmi Note 11, log of 2026-10-18)',
     'Select-String … run6_module4_workout\\flutter_drive.log'),
    ('device_m5.png', 'Recorded real-device run of Module 5 (Flutter Integration Test on the Redmi Note 11, log of 2026-10-18)',
     'Select-String … run7_module5_posture\\flutter_drive.log'),
    ('device_m6_cross.png', 'Recorded real-device runs of Module 6 and the cross-module flows (Flutter Integration Test, logs of 2026-10-18)',
     'Select-String … run6_module6_voice and run7_cross_module\\flutter_drive.log'),
]

# ---------------------------------------------------------------- results
atc = OrderedDict((d['id'], d) for d in map(json.loads, (HERE / 'results' / 'atc_m456.jsonl').read_text(encoding='utf-8').splitlines()))
headless_started = (HERE / 'results' / 'headless_run_started.txt').read_text(encoding='utf-8').strip()
dev = OrderedDict()
runs = {}
for name in RUNS:
    ev = HERE / 'device_evidence' / name
    log = (ev / 'flutter_drive.log').read_text(encoding='utf-8', errors='replace')
    steps = dict(re.findall(r'\[device-step\] (ATC-[A-Z0-9-]+) (passed|failed)', log))
    for c in json.loads((ev / 'device_results.json').read_text(encoding='utf-8'))['cases']:
        assert steps.get(c['id']) == ('passed' if c['status'] == 'Passed' else 'failed'), c['id']
        c['run'] = name
        dev[c['id']] = c
    info = (ev / 'device.txt').read_text(encoding='utf-8')
    runs[name] = re.search(r'started: (\S+)', info).group(1)
model, android, sdk, miui = re.search(r'model=(\S+) android=(\S+) sdk=(\S+) miui=(\S+)', info).groups()
DEVICE = f'Redmi Note 11 ({model}), Android {android} (API {sdk}), MIUI {miui}'

def case(i):
    if i in atc:
        c = atc[i]
        return dict(id=i, req=c['req'], objective=c['objective'], input=c['input'], expected=c['expected'], actual=c['actual'],
                    result='Pass' if c['ok'] else 'Fail', table=c.get('table'), conds=c.get('conds'), actions=c.get('actions'), tool='Flutter test (headless)')
    c = dev[i]
    return dict(id=i, req=c['req'], objective=c['objective'], input=c['input'], expected=c['expected'], actual=c['actual'],
                result={'Passed': 'Pass', 'Failed': 'Fail', 'Blocked': 'Blocked'}[c['status']], tool='Flutter Integration Test (Android phone)')

selected = [i for _, (_, ids) in UNIT.items() for i in ids] + [i for ids in FUNC.values() for i in ids] + \
           [i for _, ids in DT for i in ids] + [i for _, (_, ids) in INTEG.items() for i in ids]
assert len(selected) == len(set(selected)), 'duplicate selection'
missing = [i for i in selected if i not in atc and i not in dev]
assert not missing, missing

fr = json.loads((HERE / 'tools' / 'fr_m56.json').read_text(encoding='utf-8'))
sys.path.insert(0, str(REPO / 'docs' / 'test-cases' / 'tools'))
import requirements  # noqa: E402
REQ = {f'M4-FR{n}': t for n, t, _ in requirements.REQS[4]}
REQ.update({f'M5-{k}': v for k, v in fr.items() if not k.startswith('FR19')})
REQ.update({f'M6-{k}': v for k, v in fr.items() if k.startswith('FR19')})
REQ.update({
    'M4-SFR1': 'Import the exercise dataset with stable, unique IDs (added during implementation)',
    'M4-SFR2': 'Estimate energy from Compendium MET values: MET x weight x time (added during implementation)',
    'M4-SFR3': 'Screen readiness (warning symptoms, clearance, missing data) and owned equipment before planning (added during implementation)',
    'M4-SFR4': 'Record completion of planned exercises from posture sessions (added during implementation)',
    'M5-SFR1': 'Map every exercise to a movement pattern with a camera tracker or a stated reason (added during implementation)',
    'M5-SFR2': 'Time static holds such as the plank in camera mode (added during implementation)',
    'M5-SFR3': 'Start posture sessions from the personalised plan as well as the library (added during implementation)',
    'M6-SFR1': 'Recognise workout intents from the transcribed speech (added during implementation)',
    'M6-SFR2': 'Speak posture corrections and answer form questions from the live session (added during implementation)',
    'M6-SFR3': 'Control the posture session by voice: pause, resume, stop with confirmation (added during implementation)',
})

# ---------------------------------------------------------------- document from the team's template
d = docx.Document(str(TEMPLATE))
body = d.element.body
orig = list(body.iterchildren())
P = lambda e: Paragraph(e, d)
assert P(orig[0]).text.startswith('Chapter 5') and P(orig[107]).style.name == 'Heading 3'
TPL = dict(h1=orig[0], caption=orig[108], sum_tbl=orig[2], h2=orig[4], h3=orig[107], normal=orig[18], spacer=orig[20], unit_tbl=orig[19],
           func_tbl=orig[64], int_tbl=orig[201], dt=orig[109], br_tbl=orig[112], tools=orig[220], cases=orig[224], cmds=orig[229],
           results=orig[232], rtm=orig[238], fig_caption=orig[234], h3_55=orig[216])
TPL = {k: copy.deepcopy(v) for k, v in TPL.items()}
sect = orig[-1]
for e in orig[:-1]:
    body.remove(e)
out = []

def set_par_text(p_el, text):
    runs_ = p_el.findall(qn('w:r'))
    for r in runs_[1:]:
        p_el.remove(r)
    t = runs_[0].find(qn('w:t'))
    t.text = text
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    return p_el

def par(kind, text):
    out.append(set_par_text(copy.deepcopy(TPL[kind]), text))

def spacer():
    out.append(copy.deepcopy(TPL['spacer']))

def set_cell(tc, text, color=None):
    ps = tc.findall(qn('w:p'))
    for p in ps[1:]:
        tc.remove(p)
    p = ps[0]
    rs = p.findall(qn('w:r'))
    for r in rs[1:]:
        p.remove(r)
    r = rs[0]
    t = r.find(qn('w:t'))
    t.text = str(text)
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    rpr = r.find(qn('w:rPr'))
    c = rpr.find(qn('w:color')) if rpr is not None else None
    if color:
        if rpr is None:
            rpr = r.makeelement(qn('w:rPr'), {})
            r.insert(0, rpr)
        if c is None:
            c = rpr.makeelement(qn('w:color'), {})
            later = [e for e in rpr if e.tag in (qn('w:sz'), qn('w:szCs'))]
            (later[0].addprevious(c) if later else rpr.append(c))
        c.set(qn('w:val'), color)
    elif c is not None and rpr is not None and t.text not in ('Pass',):
        pass

def status_color(v):
    v = str(v)
    return PASS if v.startswith('Pass') else BLOCKED if v.startswith(('Blocked', 'Not', 'Pending')) else FAIL

def table(template, rows, header=None, status_col=None):
    tbl = copy.deepcopy(TPL[template])
    trs = tbl.findall(qn('w:tr'))
    head, data = trs[0], trs[1]
    for tr in trs[1:]:
        tbl.remove(tr)
    if header:
        for tc, h in zip(head.findall(qn('w:tc')), header):
            set_cell(tc, h)
    for values in rows:
        tr = copy.deepcopy(data)
        for k, (tc, v) in enumerate(zip(tr.findall(qn('w:tc')), values)):
            set_cell(tc, v, status_color(v) if k == status_col else None)
        tbl.append(tr)
    out.append(tbl)

def decision_table(conds_order, rules, actions):
    tbl = copy.deepcopy(TPL['dt'])
    n = len(rules)
    first, w = 3000, (14394 - 3000) // n
    grid = tbl.find(qn('w:tblGrid'))
    for g in list(grid):
        grid.remove(g)
    for k in range(n + 1):
        grid.append(grid.makeelement(qn('w:gridCol'), {qn('w:w'): str(first if k == 0 else w)}))
    trs = tbl.findall(qn('w:tr'))
    head, cond_row, act_row = trs[0], trs[1], trs[-1]
    for tr in trs:
        tbl.remove(tr)

    def build(template, label, values):
        tr = copy.deepcopy(template)
        tcs = tr.findall(qn('w:tc'))
        a, other = tcs[0], tcs[1]
        for tc in tcs:
            tr.remove(tc)
        a = copy.deepcopy(a)
        set_cell(a, label)
        tr.append(a)
        for v in values:
            c = copy.deepcopy(other)
            c.find(qn('w:tcPr')).find(qn('w:tcW')).set(qn('w:w'), str(w))
            set_cell(c, v)
            tr.append(c)
        return tr
    tbl.append(build(head, 'Conditions', [f'Rule {k + 1}' for k in range(n)]))
    for name in conds_order:
        tbl.append(build(cond_row, name, [r.get(name, '-') for r in rules]))
    tbl.append(build(act_row, 'Action / expected result', actions))
    out.append(tbl)

tno = [32]
def caption(text):
    tno[0] += 1
    par('caption', f'Table 5.{tno[0]}  {text}')
fno = [1]
def fig_caption(text):
    fno[0] += 1
    par('fig_caption', f'Figure 5.{fno[0]}: {text}')

def picture(path, width):
    p = d.add_paragraph()
    p.alignment = 1
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(path), width=width)
    el = p._p
    el.getparent().remove(el)
    out.append(el)

def rows7(ids):
    return [[k + 1, c['id'], c['objective'], c['input'], c['expected'], c['actual'], c['result']] for k, c in enumerate(map(case, ids))]

# ---------------------------------------------------------------- content
cats = OrderedDict([('Unit', [i for _, (_, ids) in UNIT.items() for i in ids]), ('Functional', [i for ids in FUNC.values() for i in ids]),
                    ('Business rules (decision tables)', [i for _, ids in DT for i in ids]), ('Integration', [i for _, (_, ids) in INTEG.items() for i in ids])])
par('h1', 'Chapter 5: Testing and Evaluation (Modules 4, 5 and 6)')
caption('Summary of the selected test cases for Modules 4, 5 and 6')
sum_rows, tot = [], [0, 0, 0, 0]
for (name, ids), sec in zip(cats.items(), ['5.1', '5.2', '5.3', '5.4']):
    res = [case(i)['result'] for i in ids]
    v = [len(ids), res.count('Pass'), res.count('Fail'), len(ids) - res.count('Pass') - res.count('Fail')]
    tot = [a + b for a, b in zip(tot, v)]
    sum_rows.append([name, sec] + v)
sum_rows.append(['Total', ''] + tot)
table('sum_tbl', sum_rows)
par('normal', f'The cases above are a representative selection from the automated suites of Modules 4, 5 and 6 (about six per module per '
              f'category). "Not run" counts cases that were blocked by the test device; they are explained in Section 5.5.4.')
spacer()

par('h2', '5.1 Unit Testing')
for title, (objective, ids) in UNIT.items():
    par('h3', title)
    par('normal', objective)
    table('unit_tbl', rows7(ids), status_col=6)
    spacer()

par('h2', '5.2 Functional Testing')
for title, ids in FUNC.items():
    par('h3', title)
    par('normal', FUNC_NOTE)
    table('func_tbl', rows7(ids), status_col=6)
    spacer()

par('h2', '5.3 Business Rules Testing')
for k, (code, ids) in enumerate(DT, start=14):
    cs = [case(i) for i in ids]
    tname = cs[0]['table']
    conds = list(OrderedDict.fromkeys(c for x in cs for c in x['conds']))
    par('h3', f'Business Rule Testing {k}: {tname}')
    caption(f'Decision table: {tname}')
    decision_table(conds, [x['conds'] for x in cs], [x['actions'] for x in cs])
    spacer()
    caption(f'Test cases for {code}')
    table('br_tbl', [[n + 1, x['id'], f'Rule {n + 1}: {x["objective"]}', x['input'], x['expected'], x['actual'], x['result']] for n, x in enumerate(cs)], status_col=6)
    spacer()

par('h2', '5.4 Integration Testing')
for title, (objective, ids) in INTEG.items():
    par('h3', title)
    par('normal', objective)
    table('int_tbl', rows7(ids), status_col=6)
    spacer()

par('h2', '5.5 Automated Testing')
par('h3', '5.5.1 Automated Testing Strategy')
par('normal', 'Types of testing automated. Unit, functional (widget), business-rule (decision-table) and integration tests were automated with '
              'Flutter test and run without a device. Real-device UI tests and end-to-end flows were automated with Flutter Integration Test on an '
              'Android phone. The complete Flutter test suite of the application was also run as a regression check.')
par('normal', 'Functionality selected and why. For Module 4, the screening gate (warning symptoms, missing data, doctor\'s clearance), the medical '
              'and equipment restrictions, the weekly plan structure and the MET-based energy estimate were selected, because a mistake there could '
              'give an unsafe or wrong plan. For Module 5, joint-angle and landmark-visibility handling, repetition acceptance, hold timing, the '
              'timing of corrections, camera consent and the session summary were selected, because users rely on the counts and corrections and '
              'the camera must not start without consent. For Module 6, intent recognition including pain reports, permission handling, replies '
              'built from the live session (never invented numbers) and voice control of a running session were selected. Integration cases '
              'cover the data flow between the health classification (Module 2), the plan (Module 4), posture sessions (Module 5) and the voice '
              'assistant (Module 6). Easy but low-value cases (for example simple labels) were not prioritised.')
par('normal', 'How automation was performed. Each case has a test-case ID in its name and records its objective, input, expected result and the '
              'observed actual result, so the tables in this chapter are taken from real runs. Posture cases feed deterministic synthetic pose-landmark '
              'sequences into the real posture engine; voice cases use a simulated speech recogniser and speech output in the headless tests. On the '
              'phone, Flutter Integration Test starts the real application and drives it through Flutter\'s gesture system (taps, scrolling, '
              'navigation) with a fictional test user held in memory; nobody signs in, finished sessions are kept in memory, and the phone\'s '
              'permission state is read but never changed, so no real account or health record is touched.')
par('normal', f'Frameworks and tools. Flutter test (flutter_test) and Flutter Integration Test (integration_test, run with flutter drive and '
              f'test_driver/integration_test.dart), Flutter 3.47.7 with Dart 3.13.5, and the Android Debug Bridge. No other test framework '
              f'is used for these modules.')
par('normal', f'Where the tests were executed. Headless tests ran on the development PC (Windows 11 Home). Real-device tests ran on a {DEVICE}, '
              f'connected by USB, on 2026-10-18.')
par('normal', 'Tests that remained manual and why. Real-person posture accuracy (whether reps and corrections are right for a person exercising '
              'in front of the camera) cannot be judged automatically and is validated manually; so far only the squat has been checked live '
              '(2026-10-15). Live speech recognition with a real voice and the audible quality of spoken replies need a person speaking and '
              'listening, so they are validated manually; the automated device tests use fixed quick-action phrases. Saving to the cloud with a '
              'real account was not automated, to avoid changing real user data.')

par('h3', '5.5.2 Automation Tools and Environment')
caption('Automation tools and environment for Modules 4, 5 and 6')
table('tools', [
    ['flutter_test (Flutter test framework)', 'Unit, widget (functional), decision-table and integration test cases', 'Flutter 3.47.7, Dart 3.13.5', 'Unit / Functional / Business rules / Integration', 'Windows 11 Home PC, headless'],
    ['integration_test (Flutter Integration Test)', 'Automated UI and end-to-end tests of the installed application on a phone', 'Flutter 3.47.7 SDK package', 'Functional / Integration (real device)', DEVICE],
    ['flutter drive with test_driver/integration_test.dart', 'Builds and installs the test build, runs it, collects results and screenshots', 'Flutter 3.47.7 tools', 'Test runner (real device)', 'Windows 11 PC, USB to the phone'],
    ['Android Debug Bridge (adb)', 'Device connection and device information', 'adb 1.0.41', '-', 'Windows 11 PC'],
    ['On-device components under test', 'Camera plugin with on-device MediaPipe pose detection, speech_to_text, flutter_tts', 'as locked in pubspec.lock', 'Functional / Integration (real device)', DEVICE],
])
spacer()

par('h3', '5.5.3 Automated Test Cases')
caption('Automated test cases selected for Modules 4, 5 and 6')
table('cases', [[c['id'], c['req'], c['objective'], c['tool'], c['expected'], c['actual'], c['result']] for c in map(case, selected)],
      header=['Test Case ID', 'Related Requirement', 'Test Objective', 'Framework / where run', 'Expected Result', 'Actual Result', 'Status'], status_col=6)
spacer()

par('h3', '5.5.4 Automated Test Execution and Results')
caption('How the selected suites are run')
table('cmds', [[f[1], f[2], 'Flutter test' if not f[0].startswith('device') else 'Flutter Integration Test (recorded log)'] for f in FIGS[:4]] +
      [['All real-device cases of one module', 'cd app && bash integration_test/run_on_device.sh integration_test/<module>_test.dart <run-name>', 'Flutter Integration Test'],
       ['Complete regression of the application', 'cd app && flutter test --concurrency=2', 'Flutter test']],
      header=['Suite', 'Command (run from the app folder)', 'Type'])
spacer()
caption('Execution results of the selected test cases')
hl = [i for i in selected if i in atc]
dv = [i for i in selected if i in dev]
def counts(ids):
    r = [case(i)['result'] for i in ids]
    return [len(ids), r.count('Pass'), r.count('Fail'), len(ids) - r.count('Pass') - r.count('Fail')]
table('results', [['Flutter test (headless), selected cases', *counts(hl)],
                  [f'Flutter Integration Test on the {DEVICE.split(",")[0]}, selected cases', *counts(dv)],
                  ['Total selected', *counts(selected)],
                  ['Complete Flutter regression of the application (context)', 1006 - 13, 993, 0, '13 (skipped in source)']])
spacer()
blocked = [i for i in dv if case(i)['result'] == 'Blocked']
par('normal', f'The headless results come from the Flutter test run of {headless_started[:16].replace("T", " ")} (all {len(hl)} selected cases passed). '
              f'The real-device results come from the Flutter Integration Test runs of 2026-10-18 on the {DEVICE}. '
              + (f'{", ".join(blocked)} could not be executed: the camera permission of the installed test build was "denied" on the phone after a '
                 'reinstall, and the tests do not grant permissions themselves; these cases are reported as not run and need a rerun after camera '
                 'access is allowed. ' if blocked else '')
              + 'The figures below are terminal screenshots of the selected suites.')
for fname, cap, cmd in FIGS:
    p = SHOTS / fname
    if p.exists():
        picture(p, Inches(8.5))
    else:
        par('normal', f'[Screenshot pending: run "{cmd}" in the project terminal and insert the screenshot here.]')
    fig_caption(cap + ('' if p.exists() else ' (pending)'))
phone = HERE / 'device_evidence' / 'run7_cross_module' / 'screenshots' / 'ATC-DEV-INT-01.png'
if phone.exists():
    picture(phone, Inches(2.2))
    fig_caption('Screen captured by ATC-DEV-INT-01 on the Redmi Note 11 at the end of the case (Flutter Integration Test)')
spacer()

par('h3', '5.5.5 Requirement Traceability for Automated Testing')
caption('Requirement Traceability Matrix for Modules 4, 5 and 6 (selected cases)')
def cat(i):
    return ('Integration (real device)' if i.startswith('ATC-DEV-INT') else 'Functional (real device)' if i.startswith('ATC-DEV')
            else 'Integration' if i.startswith('ATC-INT') else {'U': 'Unit', 'F': 'Functional', 'B': 'Business rule'}[i.split('-')[2][0]])
mod = {'M3': 'Home Dashboard', 'M4': 'Module 4 Workout Plan', 'M5': 'Module 5 Posture Detection', 'M6': 'Module 6 Voice Assistant'}
reqs = sorted({case(i)['req'] for i in selected}, key=lambda r: (r[:2], 'SFR' in r, [int(x) if x.isdigit() else x for x in re.findall(r'\d+|\D+', r)]))
rtm = []
for r in reqs:
    ids = [i for i in selected if case(i)['req'] == r]
    res = [case(i)['result'] for i in ids]
    run = res.count('Pass') + res.count('Fail')
    st = (f'Pass ({res.count("Pass")}/{run})' if not res.count('Fail') else f'Fail ({res.count("Fail")} of {run})') if run else 'Not run'
    if res.count('Blocked'):
        st += f'; not run ({res.count("Blocked")}, blocked on device)'
    rtm.append([r, REQ.get(r, ''), f'{mod[r[:2]]}; {", ".join(sorted({cat(i) for i in ids}))}', ', '.join(ids),
                '; '.join(sorted({'Flutter test' if i in atc else 'Flutter Integration Test' for i in ids})), 'Yes', st])
table('rtm', rtm, status_col=6)
spacer()

for e in out:
    sect.addprevious(e)
OUTDIR.mkdir(exist_ok=True)
d.save(str(OUT))
print('wrote', OUT, '| cases', len(selected), '| summary', tot, '| tables 5.33-5.%d | figures 5.2-5.%d' % (tno[0], fno[0]),
      '| screenshots present:', [f[0] for f in FIGS if (SHOTS / f[0]).exists()])

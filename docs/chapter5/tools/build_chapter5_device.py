"""Builds Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx from the team's merged Chapter 5
(base_Baymax_Chapter5complete_Test_Cases.docx, an exact copy of the version supplied on 2026-10-18) and the recorded results.

Nothing in the base is deleted, reworded, reformatted or renumbered. New elements are cloned from the base's own elements and
inserted at anchors found by heading/caption text. The only edits to existing content are the aggregate counts in Table 5.1 and 5.31.
Inputs (all written by real runs):
  results/atc_m456.jsonl                         headless Flutter ATC cases of Modules 4-6 (ATC_LOG)
  results/flutter_full_regression_reporter.json  complete headless Flutter run
  device_evidence/<RUN>/flutter_drive.log        real-device run: one "[device-case] {json}" line per case
  device_evidence/<RUN>/device.txt, screenshots/  device model, Android version, command, screenshots
Run (from docs/chapter5):  python tools/build_chapter5_device.py run5_all
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
BASE = HERE / 'base_Baymax_Chapter5complete_Test_Cases.docx'
OUT = HERE / 'Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx'
RUNS = sys.argv[1:] or ['run3_smoke', 'run6_module4_workout', 'run7_module5_posture', 'run6_module6_voice', 'run7_cross_module']
EVS = [HERE / 'device_evidence' / r for r in RUNS]
PASS, FAIL, BLOCKED = '1B7F3B', 'C00000', '9C5700'

# ---------------------------------------------------------------- results
atc = OrderedDict()
for line in (HERE / 'results' / 'atc_m456.jsonl').read_text(encoding='utf-8').splitlines():
    d = json.loads(line)
    atc[d['id']] = d
dev = OrderedDict()
run_info = []
for name, ev in zip(RUNS, EVS):
    log_txt = (ev / 'flutter_drive.log').read_text(encoding='utf-8', errors='replace')
    # Full records come from device_results.json (written by the driver from the app's reportData). Android truncates long
    # log lines, so the log is only used to cross-check each case's status against the device-side "[device-step] <id> passed|failed".
    records = json.loads((ev / 'device_results.json').read_text(encoding='utf-8'))['cases']
    steps = dict(re.findall(r'\[device-step\] (ATC-[A-Z0-9-]+) (passed|failed)', log_txt))
    assert len(records) == len(steps), f'{name}: {len(records)} records but {len(steps)} results in the log'
    for c in records:
        want = 'passed' if c['status'] == 'Passed' else 'failed'
        assert steps.get(c['id']) == want, f"{name}: {c['id']} is {c['status']} in device_results.json but {steps.get(c['id'])} in the log"
        c['run'] = name
        dev[c['id']] = c
    info = (ev / 'device.txt').read_text(encoding='utf-8')
    runner = re.findall(r': (\d\d:\d\d) \+(\d+)(?: -(\d+))?: (All tests passed!|Some tests failed\.)', log_txt)
    assert runner, f'device-side runner summary not found in {name}'
    # The framework's own verdict must agree with the case records (a case can pass its body yet fail on an exception the
    # framework catches elsewhere). "+N" includes the tear-down step; Blocked cases fail in the framework by design.
    fw_pass, fw_fail = int(runner[-1][1]) - 1, int(runner[-1][2] or 0)
    rec_pass = sum(c['status'] == 'Passed' for c in records)
    assert (fw_pass, fw_fail) == (rec_pass, len(records) - rec_pass), f'{name}: framework {fw_pass}/{fw_fail} vs records {rec_pass}/{len(records) - rec_pass}'
    run_info.append((name, re.search(r'started: (\S+)', info).group(1), re.search(r'target: (\S+)', info).group(1), runner[-1]))
dm = re.search(r'model=(\S+) android=(\S+) sdk=(\S+) miui=(\S+)', info)
model, android, sdk, miui = dm.groups()
started = run_info[0][1]
reg = {'passed': 0, 'failed': 0, 'skipped': 0}
for line in (HERE / 'results' / 'flutter_full_regression_reporter.json').read_text(encoding='utf-8', errors='replace').splitlines():
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get('type') == 'testDone' and not e.get('hidden'):
        reg['skipped' if e['skipped'] else ('passed' if e['result'] == 'success' else 'failed')] += 1

fr = json.loads((HERE / 'tools' / 'fr_m56.json').read_text(encoding='utf-8'))
sys.path.insert(0, str(REPO / 'docs' / 'test-cases' / 'tools'))
import requirements  # noqa: E402
m4 = {f'M4-FR{n}': t for n, t, _ in requirements.REQS[4]}
m3 = {f'M3-FR{n}': t for n, t, _ in requirements.REQS[3]}
SFR = {
    'M4-SFR1': 'Import the free-exercise-db exercise dataset with stable, unique IDs (added during implementation)',
    'M4-SFR2': 'Match each exercise to a Compendium MET value; estimate energy as MET x weight x time (added)',
    'M4-SFR3': 'Screen readiness (warning symptoms, clearance, missing data) and owned equipment before planning (added)',
    'M4-SFR4': 'Record completion of planned exercises from sessions and mark the plan day done (added)',
    'M5-SFR1': 'Map every exercise to a movement pattern with a camera tracker or a stated reason (added)',
    'M5-SFR2': 'Time static holds (plank, wall sit) in camera mode (added)',
    'M5-SFR3': "Start posture sessions from the personalised plan (Today's workout / My plan) as well as the library (added)",
    'M6-SFR1': 'Recognise workout intents from the spoken (transcribed) text (added)',
    'M6-SFR2': 'Speak posture corrections and answer form questions from the live session (added)',
    'M6-SFR3': 'Control the posture session by voice (pause, resume, stop with confirmation) (added)',
}
def req_text(r):
    return m4.get(r) or m3.get(r) or SFR.get(r) or fr[r.split('-', 1)[1]]

def category(i):
    if i.startswith('ATC-DEV-INT'):
        return 'Integration (real device)'
    if i.startswith('ATC-DEV'):
        return 'Functional (real device)'
    if i.startswith('ATC-INT'):
        return 'Integration'
    return {'U': 'Unit', 'F': 'Functional (widget)', 'B': 'Business rule'}[i.split('-')[2][0]]

SRC = {'U': 'test/atc/atc_m456_unit_test.dart', 'F': 'test/atc/atc_m456_functional_test.dart',
       'B': 'test/atc/atc_m456_rules_test.dart', 'I': 'test/atc/atc_m456_integration_test.dart'}
def source(i):
    if i.startswith('ATC-DEV'):
        return dev[i]['file']
    return SRC['I' if i.startswith('ATC-INT') else i.split('-')[2][0]]

# ---------------------------------------------------------------- document helpers
d = docx.Document(str(BASE))
body = d.element.body
orig = list(body.iterchildren())
P = lambda e: Paragraph(e, d)

def find_par(text, style=None, start=0):
    for k in range(start, len(orig)):
        e = orig[k]
        if e.tag.endswith('}p') and P(e).text.strip() == text and (style is None or P(e).style.name == style):
            return k
    raise KeyError(text)

def next_tbl(k):
    while not orig[k].tag.endswith('}tbl'):
        k += 1
    return k

i_51 = find_par('5.1 Unit Testing', 'Heading 2')
i_52 = find_par('5.2 Functional Testing', 'Heading 2')
i_53 = find_par('5.3 Business Rules Testing', 'Heading 2')
i_54 = find_par('5.4 Integration Testing', 'Heading 2')
i_55 = find_par('5.5 Automated Testing', 'Heading 2')
i_551 = find_par('5.5.1 Automated Testing Strategy')
i_553 = find_par('5.5.3 Automated Test Cases')
i_554 = find_par('5.5.4 Automated Test Execution and Results')
i_555 = find_par('5.5.5 Requirement Traceability for Automated Testing')
i_cap28 = find_par('Table 5.28  Automated Testing Tools and Environment')
i_cap29 = find_par('Table 5.29  Automated Test Cases')
i_cap30 = find_par('Table 5.30  How each suite is run')
i_cap31 = find_par('Table 5.31  Execution results (from the latest run)')
i_cap32 = find_par('Table 5.32  Requirement Traceability Matrix for Automated Testing')
i_fig1 = find_par('Figure 5.1: Automated Test Execution Result')
i_ft4 = next(k for k in range(i_52, i_53) if orig[k].tag.endswith('}p') and P(orig[k]).text.startswith('Functional Testing 4:'))
i_it2 = next(k for k in range(i_54, i_55) if orig[k].tag.endswith('}p') and P(orig[k]).text.startswith('Integration Testing 2:'))
sect = len(orig) - 1
assert orig[sect].tag.endswith('}sectPr')

TPL = dict(h3=orig[i_ft4], normal=orig[i_ft4 + 1], func_tbl=orig[next_tbl(i_ft4)], spacer=orig[next_tbl(i_ft4) + 1],
           int_tbl=orig[next_tbl(i_it2)], caption=orig[i_cap28], tools=orig[next_tbl(i_cap28)], cases=orig[next_tbl(i_cap29)],
           cmds=orig[next_tbl(i_cap30)], results=orig[next_tbl(i_cap31)], rtm=orig[next_tbl(i_cap32)], fig_caption=orig[i_fig1],
           h3_55=orig[i_555])
assert P(TPL['spacer']).text == ''

def clone(e):
    return copy.deepcopy(e)

def set_par_text(p_el, text):
    runs = p_el.findall(qn('w:r'))
    for r in runs[1:]:
        p_el.remove(r)
    t = runs[0].find(qn('w:t'))
    t.text = text
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    return p_el

def par(kind, text):
    return set_par_text(clone(TPL[kind]), text)

def spacer():
    return clone(TPL['spacer'])

def set_cell(tc, text, color=None):
    ps = tc.findall(qn('w:p'))
    for p in ps[1:]:
        tc.remove(p)
    p = ps[0]
    runs = p.findall(qn('w:r'))
    for r in runs[1:]:
        p.remove(r)
    r = runs[0]
    t = r.find(qn('w:t'))
    t.text = str(text)
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    if color:
        rpr = r.find(qn('w:rPr'))
        if rpr is None:
            rpr = r.makeelement(qn('w:rPr'), {})
            r.insert(0, rpr)
        c = rpr.find(qn('w:color'))
        if c is None:
            c = rpr.makeelement(qn('w:color'), {})
            later = [e for e in rpr if e.tag in (qn('w:sz'), qn('w:szCs'), qn('w:highlight'), qn('w:u'), qn('w:lang'))]
            (later[0].addprevious(c) if later else rpr.append(c))
        c.set(qn('w:val'), color)

def status_color(v):
    v = str(v)
    return PASS if v.startswith('Pass') else BLOCKED if v.startswith(('Blocked', 'Not')) else FAIL

def table_from(template, rows, header=None, status_col=None):
    tbl = clone(template)
    trs = tbl.findall(qn('w:tr'))
    head, data = trs[0], trs[1]
    for tr in trs[1:]:
        tbl.remove(tr)
    if header:
        for tc, h in zip(head.findall(qn('w:tc')), header):
            set_cell(tc, h)
    for values in rows:
        tr = clone(data)
        for k, (tc, v) in enumerate(zip(tr.findall(qn('w:tc')), values)):
            set_cell(tc, v, status_color(v) if k == status_col else None)
        tbl.append(tr)
    return tbl

def picture(path, width):
    p = d.add_paragraph()
    p.alignment = 1
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(path), width=width)
    el = p._p
    el.getparent().remove(el)
    return el

def before(k, els):
    for e in els:
        orig[k].addprevious(e)

def after(k, els):
    for e in reversed(els):
        orig[k].addnext(e)

existing = [int(m.group(1)) for e in orig if e.tag.endswith('}p') for m in [re.match(r'Table 5\.(\d+)\s', P(e).text)] if m]
table_no = [max(existing)]
def caption(text):
    table_no[0] += 1
    return par('caption', f'Table 5.{table_no[0]}  {text}')
fig_no = [max(int(m.group(1)) for e in orig if e.tag.endswith('}p') for m in [re.match(r'Figure 5\.(\d+)', P(e).text)] if m)]
def fig_caption(text):
    fig_no[0] += 1
    return par('fig_caption', f'Figure 5.{fig_no[0]}: {text}')

def dev_status(c):
    return {'Passed': 'Pass', 'Failed': 'Fail', 'Blocked': 'Blocked'}[c['status']]

def dev_rows(cs):
    return [[k + 1, c['id'], c['objective'], c['input'], c['expected'], c['actual'], dev_status(c)] for k, c in enumerate(cs)]

dev_func = [c for i, c in dev.items() if not i.startswith('ATC-DEV-INT')]
dev_int = [c for i, c in dev.items() if i.startswith('ATC-DEV-INT')]
ok_func = sum(c['status'] == 'Passed' for c in dev_func)
ok_int = sum(c['status'] == 'Passed' for c in dev_int)
fail_func = sum(c['status'] == 'Failed' for c in dev_func)
fail_int = sum(c['status'] == 'Failed' for c in dev_int)
blk_func = len(dev_func) - ok_func - fail_func
blk_int = len(dev_int) - ok_int - fail_int
DEVICE = f'Redmi Note 11 ({model}), Android {android} (API {sdk}), MIUI {miui}'

# ---------------------------------------------------------------- 5.2: real-device functional cases (end of 5.2)
ft_last = max(int(m.group(1)) for k in range(i_52, i_53) if orig[k].tag.endswith('}p')
              for m in [re.match(r'Functional Testing (\d+):', P(orig[k]).text)] if m)
before(i_53, [
    par('h3', f'Functional Testing {ft_last + 1}: Real-device UI automation of Modules 4, 5 and 6 (Flutter integration_test, {DEVICE.split(",")[0]})'),
    par('normal', 'Objective: to run the real Baymax screens on the physical phone and operate them automatically (taps, scrolling and '
                  'navigation through Flutter integration_test), with a controlled in-memory test user. Camera cases use the phone\'s camera and '
                  'on-device MediaPipe; voice cases use the phone\'s speech and text-to-speech engines. These cases do not measure posture-detection '
                  'or speech-recognition accuracy.'),
    table_from(TPL['func_tbl'], dev_rows(dev_func), status_col=6), spacer()])

# ---------------------------------------------------------------- 5.4: real-device cross-module cases (end of 5.4)
it_last = max(int(m.group(1)) for k in range(i_54, i_55) if orig[k].tag.endswith('}p')
              for m in [re.match(r'Integration Testing (\d+):', P(orig[k]).text)] if m)
before(i_55, [
    par('h3', f'Integration Testing {it_last + 1}: Cross-module flows on the real phone (Modules 4, 5 and 6, Flutter integration_test)'),
    par('normal', 'Testing Objective: to follow the user journey across modules on the physical phone: plan to posture session to recorded '
                  'completion (4 → 5 → 4), the voice assistant answering from a live camera session (5 ↔ 6), and a voice command pausing a session (6 → 5).'),
    table_from(TPL['int_tbl'], dev_rows(dev_int), status_col=6), spacer()])

# ---------------------------------------------------------------- 5.5.1 strategy (after the existing paragraph)
after(i_551 + 1, [par('normal',
    'For Modules 4 (Workout Plan Generation), 5 (Posture Detection) and 6 (Voice Assistant) the same layers are used: Flutter test for '
    'unit, widget (functional), decision-table and integration cases, run headless on the development PC and recorded through ATC_LOG. '
    'On top of these, Flutter\'s official integration_test package runs the real application on a physically connected Android phone: '
    'the app is built and installed, and the test code drives the real screens through Flutter\'s gesture system. Unlike the headless '
    'tests, this exercises the real device rendering, the bundled datasets, the camera plugin with on-device MediaPipe, and the speech and '
    'text-to-speech engines. A fictional test user is held in memory (nobody is signed in), finished sessions are kept in an in-memory '
    'log, and the phone\'s permission state is read but never changed, so no real account or health record is touched. Real-person '
    'posture accuracy is a separate, manual validation (Section 5.5.6). Module 6 (voice assistant) is distinct from the Module 13 AI '
    'chatbot, which is only used as an entry point.')])

# ---------------------------------------------------------------- 5.5.2 tools
tools_rows = [
    ['flutter_test (Flutter test framework)', 'Unit, widget, decision-table and integration cases of Modules 4, 5 and 6 (headless)',
     'Flutter 3.47.7, Dart 3.13.5 (stable)', 'Unit / Functional / Business rules / Integration', 'Windows 11 Home, headless'],
    ['integration_test (Flutter SDK package) with IntegrationTestWidgetsFlutterBinding', 'Automated UI tests of the installed app on the physical phone',
     'integration_test from the Flutter 3.47.7 SDK', 'Functional / Integration (real device)', DEVICE],
    ['flutter drive + test_driver/integration_test.dart (integration_test_driver_extended)', 'Builds, installs and launches the test build; collects results and screenshots on the PC',
     'Flutter 3.47.7 tools', 'Test runner (real device)', 'Windows 11, USB'],
    ['Android Debug Bridge (adb)', 'Device connection, install, device properties', 'adb 1.0.41 (platform-tools 37.0.1)', '-', 'Windows 11, USB to the phone'],
    ['Android SDK / Gradle (via flutter build)', 'Debug build of the app and test APK', 'Android SDK 36, build-tools 36.0.0, AGP 8.11.1', '-', 'Windows 11, JDK 21.0.10'],
    ['On-device components under test', 'Camera plugin, MediaPipe pose landmarker, speech_to_text, flutter_tts', 'as locked in pubspec.lock', 'Functional / Integration (real device)', DEVICE],
]
before(i_553, [caption('Automation tools and environment added for Modules 4, 5 and 6'), table_from(TPL['tools'], tools_rows), spacer()])

# ---------------------------------------------------------------- 5.5.3 test cases + source mapping
rows = [[c['id'], c['req'], c['objective'], c['input'], c['expected'], c['actual'], 'Pass' if c['ok'] else 'Fail'] for c in atc.values()]
rows += [[c['id'], c['req'], c['objective'], c['input'], c['expected'], c['actual'], dev_status(c)] for c in dev.values()]
mapping = [[i, category(i), source(i), (dev[i]['test'] if i in dev else f'{i} {atc[i]["objective"]}'),
            'Flutter integration_test (real device)' if i in dev else 'Flutter test (headless)', '-', 'Yes']
           for i in list(atc) + list(dev)]
before(i_554, [caption('Automated test cases for Modules 4, 5 and 6 (headless and real device)'), table_from(TPL['cases'], rows, status_col=6), spacer(),
               caption('Test source mapping for Modules 4, 5 and 6'),
               table_from(TPL['cases'], [[m[0], m[1], m[2], m[3], m[4], m[5], m[6]] for m in mapping],
                          header=['Test Case ID', 'Testing category', 'Test file', 'Test name', 'Framework', '-', 'Automated']), spacer()])

# ---------------------------------------------------------------- 5.5.4 commands, results, figures
cmd_rows = [
    ['Modules 4-6 unit, functional, business-rule and integration cases (headless)',
     'cd app && flutter test test/atc/atc_m456_unit_test.dart test/atc/atc_m456_functional_test.dart test/atc/atc_m456_rules_test.dart test/atc/atc_m456_integration_test.dart',
     'Unit / Functional / Business rules / Integration'],
    ['Real-device smoke test', 'cd app && flutter drive --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart -d f3fd6781 --keep-app-running',
     'Functional (real device)'],
    ['All real-device cases (one install)', 'cd app && bash integration_test/run_on_device.sh integration_test/all_device_test.dart <run-name>',
     'Functional / Integration (real device)'],
    ['Complete headless regression', 'cd app && flutter test --concurrency=2', 'All app tests'],
]
before(i_cap31, [caption('How the Modules 4, 5 and 6 suites are run'), table_from(TPL['cmds'], cmd_rows), spacer()])

n_atc = len(atc)
ok_atc = sum(c['ok'] for c in atc.values())
res_rows = [
    ['Flutter test (Dart), headless: Modules 4-6 ATC cases', n_atc, ok_atc, n_atc - ok_atc, 0],
    [f'Flutter integration_test on the {DEVICE.split(",")[0]}: Modules 4-6 cases', len(dev), ok_func + ok_int, fail_func + fail_int, blk_func + blk_int],
    ['Total newly verified for Modules 4, 5 and 6', n_atc + len(dev), ok_atc + ok_func + ok_int, n_atc - ok_atc + fail_func + fail_int, blk_func + blk_int],
    ['Complete headless Flutter regression, all modules (context, not added to the totals)', reg['passed'] + reg['failed'], reg['passed'], reg['failed'], f"{reg['skipped']} (skipped in source)"],
]
shots = sorted(p for ev in EVS for p in (ev / 'screenshots').glob('*.png'))
pick = [s for s in shots if s.stem in ('ATC-DEV-M4-01', 'ATC-DEV-M5-01', 'ATC-DEV-M6-01', 'ATC-DEV-INT-01')]
figs = []
for s in pick:
    figs += [picture(s, Inches(2.0)), fig_caption(f'{s.stem} on the {DEVICE.split(",")[0]} (screenshot taken by the test at the end of the case)')]
history = sorted(p.name for p in (HERE / 'device_evidence').iterdir() if p.is_dir() and p.name not in RUNS)
run_lines = '; '.join(f'{n} ({t}, started {st}): device runner "+{r[1]}{" -" + r[2] if r[2] else ""}: {r[3]}" after {r[0]}'
                      for n, st, t, r in run_info)
before(i_555, [
    caption(f'Execution results for Modules 4, 5 and 6 (verified on {started[:10]})'), table_from(TPL['results'], res_rows), spacer(),
    par('normal', f'Real-device runs on {DEVICE}, each started with integration_test/run_on_device.sh (flutter drive --keep-app-running): '
                  f'{run_lines}. The runner counts include the framework\'s own tear-down step. Per-case results, durations and screenshots are in '
                  f'docs/chapter5/device_evidence/<run>/. Earlier runs ({", ".join(history)}) are kept as evidence and are not counted: they failed '
                  'because of defects in the test code (a screenshot call without a frame, a finder that looked for a semantic label instead of a '
                  'tooltip, a time formatted differently from the screen, a flow that assumed today is a training day), which were corrected, '
                  'and one combined run lost its debug connection to the phone midway. In the counted runs only the first case of each run '
                  'saved a screenshot: the helper converted the Android surface once per run although the framework resets it after every '
                  'test (corrected in the helper; results are unaffected, screenshots are evidence only); '
                  'the application was not changed to make tests pass. The headless figures above come from the ATC_LOG run of the same day; the '
                  'historical team results in Table 5.31 are not repeated here.'),
    *figs, spacer()])

# ---------------------------------------------------------------- 5.5.5 RTM and 5.5.6 limitations
order = (['M3-FR7', 'M4-FR1', 'M4-FR2', 'M4-FR5', 'M4-FR6', 'M4-SFR1', 'M4-SFR2', 'M4-SFR3', 'M4-SFR4'] +
         sorted([f'M5-{k}' for k in fr if k.startswith(('FR15', 'FR16', 'FR17', 'FR18'))], key=lambda s: [int(x) for x in s[5:].split('.')]) +
         ['M5-SFR1', 'M5-SFR2', 'M5-SFR3'] + sorted([f'M6-{k}' for k in fr if k.startswith('FR19')]) + ['M6-SFR1', 'M6-SFR2', 'M6-SFR3'])
feature = {'M3': 'Home Dashboard (navigation)', 'M4': 'Workout & Exercise (plan generation)', 'M5': 'Posture Detection', 'M6': 'Voice Assistant'}
# Cases that also verify further requirements: each one asserts the labels/values of those requirements explicitly.
ALSO = {
    'ATC-M5-F09': ['M5-FR18.1', 'M5-FR18.2', 'M5-FR18.3'], 'ATC-M5-F10': ['M5-FR17.3', 'M5-FR17.4'],
    'ATC-M5-F05': ['M5-FR15.1', 'M5-FR15.2'], 'ATC-M5-F07': ['M5-FR15.2'], 'ATC-M5-F08': ['M5-FR16.4', 'M5-FR16.6'],
    'ATC-M6-F01': ['M6-FR19.2'], 'ATC-M6-F02': ['M6-FR19.5'],
    'ATC-DEV-M5-05': ['M5-FR15.2'], 'ATC-DEV-M5-06': ['M5-FR16.6'], 'ATC-DEV-M5-07': ['M5-FR17.3', 'M5-FR17.4'],
    'ATC-DEV-M6-01': ['M6-FR19.2'], 'ATC-DEV-M6-02': ['M6-FR19.5'],
}
rtm_rows = []
for r in order:
    ids = ([i for i, c in atc.items() if c['req'] == r or r in ALSO.get(i, [])] +
           [i for i, c in dev.items() if c['req'] == r or r in ALSO.get(i, [])])
    if r == 'M5-FR18.4':
        rtm_rows.append([r, req_text(r), feature['M5'], '-', '-', 'No', 'Not implemented in this release (no test)'])
        continue
    if not ids:
        rtm_rows.append([r, req_text(r), feature[r[:2]], '-', '-', 'No', 'Not covered by an automated case'])
        continue
    cats = sorted({category(i) for i in ids})
    state = {i: ('Passed' if atc[i]['ok'] else 'Failed') if i in atc else dev[i]['status'] for i in ids}
    passed = sum(v == 'Passed' for v in state.values())
    failed = sum(v == 'Failed' for v in state.values())
    blocked = sum(v == 'Blocked' for v in state.values())
    run = passed + failed
    status = f'Fail ({failed} of {run} failed)' if failed else (f'Pass ({passed}/{run})' if run else 'Not run')
    if blocked:
        status += f'; Blocked ({blocked})'
    tools = sorted({'Flutter test' if i in atc else 'Flutter integration_test (real device)' for i in ids})
    rtm_rows.append([r, req_text(r), f'{feature[r[:2]]}; {", ".join(cats)}', ', '.join(ids), '; '.join(tools), 'Yes', status])
before(sect, [
    caption('Requirement Traceability Matrix for Modules 4, 5 and 6'), table_from(TPL['rtm'], rtm_rows, status_col=6), spacer(),
    par('h3_55', '5.5.6 Scope and limitations of the Modules 4, 5 and 6 evidence'),
    par('normal', 'Posture detection: the engine cases use synthetic landmark frames and the real-photo replay uses landmarks from public-domain '
                  'exercise photos (held-out half: 66 % of repetitions counted, 13 % false alarms); they test the counting, timing and feedback logic. '
                  'The real-device cases show that the camera and on-device MediaPipe start, run and stop on the phone and that results reach the plan; '
                  'they were run without a person exercising in front of the camera, so their rep counts are not accuracy evidence. Real-person '
                  'validation is tracked separately (docs/chapter5/REAL_PERSON_VALIDATION.md): only the squat has a live check (2026-10-15); the other '
                  'representative exercises have not been performed and are not claimed.'),
    par('normal', 'Voice assistant: headless cases use a simulated recogniser and speech output. On the phone, the real speech and text-to-speech '
                  'engines were used, and quick-action chips supplied fixed phrases; nothing was spoken to the phone, so this is not live speech-'
                  'recognition validation. The microphone permission of the test build was not granted on the phone during the run; the case asserted '
                  'the app\'s "Voice input unavailable" path, and the listening path is covered only by the headless cases. Permission dialogs were '
                  'never answered by the tests; the camera-denied case simulates the answer inside the app.'),
    par('normal', 'Workout plan: rule cases show the screening and safety rules are applied as written (rule set pending professional review); '
                  'they are not evidence of clinical safety. Saving to the cloud (plan regeneration save, "Mark done", session upload) was not '
                  'exercised on the device because the tests never sign in; the app\'s offline message was asserted instead. The day-level '
                  'completion mark is only set on the plan\'s own weekday, which was a rest day on the test date. M5-FR18.4 (injury-risk notice) is '
                  'not implemented. Requirement IDs marked "added" (SFR) were added during implementation and are not yet in Chapter 2.'),
])

# ---------------------------------------------------------------- aggregate counts (the only edits to existing content)
def cellp(tbl_el, r, c):
    return Table(tbl_el, d).rows[r].cells[c].paragraphs[0]

def set_count(tbl_el, r, c, old, new):
    p = cellp(tbl_el, r, c)
    assert p.text == str(old), (r, c, p.text, old)
    set_par_text(p._p, str(new))

counts = {k: sum(1 for i in atc if re.match(p, i)) for k, p in
          [('unit', r'ATC-M[456]-U'), ('functional', r'ATC-M[456]-F'), ('rules', r'ATC-M[456]-B'), ('integration', r'ATC-INT')]}
t51 = orig[next_tbl(0)]
rows51 = {r: [c.text for c in row.cells] for r, row in enumerate(Table(t51, d).rows)}
assert rows51[5][2] == '289', rows51
add = {1: (counts['unit'], counts['unit'], 0, 0), 2: (counts['functional'] + len(dev_func), counts['functional'] + ok_func, fail_func, blk_func),
       3: (counts['rules'], counts['rules'], 0, 0), 4: (counts['integration'] + len(dev_int), counts['integration'] + ok_int, fail_int, blk_int)}
tot = [0, 0, 0, 0]
for r, (n, ok, fl, nr) in add.items():
    old = [int(x) for x in rows51[r][2:6]]
    new = [old[0] + n, old[1] + ok, old[2] + fl, old[3] + nr]
    for c, (o, v) in enumerate(zip(old, new)):
        if o != v:
            set_count(t51, r, c + 2, o, v)
    tot = [a + b for a, b in zip(tot, new)]
old_tot = [int(x) for x in rows51[5][2:6]]
for c, (o, v) in enumerate(zip(old_tot, tot)):
    if o != v:
        set_count(t51, 5, c + 2, o, v)
after(next_tbl(0), [par('normal', f'Counts updated for Modules 4, 5 and 6: the {n_atc} headless Flutter cases already listed in Sections 5.1-5.4 '
                                  f'({counts["unit"]} unit, {counts["functional"]} functional, {counts["rules"]} business-rule, {counts["integration"]} '
                                  f'integration; {ok_atc} passed on re-run) and {len(dev)} real-device integration_test cases ({len(dev_func)} functional, '
                                  f'{len(dev_int)} integration; {ok_func + ok_int} passed, {fail_func + fail_int} failed, {blk_func + blk_int} not run).')])
t531 = orig[next_tbl(i_cap31)]
r531 = [[c.text for c in row.cells] for row in Table(t531, d).rows]
assert r531[1][0].startswith('Flutter test') and r531[1][1] == '203' and r531[4][1] == '289', r531
set_count(t531, 1, 1, 203, 203 + n_atc)
set_count(t531, 1, 2, 203, 203 + ok_atc)
set_count(t531, 4, 1, 289, 289 + n_atc)
set_count(t531, 4, 2, 289, 289 + ok_atc)
after(next_tbl(i_cap31), [par('normal', f'Table 5.31 counts the headless Flutter cases; the {n_atc} Modules 4-6 cases were added to the Flutter row. '
                                        'The real-device integration_test run is reported separately below and is not double-counted here.')])

d.save(str(OUT))
print('wrote', OUT.name, '| tables to 5.%d | figures to 5.%d | atc %d/%d | device %d passed of %d' % (
    table_no[0], fig_no[0], ok_atc, n_atc, ok_func + ok_int, len(dev)))

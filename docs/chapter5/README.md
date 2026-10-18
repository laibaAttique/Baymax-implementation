# Chapter 5: Modules 4, 5 and 6 testing documentation

## Deliverables

| File | What it is |
|---|---|
| `Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx` | Completed chapter, generated from the team's merged base |
| `Baymax_Chapter5_Complete_Testing_Modules_4_5_6.pdf`, `pages/` | Word export (76 pages) and page images used for the layout check |
| `base_Baymax_Chapter5complete_Test_Cases.docx` | Exact copy of the base supplied on 2026-10-18 (never edited) |
| `CHANGE_REPORT.md` | Every insertion, the only edited cells, the test-run history |
| `results/integrity_report.json` | Output of `tools/verify_integrity_device.py` |
| `REAL_PERSON_VALIDATION.md` | Real-person posture validation status (separate from automated tests) |

## Evidence

| Folder / file | Content |
|---|---|
| `results/atc_m456.jsonl` | 123 headless Flutter ATC results of Modules 4-6 (ATC_LOG); `flutter_m456_junit.xml`, `flutter_m456_reporter.json` |
| `results/flutter_full_regression_*` | Complete headless app run (JSON reporter + JUnit XML) |
| `device_evidence/<run>/` | Real-device runs: `device.txt`, `flutter_drive.log`, `device_results.json`, `device_junit.xml`, `screenshots/` |

Counted device runs: `run3_smoke`, `run6_module4_workout`, `run7_module5_posture`, `run6_module6_voice`, `run7_cross_module`.
The others are kept as history (see CHANGE_REPORT.md).

## Regenerate

Headless (from `app/`; delete the old `atc_m456.jsonl` first, the log is appended to):

```bash
ATC_LOG=../docs/chapter5/results/atc_m456.jsonl flutter test test/atc/atc_m456_unit_test.dart test/atc/atc_m456_functional_test.dart test/atc/atc_m456_rules_test.dart test/atc/atc_m456_integration_test.dart
```

Real device (from `app/`, phone connected; see `app/integration_test/README.md`):

```bash
bash integration_test/run_on_device.sh integration_test/module5_posture_test.dart run8_module5_posture
```

Document (from `docs/chapter5`; needs python-docx, lxml):

```bash
python tools/build_chapter5_device.py run3_smoke run6_module4_workout run7_module5_posture run6_module6_voice run7_cross_module
```

```bash
python tools/verify_integrity_device.py
```

`tools/device_results_to_junit.py <run folder>` converts a device run to JUnit XML; `tools/flutter_json_to_junit.py` does the same for
headless runs. These are format conversions only; no Java JUnit is used.

The previous round's files (`Baymax_Chapter5_Test_Cases.original.docx`, `tools/build_chapter5.py`, `tools/verify_integrity.py`,
the Appium suite in `automation/appium/`) belong to the earlier version of the chapter and are not used for this document.

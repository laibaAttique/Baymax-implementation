# Chapter 5: Modules 4, 5 and 6 testing documentation

| File | What it is |
|---|---|
| `Baymax_Chapter5_Test_Cases.original.docx` | Byte-identical copy of the team's original (`~/Downloads/Baymax_Chapter5_Test_Cases.docx`, SHA-256 `392b3df0…a162`). Never edited. |
| `Baymax_Chapter5_Complete_Testing_Modules_4_5_6.docx` | The completed chapter (generated). |
| `Baymax_Chapter5_Complete_Testing_Modules_4_5_6.pdf`, `pages/` | Word export (71 pages) and page images used for the visual check. |
| `CHANGE_REPORT.md` | Every insertion and the only edited cells. |
| `results/atc_m456.jsonl` | The 123 Flutter ATC results (ATC_LOG output); the DOCX tables are generated from it. |
| `results/flutter_m456_junit.xml`, `results/flutter_m456_reporter.json`, `results/flutter_m456_run.txt` | Same run as JUnit XML, raw JSON reporter output and console text. |
| `results/flutter_full_regression_*` | Complete app test run (all modules). |
| `results/integrity_report.json` | Output of `tools/verify_integrity.py`. |
| `figures/` | Figure 5.2 (rendered from the console log). Figure 5.3 is `automation/appium/screenshots/device_smoke_dashboard.png`. |
| `tools/build_chapter5.py` | Builds the DOCX from the original + results. |
| `tools/verify_integrity.py` | Checks the original is preserved (all 241 body elements unchanged and in order). |
| `tools/flutter_json_to_junit.py` | Flutter JSON reporter → JUnit XML. |

## Regenerate

```bash
cd app
ATC_LOG=../docs/chapter5/results/atc_m456.jsonl flutter test test/atc/atc_m456_unit_test.dart test/atc/atc_m456_functional_test.dart test/atc/atc_m456_rules_test.dart test/atc/atc_m456_integration_test.dart
```

(delete the old `atc_m456.jsonl` first; the log is appended to), then from `docs/chapter5`:

```bash
python tools/build_chapter5.py
```

```bash
python tools/verify_integrity.py
```

Needs `python-docx`, `lxml` and `Pillow`. The real-device suite and its status are described in `automation/appium/README.md`.

## What the evidence does and does not show

- Posture cases use synthetic landmark frames and real-photo replays: they test the logic, not live detection accuracy (only the squat has a live device check).
- Voice cases use a simulated recogniser and speech output: not microphone or recognition-accuracy validation.
- Safety-rule cases show the rules run as written; they are not evidence of clinical safety.
- The 12 Appium cases are Blocked by the phone (MIUI security setting) and are never counted as passed.
- M5-FR18.4 (injury-risk notice) is not implemented.

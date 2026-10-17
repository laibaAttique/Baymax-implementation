# Baymax: Chapter 5 test cases (60% implementation)

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
289 automated test cases: 289 passed, 0 failed, 0 not run.
Unit 105 - Functional 73 - Business rules 84 - Integration 27.

## Run again
```
tools/run_all.sh          # ATC suites (about 3 minutes); starts and stops the Firebase emulators itself
tools/run_all.sh --full   # also the complete flutter test and npm test suites
```
Needs: Flutter, Node, the Firebase CLI and Java (for the emulator). Run one e2e file at a time (they reset the same emulator database).

## What this does NOT show
- Nothing was run on a physical phone. The Flutter tests are headless widget tests.
- The end-to-end tests run on local emulators, not the live Firebase project.
- `test_code/` also holds 55 passing regression cases for Modules 10, 11 and 15, which are outside this chapter's module list; they are not in the document or the CSVs.
- Screens' look and feel, OCR with the Google Vision key, camera and the food photo model are not covered.
- Requirement IDs follow the merged report; FR-11 to FR-15 of Module 14 and FR-10 of Module 12 are requirements added during the build and are not in Chapter 2 yet (marked "added" in the RTM). The report's second "FR-6" in Module 2 is treated as FR-7.

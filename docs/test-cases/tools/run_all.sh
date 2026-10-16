#!/bin/zsh
# Runs every automated test case and writes the raw results next to this script (../results/raw).
#   ./run_all.sh          the ATC suites only (about 3 minutes)
#   ./run_all.sh --full   also the complete existing suites (flutter test, npm test)
# The end-to-end cases need the Firebase emulators; this script starts them if they are not running and stops them afterwards.
set -u
HERE="${0:A:h}"
ROOT="${HERE:h}"
APP="$HOME/Downloads/baymaxxxx 2/untitled folder/app"
API="$HOME/Downloads/baymax-api"
RAW="$ROOT/results/raw"
rm -rf "$RAW"; mkdir -p "$RAW"

for s in unit functional rules integration; do
  (cd "$APP" && ATC_LOG="$RAW/dart_$s.jsonl" flutter test "test/atc/atc_${s}_test.dart" --reporter expanded > "$RAW/dart_$s.console.txt" 2>&1)
  tail -1 "$RAW/dart_$s.console.txt"
done

(cd "$API" && ATC_LOG="$RAW/api.jsonl" node --test test/atc/ > "$RAW/api.console.txt" 2>&1)
grep -E "^ℹ (tests|pass|fail)" "$RAW/api.console.txt" | tr '\n' ' '; echo

STARTED=0
if ! nc -z 127.0.0.1 9000 2>/dev/null; then
  cp "$APP/database.rules.json" "$API/emulator/"
  (cd "$API/emulator" && nohup firebase emulators:start --only auth,database --project demo-baymax > "$RAW/emulators.log" 2>&1 &)
  STARTED=1
  for i in {1..60}; do nc -z 127.0.0.1 9000 2>/dev/null && nc -z 127.0.0.1 9099 2>/dev/null && break; sleep 2; done
fi
# one file at a time: every file resets the same emulator database
for f in rules flow admin-account; do
  (cd "$API/e2e" && perl -e 'alarm 240; exec @ARGV' node --test --test-force-exit --test-reporter=junit --test-reporter-destination="$RAW/e2e-$f.xml" --test-reporter=spec --test-reporter-destination="$RAW/e2e-$f.console.txt" "$f.e2e.mjs" > /dev/null 2>&1)
  grep -E "^ℹ (tests|pass|fail)" "$RAW/e2e-$f.console.txt" | tr '\n' ' '; echo
done
if [ "$STARTED" = 1 ]; then pkill -f "firebase emulators:start" ; pkill -f cloud-firestore-emulator; pkill -f firebase-database-emulator; fi

if [ "${1:-}" = "--full" ]; then
  (cd "$APP" && flutter test --reporter expanded > "$RAW/flutter_full.console.txt" 2>&1); tail -1 "$RAW/flutter_full.console.txt"
  (cd "$API" && npm test > "$RAW/api_full.console.txt" 2>&1); grep -E "^ℹ (tests|pass|fail)" "$RAW/api_full.console.txt" | tr '\n' ' '; echo
fi
python3 "$HERE/generate_report.py"

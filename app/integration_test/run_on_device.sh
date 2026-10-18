#!/usr/bin/env bash
# Runs one real-device integration test target with `flutter drive` and keeps the evidence.
#   integration_test/run_on_device.sh <target.dart> <run-name> [device-id]
# Evidence goes to docs/chapter5/device_evidence/<run-name>/: flutter_drive.log, device.txt, device_results.json, screenshots/.
# --keep-app-running is REQUIRED: without it `flutter drive` stops AND UNINSTALLS the app when the run ends, which deletes the
# phone owner's local app data (sign-in). With it the test build stays installed; reinstall the normal app afterwards
# (flutter build apk --debug, then adb install -r build/app/outputs/flutter-apk/app-debug.apk) so the phone opens Baymax again.
# NOTE: the driver's final "All tests passed" line is not used as the result; summarize_device_runs.py reads the device-side
# test runner lines ("+N -M") and the per-case [device-case] records.
set -u
target="${1:?target, e.g. integration_test/smoke_test.dart}"
name="${2:?run name}"
device="${3:-f3fd6781}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/../docs/chapter5/device_evidence/$name"
mkdir -p "$out"
export ANDROID_HOME="${ANDROID_HOME:-D:/android-sdk}" BAYMAX_EVIDENCE_DIR="$out"
adb="$ANDROID_HOME/platform-tools/adb"
{
  echo "started: $(date -Iseconds)"
  echo "target: $target"
  echo "command: flutter drive --driver=test_driver/integration_test.dart --target=$target -d $device --keep-app-running"
  echo "device: $device model=$("$adb" -s "$device" shell getprop ro.product.model | tr -d '\r') android=$("$adb" -s "$device" shell getprop ro.build.version.release | tr -d '\r') sdk=$("$adb" -s "$device" shell getprop ro.build.version.sdk | tr -d '\r') miui=$("$adb" -s "$device" shell getprop ro.miui.ui.version.name | tr -d '\r')"
  flutter --version 2>/dev/null | head -4
} > "$out/device.txt"
cd "$here"
flutter drive --driver=test_driver/integration_test.dart --target="$target" -d "$device" --keep-app-running > "$out/flutter_drive.log" 2>&1
echo "exit $?" >> "$out/flutter_drive.log"
echo "finished: $(date -Iseconds)" >> "$out/device.txt"
grep -E "\[device-case\]|\[device-step\] .*(passed|failed)|I/flutter.*: [0-9]{2}:[0-9]{2} \+[0-9]+.*(\[E\]|tests passed|tests failed)|^exit " "$out/flutter_drive.log" | cut -c1-400

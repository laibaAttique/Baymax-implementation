import 'dart:convert';
import 'dart:io';

import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_pose_eval.dart';

/// Real-pose replay: MediaPipe landmarks of REAL people (free-exercise-db photos, start and end position), detected
/// on the phone by integration_test/dataset_pose_validation_test.dart and stored in test/fixtures/real_poses.json.
/// Every run replays them through the production analyzer and engine.
///
/// Exercises are split deterministically into a calibration half and a held-out half; thresholds were tuned on the
/// calibration half only, and the gates below are checked on the held-out half (so the numbers are not fitted to the
/// data they report). Static photos: this measures detection, rep-range coverage and false alarms on correct form —
/// not fault sensitivity or tracking at speed.
///
///   BAYMAX_WRITE_REVIEW=1 flutter test test/real_pose_replay_test.dart     → docs/review/real_pose_validation.{json,md}
///   BAYMAX_DUMP_MEASURES=1 flutter test test/real_pose_replay_test.dart    → build/real_pose_measures.json (calibration)

bool heldOut(String id) => id.codeUnits.fold(0, (s, c) => (s * 31 + c) & 0x7fffffff) % 2 == 1;

class _Stats {
  int n = 0, span = 0, counted = 0, inPos = 0, alarmed = 0, holds = 0;
  final Map<String, int> alarms = {};
  int? pct(int v, int d) => d == 0 ? null : (100 * v / d).round();
  Map<String, Object?> toJson() => {
        'pairs': n,
        if (n > holds) 'repSpanPct': pct(span, n - holds),
        if (n > holds) 'repCountedPct': pct(counted, n - holds),
        if (holds > 0) 'inPositionPct': pct(inPos, holds),
        'anyFalseAlarmPct': pct(alarmed, n),
        'falseAlarmPctByCheck': {for (final e in alarms.entries) e.key: pct(e.value, n)},
      };
}

void main() {
  test('real people: rep coverage and false alarms on correct form (held-out half)', () {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    final fixture = jsonDecode(File('test/fixtures/real_poses.json').readAsStringSync()) as Map<String, dynamic>;
    final rows = (fixture['exercises'] as List).cast<Map<String, dynamic>>();
    expect(rows.length, greaterThan(200));

    final splits = {'calibration': <String, _Stats>{}, 'heldOut': <String, _Stats>{}};
    final totals = {'calibration': _Stats(), 'heldOut': _Stats()};
    final perExercise = <Map<String, Object?>>[];
    final dump = <Map<String, Object?>>[];
    for (final r in rows) {
      final e = ExerciseRepository.byId(r['id'] as String);
      if (e == null) continue;
      final posture = ExerciseRepository.postureFor(e);
      final cfg = posture.form;
      if (cfg == null || posture.scoreValidated) continue; // the 4 validated configurations are not re-tuned here
      final frames = (r['frames'] as List).cast<Map<String, dynamic>>();
      final res = evaluatePair(cfg, frameFromJson(frames[0], 0), frameFromJson(frames[1], 0));
      if (!res.measurable) continue;
      final split = heldOut(e.id) ? 'heldOut' : 'calibration';
      for (final s in [splits[split]!.putIfAbsent(posture.movementPattern.name, _Stats.new), totals[split]!]) {
        s.n++;
        if (res.isHold) {
          s.holds++;
          if (res.inPosition) s.inPos++;
        } else {
          if (res.span) s.span++;
          if (res.repCounted) s.counted++;
        }
        if (res.falseAlarms.isNotEmpty) s.alarmed++;
        for (final a in res.falseAlarms) {
          s.alarms[a] = (s.alarms[a] ?? 0) + 1;
        }
      }
      perExercise.add({
        'id': e.id,
        'name': e.name,
        'pattern': posture.movementPattern.name,
        'split': split,
        'angles': [res.a0?.round(), res.a1?.round()],
        if (res.isHold) 'inPosition': res.inPosition else 'repCounted': res.repCounted,
        'falseAlarms': res.falseAlarms,
        'notApplicable': res.notApplicable,
      });
      dump.add({'id': e.id, 'pattern': posture.movementPattern.name, 'split': split, ...res.measures});
    }

    final report = {
      'source': fixture['source'],
      'method': 'two real photos per exercise (start/end); production MediaPipe landmarks replayed through the production '
          'engine; thresholds tuned on the calibration half, reported on the held-out half',
      'totals': {for (final e in totals.entries) e.key: e.value.toJson()},
      'patterns': {
        for (final e in splits.entries) e.key: {for (final p in e.value.entries) p.key: p.value.toJson()},
      },
      'exercises': perExercise,
    };
    if (Platform.environment['BAYMAX_DUMP_MEASURES'] == '1') {
      Directory('build').createSync(recursive: true);
      File('build/real_pose_measures.json').writeAsStringSync(jsonEncode(dump));
    }
    if (Platform.environment['BAYMAX_WRITE_REVIEW'] == '1') {
      File('docs/review/real_pose_validation.json').writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(report)}\n');
      File('docs/review/real_pose_validation.md').writeAsStringSync(_markdown(report));
    }
    // ignore: avoid_print
    print('real-pose totals: ${jsonEncode(report['totals'])}');

    // Regression gates on the held-out half.
    final held = totals['heldOut']!;
    expect(held.n, greaterThan(80));
    expect(held.pct(held.counted, held.n - held.holds)!, greaterThanOrEqualTo(_gateRepCounted),
        reason: 'held-out real pairs whose rep is counted');
    expect(held.pct(held.alarmed, held.n)!, lessThanOrEqualTo(_gateFalseAlarm), reason: 'held-out real pairs with any false alarm');
  });
}

/// Set from the calibrated run (see docs/MODULE5_DEVICE_VALIDATION.md); a change that makes real-pose results worse fails.
/// Calibrated run 2026-10-18, held-out half: reps counted 66 %, pairs with any false alarm 13 %.
const _gateRepCounted = 60;
const _gateFalseAlarm = 18;

String _markdown(Map<String, Object?> report) {
  final b = StringBuffer()
    ..writeln('# Real-pose validation (generated)')
    ..writeln()
    ..writeln('${report['method']}.')
    ..writeln()
    ..writeln('Source: ${report['source']}.')
    ..writeln()
    ..writeln('| Split | Pairs | Rep counted | Any false alarm on correct form |')
    ..writeln('|---|---|---|---|');
  for (final e in (report['totals'] as Map).entries) {
    final t = e.value as Map;
    b.writeln('| ${e.key} | ${t['pairs']} | ${t['repCountedPct']}% | ${t['anyFalseAlarmPct']}% |');
  }
  b
    ..writeln()
    ..writeln('## Held-out half, by movement pattern')
    ..writeln()
    ..writeln('| Pattern | Pairs | Rep counted / in position | False alarms on correct form |')
    ..writeln('|---|---|---|---|');
  final held = ((report['patterns'] as Map)['heldOut'] as Map);
  for (final e in held.entries) {
    final s = e.value as Map;
    final counted = s.containsKey('inPositionPct') ? '${s['inPositionPct']}% in position' : '${s['repCountedPct']}%';
    final alarms = (s['falseAlarmPctByCheck'] as Map).entries.map((a) => '${a.key} ${a.value}%').join(', ');
    b.writeln('| ${e.key} | ${s['pairs']} | $counted | ${alarms.isEmpty ? 'none' : alarms} |');
  }
  b
    ..writeln()
    ..writeln('Static photos only: fault sensitivity (does a real mistake trigger the correction?) and tracking at '
        'speed still need the live checklist (MODULE5_DEVICE_TEST_CHECKLIST.md).');
  return b.toString();
}

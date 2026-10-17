import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';

import '../models/plan.dart';
import '../models/workout_readiness.dart';
import 'realtime_db.dart';

/// Where the readiness answers and the generated plan snapshot are kept (Module 4).
abstract class WorkoutReadinessStore {
  /// Null when the person has never answered.
  Future<WorkoutReadiness?> load();
  Future<void> save(WorkoutReadiness readiness);

  /// Stores [snapshot] as the current plan unless it is identical to the stored one. Returns true if written.
  Future<bool> savePlanSnapshot(Map<String, Object?> snapshot);
}

/// `users/{uid}/workoutReadiness` and `users/{uid}/workoutPlan`, protected by the per-user rules in database.rules.json.
class FirebaseWorkoutReadinessStore implements WorkoutReadinessStore {
  FirebaseWorkoutReadinessStore._();
  static final FirebaseWorkoutReadinessStore instance = FirebaseWorkoutReadinessStore._();

  String? _lastSnapshotHash;

  @override
  Future<WorkoutReadiness?> load() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('workoutReadiness').get();
      if (!snap.exists) return null;
      return WorkoutReadiness.fromJson(Map<String, dynamic>.from(RealtimeDb.plain(snap.value) as Map));
    });
  }

  @override
  Future<void> save(WorkoutReadiness readiness) {
    return RealtimeDb.guard(
        () => RealtimeDb.userRef('workoutReadiness').set({...readiness.toJson(), 'updatedAt': ServerValue.timestamp}));
  }

  @override
  Future<bool> savePlanSnapshot(Map<String, Object?> snapshot) async {
    final hash = snapshot['fingerprint'] as String?;
    if (hash == _lastSnapshotHash) return false;
    await RealtimeDb.guard(() => RealtimeDb.userRef('workoutPlan').set({...snapshot, 'savedAt': ServerValue.timestamp}));
    _lastSnapshotHash = hash;
    return true;
  }
}

/// A compact, versioned record of the generated plan: what was scheduled, with which rule/catalogue versions and for
/// which health snapshot. No free-text health data is stored here (the profile already holds it).
class WorkoutPlanSnapshot {
  WorkoutPlanSnapshot._();

  static const engineVersion = 'workout-engine-2026.10.1';

  static Map<String, Object?> build({
    required PersonalizedPlan plan,
    required String goal,
    required String catalogCommit,
    required int profileUpdatedAt,
    required double weightKg,
  }) {
    final days = <String, Object?>{};
    for (var i = 0; i < plan.week.length; i++) {
      final d = plan.week[i];
      if (d == null) continue;
      days['$i'] = {
        'name': d.name,
        'kcal': d.kcal(weightKg),
        'minutes': d.durationMin,
        'exercises': {
          for (var k = 0; k < d.exercises.length; k++)
            '$k': {
              'id': d.exercises[k].exercise.id,
              'sets': d.exercises[k].sets,
              'reps': d.exercises[k].reps,
              'seconds': d.exercises[k].seconds,
              'rest': d.exercises[k].restSeconds,
            },
        },
      };
    }
    final fingerprint = {
      'engine': engineVersion,
      'rules': plan.rulesVersion,
      'catalog': catalogCommit,
      'classification': plan.category,
      'intensity': plan.intensity,
      'goal': goal,
      'variant': plan.variant,
      'gate': plan.gate?.status.name ?? 'notScreened',
      'days': days,
    };
    return {
      'engineVersion': engineVersion,
      'rulesVersion': plan.rulesVersion,
      'catalogCommit': catalogCommit,
      'classification': plan.category,
      'intensity': plan.intensity,
      'goal': goal,
      'variant': plan.variant,
      'gate': plan.gate?.status.name ?? 'notScreened',
      'profileUpdatedAt': profileUpdatedAt,
      'days': days,
      'fingerprint': fingerprintOf(fingerprint),
    };
  }

  /// FNV-1a over the canonical JSON: the same plan always gives the same value, on every device and run.
  static String fingerprintOf(Map<String, Object?> value) {
    var h = 0x811c9dc5;
    for (final unit in utf8.encode(jsonEncode(value))) {
      h ^= unit;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

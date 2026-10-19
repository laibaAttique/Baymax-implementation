import 'package:firebase_database/firebase_database.dart';

import '../../models/workout_session.dart';
import '../realtime_db.dart';

/// A saved session as read back from the database.
class WorkoutLogEntry {
  final String id;
  final String exerciseId;
  final String exerciseName;
  final SessionMode mode;
  final DateTime endedAt;
  final Duration duration;
  final int reps;
  final int? postureScore;
  final bool tooDifficult;

  /// Set when the session was started from the user's plan (see [PlanLink]).
  final String? planId;
  final String? planDate;
  final int? planWeekday;
  final int? planEntry;
  final bool planCompleted;

  const WorkoutLogEntry({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.mode,
    required this.endedAt,
    required this.duration,
    required this.reps,
    this.postureScore,
    this.tooDifficult = false,
    this.planId,
    this.planDate,
    this.planWeekday,
    this.planEntry,
    this.planCompleted = false,
  });

  factory WorkoutLogEntry.fromJson(String id, Map<String, dynamic> j) => WorkoutLogEntry(
        id: id,
        exerciseId: j['exerciseId'] as String,
        exerciseName: j['exerciseName'] as String,
        mode: j['mode'] == 'camera' ? SessionMode.camera : SessionMode.manual,
        endedAt: DateTime.fromMillisecondsSinceEpoch((j['endedAt'] as num).toInt()),
        duration: Duration(seconds: (j['durationSec'] as num).toInt()),
        reps: (j['reps'] as num).toInt(),
        postureScore: (j['postureScore'] as num?)?.toInt(),
        tooDifficult: j['tooDifficult'] as bool? ?? false,
        planId: j['planId'] as String?,
        planDate: j['planDate'] as String?,
        planWeekday: (j['planWeekday'] as num?)?.toInt(),
        planEntry: (j['planEntry'] as num?)?.toInt(),
        planCompleted: j['planCompleted'] as bool? ?? false,
      );
}

/// Where finished sessions and "Too Difficult" flags are stored.
abstract class WorkoutLogStore {
  Future<void> save(SessionSummary summary);

  /// Report FR17.4: remember that the user found [exerciseId] too difficult so
  /// the next plan generation makes it easier.
  Future<void> markTooDifficult(String exerciseId);

  /// Exercises marked too difficult within [WorkoutLog.flagLifetime].
  Future<Set<String>> tooDifficultExercises();

  /// Most recent sessions first.
  Future<List<WorkoutLogEntry>> recent({int limit = 20});

  /// Sessions that ended at or after [from], oldest first (used for today's plan progress).
  Future<List<WorkoutLogEntry>> since(DateTime from);
}

/// Converts a summary to the shape accepted by `database.rules.json`.
class WorkoutLog {
  WorkoutLog._();

  /// A "Too Difficult" mark stops affecting new plans after four weeks, so an
  /// exercise is not hidden forever after one hard day.
  static const flagLifetime = Duration(days: 28);

  /// [withPlan] false leaves the plan link out (fallback while the database rules do not know those fields yet).
  static Map<String, Object?> toJson(SessionSummary s, {bool withPlan = true}) => {
        'exerciseId': s.exercise.id,
        'exerciseName': s.exercise.name,
        'mode': s.mode.name,
        'endedAt': s.endedAt.millisecondsSinceEpoch,
        'durationSec': s.duration.inSeconds,
        'reps': s.reps,
        'partialReps': s.partialReps,
        'setsCompleted': s.setsCompleted,
        'targetSets': s.exercise.sets,
        'targetReps': s.exercise.targetReps,
        if (s.postureScore != null) 'postureScore': s.postureScore,
        if (s.accuracy != null) 'accuracy': s.accuracy,
        if (s.averageFps != null) 'averageFps': double.parse(s.averageFps!.toStringAsFixed(1)),
        'skipped': s.skipped,
        'tooDifficult': s.tooDifficult,
        if (withPlan && s.plan != null) ...{
          'planId': s.plan!.planId,
          'planDate': s.plan!.date,
          'planWeekday': s.plan!.weekday,
          'planEntry': s.plan!.entryIndex,
          'planCompleted': s.completedTarget,
        },
        'feedback': {
          for (var i = 0; i < s.feedback.length; i++)
            '$i': {
              'id': s.feedback[i].id,
              'verdict': s.feedback[i].verdict.name,
              'text': s.feedback[i].text.length > 200 ? s.feedback[i].text.substring(0, 200) : s.feedback[i].text,
            },
        },
      };
}

/// Stores sessions in the Firebase Realtime Database:
/// `users/{uid}/workoutSessions/{pushId}` and
/// `users/{uid}/exerciseFeedback/{exerciseId}`. Only summary numbers and
/// feedback text are stored — never camera frames or landmarks.
class FirebaseWorkoutLog implements WorkoutLogStore {
  FirebaseWorkoutLog._();
  static final FirebaseWorkoutLog instance = FirebaseWorkoutLog._();

  /// False after a save had to leave the plan link out (the live database rules are older than this app).
  bool planLinkAccepted = true;

  @override
  Future<void> save(SessionSummary summary) async {
    final ref = RealtimeDb.userRef('workoutSessions').push();
    if (summary.plan == null) {
      await RealtimeDb.guard(() => ref.set(WorkoutLog.toJson(summary)));
      return;
    }
    try {
      await RealtimeDb.guard(() => ref.set(WorkoutLog.toJson(summary)));
      planLinkAccepted = true;
    } catch (_) {
      // Database rules without the plan fields refuse the whole write; keep the session itself rather than lose it.
      // Same key, so a retry can never create two records.
      await RealtimeDb.guard(() => ref.set(WorkoutLog.toJson(summary, withPlan: false)));
      planLinkAccepted = false;
    }
  }

  @override
  Future<void> markTooDifficult(String exerciseId) {
    return RealtimeDb.guard(() => RealtimeDb.userRef('exerciseFeedback/$exerciseId').set({
          'tooDifficult': true,
          'updatedAt': ServerValue.timestamp,
        }));
  }

  @override
  Future<Set<String>> tooDifficultExercises() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('exerciseFeedback').get();
      if (!snap.exists) return <String>{};
      final cutoff = DateTime.now().subtract(WorkoutLog.flagLifetime).millisecondsSinceEpoch;
      final all = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      return {
        for (final e in all.entries)
          if (e.value is Map && e.value['tooDifficult'] == true && (e.value['updatedAt'] as num? ?? 0) >= cutoff) e.key,
      };
    });
  }

  @override
  Future<List<WorkoutLogEntry>> recent({int limit = 20}) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('workoutSessions').orderByChild('endedAt').limitToLast(limit).get();
      if (!snap.exists) return <WorkoutLogEntry>[];
      final all = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      final entries = [
        for (final e in all.entries) WorkoutLogEntry.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)),
      ]..sort((a, b) => b.endedAt.compareTo(a.endedAt));
      return entries;
    });
  }

  @override
  Future<List<WorkoutLogEntry>> since(DateTime from) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('workoutSessions').orderByChild('endedAt').startAt(from.millisecondsSinceEpoch).get();
      if (!snap.exists) return <WorkoutLogEntry>[];
      final all = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      return [
        for (final e in all.entries) WorkoutLogEntry.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)),
      ]..sort((a, b) => a.endedAt.compareTo(b.endedAt));
    });
  }
}

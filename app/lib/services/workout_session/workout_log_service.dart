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
}

/// Converts a summary to the shape accepted by `database.rules.json`.
class WorkoutLog {
  WorkoutLog._();

  /// A "Too Difficult" mark stops affecting new plans after four weeks, so an
  /// exercise is not hidden forever after one hard day.
  static const flagLifetime = Duration(days: 28);

  static Map<String, Object?> toJson(SessionSummary s) => {
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

  @override
  Future<void> save(SessionSummary summary) {
    return RealtimeDb.guard(() => RealtimeDb.userRef('workoutSessions').push().set(WorkoutLog.toJson(summary)));
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
}

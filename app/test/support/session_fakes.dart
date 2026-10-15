import 'package:app/models/workout_session.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/workout_session/workout_log_service.dart';

/// In-memory [WorkoutLogStore] that can be told to fail.
class FakeStore implements WorkoutLogStore {
  final List<SessionSummary> saved = [];
  final List<String> flagged = [];
  int failSaves = 0;
  int failFlags = 0;

  @override
  Future<void> save(SessionSummary summary) async {
    if (failSaves > 0) {
      failSaves--;
      throw const ApiException('Could not reach the database.');
    }
    saved.add(summary);
  }

  @override
  Future<void> markTooDifficult(String exerciseId) async {
    if (failFlags > 0) {
      failFlags--;
      throw const ApiException('Could not reach the database.');
    }
    flagged.add(exerciseId);
  }

  @override
  Future<Set<String>> tooDifficultExercises() async => flagged.toSet();

  @override
  Future<List<WorkoutLogEntry>> recent({int limit = 20}) async => const [];
}

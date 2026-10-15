import '../../models/plan.dart';
import '../../services/user_session.dart';

/// The exercises a guided session walks through. When a screen is opened without a specific exercise list (the "Posture check"
/// shortcut), today's workout is used, or the first workout day of the week if today is a rest day.
List<PlannedExercise> defaultSessionQueue() {
  final plan = UserSession.instance.plan;
  if (plan == null) return const [];
  final today = plan.workoutFor(DateTime.now());
  final day = today ?? plan.week.firstWhere((d) => d != null, orElse: () => null);
  return day?.exercises ?? const [];
}

/// What happened in a guided session. Only things the app can actually observe are recorded (no posture score without a camera model).
class SessionResult {
  final int total;
  final int completed;
  final int skipped;
  final int setsDone;
  final Duration elapsed;
  const SessionResult({required this.total, required this.completed, required this.skipped, required this.setsDone, required this.elapsed});
}

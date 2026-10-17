import 'movement_pattern.dart';
import 'plan.dart';

/// How an exercise session is being tracked (Module 5).
enum SessionMode { camera, manual }

enum SessionStatus { idle, active, paused, finished }

/// The exercise a session is run for.
///
/// INTEGRATION POINT (Workout Plan module): this is the only thing the posture
/// and voice modules need from a workout plan. Build it with
/// [SessionExercise.fromPlanned] from a plan entry, or
/// [SessionExercise.fromExercise] from a library exercise.
class SessionExercise {
  final String id;
  final String name;
  final String icon;

  /// cardio | legs | push | back | core | mobility
  final String group;
  final List<String> muscles;
  final List<String> steps;

  /// True when the exercise is prescribed by time instead of repetitions.
  final bool timed;
  final int sets;
  final int reps; // per set; 0 when timed
  final int seconds; // per set when timed, else 0
  final int restSeconds;

  /// How the Module 4 safety rules adapted this exercise for the person (e.g. a pain-free range or a capped hold), each
  /// ending with its rule id. Empty when nothing was adapted or the exercise is not from a plan.
  final List<String> safetyNotes;

  /// How the camera can follow this exercise (Module 5). Null when unknown; the curated mapping is used then.
  final MovementPattern? movementValue;
  final NoTrackingReason? noTrackingValue;

  MovementPattern get movement => movementValue ?? curatedMovements[id] ?? MovementPattern.none;
  NoTrackingReason? get noTrackingReason => movement != MovementPattern.none
      ? null
      : (noTrackingValue ?? curatedNoTracking[id] ?? (group == 'mobility' ? NoTrackingReason.stretch : NoTrackingReason.noTracker));

  const SessionExercise({
    required this.id,
    required this.name,
    this.icon = '🏋️',
    this.group = '',
    this.muscles = const [],
    this.steps = const [],
    this.timed = false,
    this.sets = 1,
    this.reps = 0,
    this.seconds = 0,
    this.restSeconds = 0,
    this.safetyNotes = const [],
    this.movementValue,
    this.noTrackingValue,
  });

  factory SessionExercise.fromPlanned(PlannedExercise p) => SessionExercise(
        id: p.exercise.id,
        name: p.exercise.name,
        icon: p.exercise.icon,
        group: p.exercise.group,
        muscles: p.exercise.muscles,
        steps: p.exercise.steps,
        timed: p.timed,
        sets: p.sets,
        reps: p.reps,
        seconds: p.seconds,
        restSeconds: p.restSeconds,
        safetyNotes: p.ruleNotes,
        movementValue: p.exercise.movement,
        noTrackingValue: p.exercise.noTrackingReason,
      );

  /// For an exercise that is not part of a plan. The dose is a neutral default
  /// (the exercise's own base reps/seconds), not a personalised prescription.
  factory SessionExercise.fromExercise(Exercise e, {int sets = 3, int restSeconds = 45}) => SessionExercise(
        id: e.id,
        name: e.name,
        icon: e.icon,
        group: e.group,
        muscles: e.muscles,
        steps: e.steps,
        timed: e.timed,
        sets: sets,
        reps: e.timed ? 0 : e.baseReps,
        seconds: e.timed ? e.baseSeconds : 0,
        restSeconds: restSeconds,
        movementValue: e.movement,
        noTrackingValue: e.noTrackingReason,
      );

  int get targetReps => timed ? 0 : sets * reps;

  /// "3 sets of 12 reps" / "3 sets of 30 seconds".
  String get targetLabel {
    final s = sets == 1 ? '1 set' : '$sets sets';
    return timed ? '$s of $seconds seconds' : '$s of $reps reps';
  }
}

/// Which planned exercise a session belongs to (Module 4 → Module 5). Sessions started from the generic exercise
/// library have none and are saved as independent workouts.
class PlanLink {
  /// The plan's fingerprint (`WorkoutPlanSnapshot`), so a regenerated plan does not inherit old progress.
  final String planId;

  /// 0 = Monday … 6 = Sunday: the plan day the exercise belongs to.
  final int weekday;

  /// Position of the exercise in that day's list (warm-up is 0).
  final int entryIndex;

  /// The calendar day the session is done (YYYY-MM-DD).
  final String date;

  const PlanLink({required this.planId, required this.weekday, required this.entryIndex, required this.date});

  PlanLink get nextEntry => PlanLink(planId: planId, weekday: weekday, entryIndex: entryIndex + 1, date: date);

  @override
  bool operator ==(Object other) =>
      other is PlanLink && other.planId == planId && other.weekday == weekday && other.entryIndex == entryIndex && other.date == date;
  @override
  int get hashCode => Object.hash(planId, weekday, entryIndex, date);
}

/// What the Workout Plan module hands over to start a session.
class WorkoutSessionRequest {
  final SessionExercise exercise;

  /// Exercises that follow in the same workout, in order. Empty when unknown.
  final List<SessionExercise> upNext;

  /// The planned exercise this session completes, when started from the user's plan.
  final PlanLink? plan;

  const WorkoutSessionRequest({required this.exercise, this.upNext = const [], this.plan});

  /// [plan] links the session to the planned entry; the exercises up next get the following entries of the same day.
  factory WorkoutSessionRequest.fromPlanned(PlannedExercise planned, {List<PlannedExercise> upNext = const [], PlanLink? plan}) =>
      WorkoutSessionRequest(
        exercise: SessionExercise.fromPlanned(planned),
        upNext: [for (final p in upNext) SessionExercise.fromPlanned(p)],
        plan: plan,
      );

  /// The request for the next exercise in the sequence, or null at the end.
  WorkoutSessionRequest? get next => upNext.isEmpty
      ? null
      : WorkoutSessionRequest(exercise: upNext.first, upNext: upNext.sublist(1), plan: plan?.nextEntry);
}

enum FeedbackVerdict { passed, failed, notAssessed }

/// One line of the "Form Feedback" list on the session summary.
class FormFeedbackItem {
  final String id;
  final FeedbackVerdict verdict;
  final String text;
  const FormFeedbackItem({required this.id, required this.verdict, required this.text});
}

/// Everything recorded for one finished session. Held in memory only.
class SessionSummary {
  final SessionExercise exercise;
  final SessionMode mode;
  final DateTime endedAt;
  final Duration duration;

  /// Camera mode: repetitions counted by the pose engine.
  /// Manual mode: repetitions the user confirmed.
  final int reps;

  /// Camera mode only: movements that did not reach the required depth.
  final int partialReps;
  final int setsCompleted;

  /// Percentage of attempted repetitions performed with acceptable form
  /// (report FR18.1). Null when posture was not analysed or there is too
  /// little valid data.
  final int? postureScore;

  /// Percentage of valid form-check frames that passed. Null like [postureScore].
  final int? accuracy;
  final List<FormFeedbackItem> feedback;

  /// Measured pose-processing rate for this session (camera mode), if known.
  final double? averageFps;
  final bool skipped;
  final bool tooDifficult;

  /// Camera mode: true when a posture score is given (validated evaluation only).
  final bool formScored;

  /// Camera mode: true when form checks ran (validated or experimental). False for basic tracking.
  final bool formChecked;

  /// Camera mode, static holds: seconds the camera saw the person in position. Null otherwise.
  final int? holdSeconds;

  /// The planned exercise this session belongs to, if any.
  final PlanLink? plan;

  /// True when the planned target was reached (reps, hold time or sets) — only then is the planned exercise complete.
  final bool completedTarget;

  const SessionSummary({
    required this.exercise,
    required this.mode,
    required this.endedAt,
    required this.duration,
    required this.reps,
    this.partialReps = 0,
    this.setsCompleted = 0,
    this.postureScore,
    this.accuracy,
    this.feedback = const [],
    this.averageFps,
    this.skipped = false,
    this.tooDifficult = false,
    this.formScored = true,
    this.formChecked = true,
    this.holdSeconds,
    this.plan,
    this.completedTarget = false,
  });

  bool get postureAnalysed => mode == SessionMode.camera;
}

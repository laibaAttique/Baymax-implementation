import '../../models/movement_pattern.dart';
import '../../models/workout_session.dart';
import 'exercise_form_rules.dart';
import 'pose_landmark.dart';

/// What the camera can do for one exercise (Module 5).
enum CameraSupportLevel {
  /// Repetitions, posture checks and a posture score. Only the configurations that were tried on real movements.
  fullForm,

  /// Repetitions counted from the movement cycle; form is NOT scored.
  basicTracking,

  /// Time in position measured for a static hold; form is NOT scored.
  holdTracking,

  /// The camera cannot follow this exercise reliably; Manual Guidance only.
  notSupported,
}

/// The camera capabilities of one exercise, resolved from its stable id and movement pattern.
class ExercisePostureConfig {
  final String exerciseId;
  final MovementPattern movementPattern;
  final CameraSupportLevel level;

  /// MediaPipe landmark indexes the tracker needs (either body side is enough).
  final List<int> requiredLandmarks;

  /// The tracker configuration; null when [level] is [CameraSupportLevel.notSupported].
  final ExerciseFormConfig? form;
  final String? unsupportedReason;

  const ExercisePostureConfig({
    required this.exerciseId,
    required this.movementPattern,
    required this.level,
    this.requiredLandmarks = const [],
    this.form,
    this.unsupportedReason,
  });

  bool get supportsCameraTracking => level != CameraSupportLevel.notSupported;
  bool get supportsRepCounting => level == CameraSupportLevel.fullForm || level == CameraSupportLevel.basicTracking;
  bool get supportsFormEvaluation => level == CameraSupportLevel.fullForm;
  bool get supportsHoldTiming => level == CameraSupportLevel.holdTracking;
}

/// Movement pattern → tracker. Replaces the old fixed list of four exercise ids: every exercise with a trackable pattern
/// gets a tracker, and the four tried-and-tuned configurations in [ExerciseFormRules] keep their full form evaluation.
///
/// ASSUMPTIONS: the angles below only decide where a movement cycle starts, turns and ends (phase detection). They are
/// starting values chosen by the project team from the usual range of each movement, have not been validated on test
/// subjects, and are not used to judge form or safety — which is why these patterns are "basic tracking" and report no
/// posture score.
class MovementPatterns {
  MovementPatterns._();

  static const _knee = (
    JointTriple(PoseIndex.leftHip, PoseIndex.leftKnee, PoseIndex.leftAnkle),
    JointTriple(PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle),
  );
  static const _elbow = (
    JointTriple(PoseIndex.leftShoulder, PoseIndex.leftElbow, PoseIndex.leftWrist),
    JointTriple(PoseIndex.rightShoulder, PoseIndex.rightElbow, PoseIndex.rightWrist),
  );
  static const _hip = (
    JointTriple(PoseIndex.leftShoulder, PoseIndex.leftHip, PoseIndex.leftKnee),
    JointTriple(PoseIndex.rightShoulder, PoseIndex.rightHip, PoseIndex.rightKnee),
  );
  static const _shoulder = (
    JointTriple(PoseIndex.leftHip, PoseIndex.leftShoulder, PoseIndex.leftElbow),
    JointTriple(PoseIndex.rightHip, PoseIndex.rightShoulder, PoseIndex.rightElbow),
  );
  static const _lineToAnkle = (
    JointTriple(PoseIndex.leftShoulder, PoseIndex.leftHip, PoseIndex.leftAnkle),
    JointTriple(PoseIndex.rightShoulder, PoseIndex.rightHip, PoseIndex.rightAnkle),
  );

  /// Holds done on the knees measure the body line to the knee instead of the ankle.
  static const _kneeSupported = {'side_plank_knee'};

  static const _sideOn = 'Stand side-on to the camera, 2–3 m away, with your whole body in the frame';
  static const _floorSideOn = 'Place the phone at floor level, side-on, with your whole body in the frame';
  static const _upperSideOn = 'Turn side-on to the camera so your shoulder, elbow and wrist are in the frame';
  static const _front = 'Face the camera, 2–3 m away, with your whole body in the frame';

  /// The camera capabilities for [e], from its id and movement pattern.
  static ExercisePostureConfig forSession(SessionExercise e) => resolve(e.id, e.movement, e.noTrackingReason);

  static ExercisePostureConfig resolve(String id, MovementPattern pattern, [NoTrackingReason? reason]) {
    final full = ExerciseFormRules.forExercise(id);
    if (full != null) {
      return ExercisePostureConfig(
        exerciseId: id,
        movementPattern: pattern == MovementPattern.none ? MovementPattern.squat : pattern,
        level: CameraSupportLevel.fullForm,
        requiredLandmarks: _landmarks(full),
        form: full,
      );
    }
    final form = pattern == MovementPattern.none ? null : _basic(id, pattern);
    if (form == null) {
      return ExercisePostureConfig(
        exerciseId: id,
        movementPattern: MovementPattern.none,
        level: CameraSupportLevel.notSupported,
        unsupportedReason: (reason ?? NoTrackingReason.noTracker).text,
      );
    }
    return ExercisePostureConfig(
      exerciseId: id,
      movementPattern: pattern,
      level: form.kind == TrackingKind.hold ? CameraSupportLevel.holdTracking : CameraSupportLevel.basicTracking,
      requiredLandmarks: _landmarks(form),
      form: form,
    );
  }

  static List<int> _landmarks(ExerciseFormConfig c) => {
        for (final t in [c.leftPrimary, c.rightPrimary]) ...[t.a, t.vertex, t.c],
        if (c.kind == TrackingKind.hold) ...[PoseIndex.leftShoulder, PoseIndex.rightShoulder, PoseIndex.leftHip, PoseIndex.rightHip],
      }.toList()
        ..sort();

  static ExerciseFormConfig _reps(
    String id,
    String joint,
    (JointTriple, JointTriple) sides, {
    required double rest,
    required double attempt,
    required double peak,
    bool opening = false,
    AngleAggregate aggregate = AngleAggregate.mean,
    int minRepMs = 600,
    double maxAngleJump = 50,
    required String setup,
    required String down,
    required String up,
  }) =>
      ExerciseFormConfig(
        exerciseId: id,
        primaryJoint: joint,
        leftPrimary: sides.$1,
        rightPrimary: sides.$2,
        extendedAngle: rest,
        attemptAngle: attempt,
        flexedAngle: peak,
        opening: opening,
        aggregate: aggregate,
        minRepMs: minRepMs,
        maxAngleJump: maxAngleJump,
        scored: false,
        checks: const [],
        depthCue: opening ? 'Go through the full movement' : 'Go a little further each rep',
        depthPassedText: 'Full movement on every counted rep',
        depthFailedText: 'Movement stopped short',
        setupHint: setup,
        downCue: down,
        upCue: up,
      );

  static ExerciseFormConfig? _basic(String id, MovementPattern p) {
    switch (p) {
      case MovementPattern.squat:
        return _reps(id, 'Knee', _knee, rest: 160, attempt: 140, peak: 100, setup: _sideOn, down: 'Bend your knees', up: 'Stand back up');
      case MovementPattern.lunge:
        return _reps(id, 'Knee', _knee, rest: 160, attempt: 140, peak: 110, aggregate: AngleAggregate.furthest,
            setup: _sideOn, down: 'Lower into the lunge', up: 'Push back up');
      case MovementPattern.hinge:
        return _reps(id, 'Hip', _hip, rest: 160, attempt: 145, peak: 120, setup: _sideOn, down: 'Hinge at the hips', up: 'Stand tall');
      case MovementPattern.hipExtension:
        return _reps(id, 'Hip', _hip, rest: 145, attempt: 152, peak: 165, opening: true,
            setup: _floorSideOn, down: 'Lower with control', up: 'Lift your hips');
      case MovementPattern.pushup:
        return _reps(id, 'Elbow', _elbow, rest: 155, attempt: 135, peak: 95, setup: _floorSideOn, down: 'Lower with control', up: 'Press back up');
      case MovementPattern.benchPress:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 130, peak: 100, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Lower with control', up: 'Press up');
      case MovementPattern.dip:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 135, peak: 105, setup: _sideOn, down: 'Lower with control', up: 'Press back up');
      case MovementPattern.overheadPress:
        return _reps(id, 'Elbow', _elbow, rest: 110, attempt: 125, peak: 155, opening: true, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Lower to your shoulders', up: 'Press overhead');
      case MovementPattern.armRaise:
        return _reps(id, 'Shoulder', _shoulder, rest: 35, attempt: 50, peak: 75, opening: true, aggregate: AngleAggregate.furthest,
            setup: _front, down: 'Lower slowly', up: 'Raise your arms');
      case MovementPattern.row:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 130, peak: 100, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Pull', up: 'Straighten your arms');
      case MovementPattern.pulldown:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 130, peak: 95, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Pull down', up: 'Straighten your arms');
      case MovementPattern.curl:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 120, peak: 70, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Curl up', up: 'Lower slowly');
      case MovementPattern.tricepsExtension:
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 130, peak: 95, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Bend your elbows', up: 'Straighten your arms');
      case MovementPattern.tricepsPushdown:
        return _reps(id, 'Elbow', _elbow, rest: 110, attempt: 125, peak: 150, opening: true, aggregate: AngleAggregate.furthest,
            setup: _upperSideOn, down: 'Return with control', up: 'Straighten your arms');
      case MovementPattern.legExtension:
        return _reps(id, 'Knee', _knee, rest: 110, attempt: 125, peak: 155, opening: true, aggregate: AngleAggregate.furthest,
            setup: _sideOn, down: 'Lower with control', up: 'Straighten your leg');
      case MovementPattern.legCurl:
        return _reps(id, 'Knee', _knee, rest: 150, attempt: 130, peak: 100, aggregate: AngleAggregate.furthest,
            setup: _sideOn, down: 'Curl your heel in', up: 'Straighten your leg');
      case MovementPattern.sitUp:
        return _reps(id, 'Hip', _hip, rest: 115, attempt: 105, peak: 80, setup: _floorSideOn, down: 'Sit up', up: 'Lower back down');
      case MovementPattern.legRaise:
        return _reps(id, 'Hip', _hip, rest: 150, attempt: 135, peak: 110, setup: _floorSideOn, down: 'Lift your legs', up: 'Lower slowly');
      case MovementPattern.kneeLift:
        return _reps(id, 'Hip', _hip, rest: 160, attempt: 145, peak: 125, aggregate: AngleAggregate.furthest, minRepMs: 300,
            maxAngleJump: 70, setup: _sideOn, down: 'Lift your knee', up: 'Switch legs');
      case MovementPattern.jumpingJack:
        return _reps(id, 'Shoulder', _shoulder, rest: 40, attempt: 70, peak: 120, opening: true, minRepMs: 400,
            maxAngleJump: 80, setup: _front, down: 'Arms down', up: 'Arms up');
      case MovementPattern.plankHold:
        final knees = _kneeSupported.contains(id);
        return ExerciseFormConfig(
          exerciseId: id,
          primaryJoint: 'Body line',
          leftPrimary: knees ? _hip.$1 : _lineToAnkle.$1,
          rightPrimary: knees ? _hip.$2 : _lineToAnkle.$2,
          extendedAngle: 180,
          attemptAngle: 180,
          flexedAngle: 0,
          kind: TrackingKind.hold,
          scored: false,
          holdMinAngle: knees ? 150 : 155,
          holdMinLean: knees ? 45 : 50,
          holdCue: 'Get into position: shoulders, hips and ${knees ? 'knees' : 'ankles'} in one line',
          checks: const [],
          depthCue: '',
          depthPassedText: '',
          depthFailedText: '',
          setupHint: _floorSideOn,
          downCue: '',
          upCue: '',
        );
      case MovementPattern.wallSitHold:
        return ExerciseFormConfig(
          exerciseId: id,
          primaryJoint: 'Knee',
          leftPrimary: _knee.$1,
          rightPrimary: _knee.$2,
          extendedAngle: 180,
          attemptAngle: 180,
          flexedAngle: 0,
          kind: TrackingKind.hold,
          scored: false,
          holdMinAngle: 70,
          holdMaxAngle: 120,
          holdMaxLean: 35,
          holdCue: 'Slide down the wall until your knees are bent, back against the wall',
          checks: const [],
          depthCue: '',
          depthPassedText: '',
          depthFailedText: '',
          setupHint: _sideOn,
          downCue: '',
          upCue: '',
        );
      case MovementPattern.none:
        return null;
    }
  }

  /// Plain names for landmarks, for "can't see your …" guidance.
  static String landmarkName(int i) => switch (i) {
        PoseIndex.leftShoulder || PoseIndex.rightShoulder => 'shoulders',
        PoseIndex.leftElbow || PoseIndex.rightElbow => 'elbows',
        PoseIndex.leftWrist || PoseIndex.rightWrist => 'wrists',
        PoseIndex.leftHip || PoseIndex.rightHip => 'hips',
        PoseIndex.leftKnee || PoseIndex.rightKnee => 'knees',
        PoseIndex.leftAnkle || PoseIndex.rightAnkle => 'ankles',
        _ => 'body',
      };
}

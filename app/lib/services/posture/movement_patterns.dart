import '../../models/movement_pattern.dart';
import '../../models/workout_session.dart';
import 'exercise_form_rules.dart';
import 'form_checks.dart';
import 'pose_landmark.dart';

/// What the camera can do for one exercise (Module 5).
enum CameraSupportLevel {
  /// Real-time form checks, corrective feedback AND a posture score; thresholds tuned on real movements
  /// (the original four exercises, [FormEvaluation.validated]).
  validatedForm,

  /// Real, measurable form checks with live corrective feedback, awaiting real-device validation. No numeric score.
  experimentalForm,

  /// Repetitions counted or hold time measured, without form checks.
  basicTracking,

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

  /// e.g. "squat/experimental", for the audit and the saved session.
  String get configId => '${movementPattern.name}/${level.name}';

  bool get supportsCameraTracking => level != CameraSupportLevel.notSupported;
  bool get isHold => form?.kind == TrackingKind.hold;
  bool get supportsRepCounting => supportsCameraTracking && !isHold;
  bool get supportsHoldTiming => supportsCameraTracking && isHold;

  /// Real form checks run (validated or experimental).
  bool get supportsFormEvaluation => level == CameraSupportLevel.validatedForm || level == CameraSupportLevel.experimentalForm;

  /// Every tracked exercise gets a posture score (same formula as the validated four).
  bool get showsPostureScore => supportsCameraTracking;

  /// The score's thresholds were tuned on real movements; otherwise screens label it experimental / range-only.
  bool get scoreValidated => level == CameraSupportLevel.validatedForm;

  /// The same label for every tracked exercise; whether it is validated is shown separately by [unvalidatedNote].
  String get scoreLabel => 'Posture score';

  /// A short, low-key note shown with the score of exercises whose movement pattern has not been validated on a device
  /// (see docs/MODULE5_DEVICE_VALIDATION.md). Null for validated configurations.
  String? get validationNote => scoreValidated || !supportsCameraTracking ? null : unvalidatedNote;

  static const unvalidatedNote = "Form feedback for this movement hasn't been validated on real users yet.";
  bool get isExperimental => level == CameraSupportLevel.experimentalForm;

  /// The form checks this configuration runs, for the audit.
  List<String> get checkLabels => [for (final c in form?.checks ?? const <FormCheck>[]) c.label];
}

/// Movement pattern → tracker and form evaluator (the exercise configuration registry).
///
/// * The four tuned configurations in [ExerciseFormRules] keep their validated evaluation, unchanged.
/// * Every other trackable pattern gets a tracker and, where the movement allows it, measurable form checks
///   ([form_checks.dart]) — these are EXPERIMENTAL until validated on a device: live corrections, no score.
/// * Patterns (or variants) whose form cannot be inferred from the visible landmarks stay basic tracking.
///
/// CALIBRATION (2026-10-18): phase angles and check thresholds of the non-validated patterns were calibrated on REAL
/// people — MediaPipe landmarks of the free-exercise-db photos (start/end position), from the app's own model on the
/// phone and on the PC — using the calibration half only, and are checked on the held-out half by
/// test/real_pose_replay_test.dart (see docs/MODULE5_DEVICE_VALIDATION.md). They are still not clinical criteria, and
/// live-movement validation (fault sensitivity, speed) remains open.
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
    final tuned = ExerciseFormRules.forExercise(id);
    if (tuned != null) {
      return ExercisePostureConfig(
        exerciseId: id,
        movementPattern: pattern == MovementPattern.none ? MovementPattern.squat : pattern,
        level: CameraSupportLevel.validatedForm,
        requiredLandmarks: _landmarks(tuned),
        form: tuned,
      );
    }
    final form = pattern == MovementPattern.none ? null : _build(id, pattern);
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
      level: form.evaluation == FormEvaluation.experimental ? CameraSupportLevel.experimentalForm : CameraSupportLevel.basicTracking,
      requiredLandmarks: _landmarks(form),
      form: form,
    );
  }

  static List<int> _landmarks(ExerciseFormConfig c) => {
        for (final t in [c.leftPrimary, c.rightPrimary]) ...[t.a, t.vertex, t.c],
        if (c.kind == TrackingKind.hold) ...[PoseIndex.leftShoulder, PoseIndex.rightShoulder, PoseIndex.leftHip, PoseIndex.rightHip],
      }.toList()
        ..sort();

  static bool _has(String id, List<String> words) {
    final s = id.toLowerCase();
    return words.any(s.contains);
  }

  static ExerciseFormConfig _reps(
    String id,
    String joint,
    (JointTriple, JointTriple) sides, {
    required double rest,
    required double attempt,
    required double peak,
    bool opening = false,
    AngleAggregate aggregate = AngleAggregate.mean,
    bool ignoreLoweredArm = false,
    int minRepMs = 600,
    double maxAngleJump = 50,
    List<FormCheck> checks = const [],
    int? bodyLineLeft,
    int? bodyLineRight,
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
        ignoreLoweredArm: ignoreLoweredArm,
        minRepMs: minRepMs,
        maxAngleJump: maxAngleJump,
        bodyLineLeft: bodyLineLeft,
        bodyLineRight: bodyLineRight,
        evaluation: checks.isEmpty ? FormEvaluation.none : FormEvaluation.experimental,
        checks: checks,
        depthCue: opening ? 'Complete the full movement' : 'Go a little further — complete the movement range',
        depthPassedText: 'Full movement range on every counted rep',
        depthFailedText: 'Movement range was incomplete',
        setupHint: setup,
        downCue: down,
        upCue: up,
      );

  static ExerciseFormConfig _hold(
    String id,
    String joint,
    (JointTriple, JointTriple) sides, {
    double? minAngle,
    double? maxAngle,
    double? minLean,
    double? maxLean,
    int? bodyLineLeft,
    int? bodyLineRight,
    required String cue,
    required List<FormCheck> checks,
    required String setup,
  }) =>
      ExerciseFormConfig(
        exerciseId: id,
        primaryJoint: joint,
        leftPrimary: sides.$1,
        rightPrimary: sides.$2,
        extendedAngle: 180,
        attemptAngle: 180,
        flexedAngle: 0,
        kind: TrackingKind.hold,
        evaluation: checks.isEmpty ? FormEvaluation.none : FormEvaluation.experimental,
        holdMinAngle: minAngle,
        holdMaxAngle: maxAngle,
        holdMinLean: minLean,
        holdMaxLean: maxLean,
        holdCue: cue,
        bodyLineLeft: bodyLineLeft,
        bodyLineRight: bodyLineRight,
        checks: checks,
        depthCue: '',
        depthPassedText: '',
        depthFailedText: '',
        setupHint: setup,
        downCue: '',
        upCue: '',
      );

  static ExerciseFormConfig? _build(String id, MovementPattern p) {
    switch (p) {
      case MovementPattern.squat:
        return _reps(id, 'Knee', _knee, rest: 143, attempt: 130, peak: 105,
            checks: const [TorsoLeanCheck(70), KneeTrackingCheck(0.6)], setup: _sideOn, down: 'Bend your knees', up: 'Stand back up');
      case MovementPattern.lunge:
        return _reps(id, 'Knee', _knee, rest: 140, attempt: 125, peak: 100, aggregate: AngleAggregate.furthest,
            checks: const [TorsoLeanCheck(30, cue: 'Keep your torso upright', failedText: 'Torso leaned forward in the lunge')],
            setup: _sideOn, down: 'Lower into the lunge', up: 'Push back up');
      case MovementPattern.hinge:
        final straightLeg = _has(id, ['stiff', 'romanian', 'good_morning']);
        return _reps(id, 'Hip', _hip, rest: 140, attempt: 132, peak: 120,
            checks: straightLeg
                ? const [
                    JointRangeCheck(
                        id: 'knees_soft',
                        label: 'Leg position',
                        measure: Measure.knee,
                        min: 120,
                        lowCue: 'Keep your legs nearly straight — push your hips back',
                        passedText: 'Legs stayed nearly straight',
                        failedText: 'Knees bent too much, turning it into a squat'),
                  ]
                : const [
                    JointRangeCheck(
                        id: 'hinge_not_squat',
                        label: 'Hip hinge',
                        measure: Measure.knee,
                        min: 70,
                        atPeakOnly: true,
                        lowCue: 'Push your hips back — this is a hinge, not a squat',
                        passedText: 'Moved from the hips, not into a squat',
                        failedText: 'Knees bent deep, like a squat'),
                  ],
            setup: _sideOn, down: 'Hinge at the hips', up: 'Stand tall');
      case MovementPattern.hipExtension:
        final bridge = _has(id, ['bridge', 'thrust', 'hip_lift', 'butt_lift']);
        return _reps(id, 'Hip', _hip, rest: 135, attempt: 142, peak: 150, opening: true,
            checks: bridge
                ? const [
                    JointRangeCheck(
                        id: 'feet',
                        label: 'Foot position',
                        measure: Measure.knee,
                        min: 60,
                        max: 125,
                        atPeakOnly: true,
                        lowCue: 'Move your feet a little further from your hips',
                        highCue: 'Bring your heels a little closer to your hips',
                        passedText: 'Knees stayed near a right angle at the top',
                        failedText: 'Feet were too close or too far at the top'),
                  ]
                : const [
                    JointRangeCheck(
                        id: 'legs_straight',
                        label: 'Leg position',
                        measure: Measure.knee,
                        min: 150,
                        lowCue: 'Keep your legs straight',
                        passedText: 'Legs stayed straight',
                        failedText: 'Knees bent during the movement'),
                  ],
            setup: _floorSideOn, down: 'Lower with control', up: 'Lift your hips');
      case MovementPattern.pushup:
        return _reps(id, 'Elbow', _elbow, rest: 140, attempt: 125, peak: 100,
            checks: const [HipLineCheck()], bodyLineLeft: PoseIndex.leftAnkle, bodyLineRight: PoseIndex.rightAnkle,
            setup: _floorSideOn, down: 'Lower with control', up: 'Press back up');
      case MovementPattern.benchPress:
        // Lying on a bench, side-on: the torso line shows the hips lifting off the bench.
        return _reps(id, 'Elbow', _elbow, rest: 135, attempt: 126, peak: 115, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(10, cue: 'Keep your hips and back on the bench')],
            setup: _upperSideOn, down: 'Lower with control', up: 'Press up');
      case MovementPattern.dip:
        final triceps = _has(id, ['tricep']);
        return _reps(id, 'Elbow', _elbow, rest: 150, attempt: 135, peak: 105,
            checks: triceps
                ? const [TorsoLeanCheck(30, cue: 'Keep your chest up and torso upright', failedText: 'Torso leaned forward')]
                : const [TorsoLeanCheck(45, cue: "Keep your torso controlled — don't fold forward", failedText: 'Torso folded too far forward')],
            setup: _sideOn, down: 'Lower with control', up: 'Press back up');
      case MovementPattern.overheadPress:
        final oneArm = _has(id, ['one-arm', 'one_arm', 'single', 'alternating', 'seesaw', 'see-saw']);
        return _reps(id, 'Elbow', _elbow, rest: 120, attempt: 130, peak: 140, opening: true, aggregate: AngleAggregate.furthest,
            ignoreLoweredArm: true,
            checks: [
              const TorsoLeanCheck(20, cue: "Stand tall — don't lean back", failedText: 'Torso leaned during the press'),
              if (!oneArm) const ArmSymmetryCheck(40),
            ],
            setup: _upperSideOn, down: 'Lower to your shoulders', up: 'Press overhead');
      case MovementPattern.armRaise:
        return _reps(id, 'Shoulder', _shoulder, rest: 45, attempt: 55, peak: 72, opening: true, aggregate: AngleAggregate.furthest,
            checks: const [
              JointRangeCheck(
                  id: 'arms_straight',
                  label: 'Arm position',
                  measure: Measure.elbow,
                  min: 120,
                  lowCue: 'Keep your arms almost straight',
                  passedText: 'Arms stayed almost straight',
                  failedText: 'Elbows bent during the raise'),
              TorsoSwayCheck(14),
            ],
            setup: _front, down: 'Lower slowly', up: 'Raise your arms');
      case MovementPattern.uprightRow:
        return _reps(id, 'Shoulder', _shoulder, rest: 35, attempt: 48, peak: 68, opening: true,
            checks: const [TorsoSwayCheck(15)], setup: _front, down: 'Lower slowly', up: 'Lift your elbows');
      case MovementPattern.row:
        return _reps(id, 'Elbow', _elbow, rest: 138, attempt: 128, peak: 115, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(20, cue: 'Keep your torso still — pull with your arms')],
            setup: _upperSideOn, down: 'Pull', up: 'Straighten your arms');
      case MovementPattern.pulldown:
        return _reps(id, 'Elbow', _elbow, rest: 130, attempt: 115, peak: 95, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(20, cue: "Don't lean back to pull")],
            setup: _upperSideOn, down: 'Pull down', up: 'Straighten your arms');
      case MovementPattern.curl:
        // Braced curls hold the upper arm forward on purpose, so the upper-arm check only applies to free curls.
        final braced = _has(id, ['preacher', 'incline', 'lying', 'concentration', 'spider', 'overhead', 'high_cable', 'prone']);
        return _reps(id, 'Elbow', _elbow, rest: 140, attempt: 128, peak: 108, aggregate: AngleAggregate.furthest,
            checks: [if (!braced) const UpperArmStillCheck(55), const TorsoSwayCheck(20)],
            setup: _upperSideOn, down: 'Curl up', up: 'Lower slowly');
      case MovementPattern.tricepsExtension:
        return _reps(id, 'Elbow', _elbow, rest: 130, attempt: 120, peak: 105, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(12)], setup: _upperSideOn, down: 'Bend your elbows', up: 'Straighten your arms');
      case MovementPattern.tricepsPushdown:
        return _reps(id, 'Elbow', _elbow, rest: 115, attempt: 125, peak: 140, opening: true, aggregate: AngleAggregate.furthest,
            checks: const [UpperArmStillCheck(50), TorsoSwayCheck(12)],
            setup: _upperSideOn, down: 'Return with control', up: 'Straighten your arms');
      case MovementPattern.legExtension:
        return _reps(id, 'Knee', _knee, rest: 110, attempt: 122, peak: 145, opening: true, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(15, cue: 'Keep your back against the seat')],
            setup: _sideOn, down: 'Lower with control', up: 'Straighten your leg');
      case MovementPattern.legCurl:
        return _reps(id, 'Knee', _knee, rest: 125, attempt: 115, peak: 100, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(15, cue: 'Keep your hips down and still')],
            setup: _sideOn, down: 'Curl your heel in', up: 'Straighten your leg');
      case MovementPattern.sitUp:
        return _reps(id, 'Hip', _hip, rest: 115, attempt: 105, peak: 80,
            checks: const [
              JointRangeCheck(
                  id: 'knees_bent',
                  label: 'Leg position',
                  measure: Measure.knee,
                  min: 40,
                  max: 130,
                  lowCue: 'Keep your knees bent, feet flat',
                  highCue: 'Keep your knees bent, feet flat',
                  passedText: 'Knees stayed bent',
                  failedText: 'Legs straightened to help the sit-up'),
            ],
            setup: _floorSideOn, down: 'Sit up', up: 'Lower back down');
      case MovementPattern.legRaise:
        final straight = id == 'leg_raise' || _has(id, ['hanging_leg']);
        return _reps(id, 'Hip', _hip, rest: 150, attempt: 135, peak: 110,
            checks: straight
                ? const [
                    JointRangeCheck(
                        id: 'legs_straight',
                        label: 'Leg position',
                        measure: Measure.knee,
                        min: 145,
                        lowCue: 'Keep your legs straight',
                        passedText: 'Legs stayed straight',
                        failedText: 'Knees bent during the raise'),
                  ]
                : const [
                    JointRangeCheck(
                        id: 'knees_bent',
                        label: 'Leg position',
                        measure: Measure.knee,
                        min: 60,
                        max: 130,
                        lowCue: 'Keep your knees at about a right angle',
                        highCue: 'Keep your knees at about a right angle',
                        passedText: 'Knees stayed near a right angle',
                        failedText: 'Knee angle changed during the lift'),
                  ],
            setup: _floorSideOn, down: 'Lift your legs', up: 'Lower slowly');
      case MovementPattern.kneeLift:
        return _reps(id, 'Hip', _hip, rest: 160, attempt: 145, peak: 125, aggregate: AngleAggregate.furthest, minRepMs: 300,
            maxAngleJump: 70,
            checks: const [TorsoLeanCheck(20, cue: 'Stand tall as you lift your knees', failedText: 'Leaned while lifting the knees')],
            setup: _sideOn, down: 'Lift your knee', up: 'Switch legs');
      case MovementPattern.jumpingJack:
        return _reps(id, 'Shoulder', _shoulder, rest: 40, attempt: 70, peak: 120, opening: true, minRepMs: 400, maxAngleJump: 80,
            checks: const [
              JointRangeCheck(
                  id: 'feet_wide',
                  label: 'Arm and leg timing',
                  measure: Measure.ankleSpread,
                  min: 1.5,
                  atPeakOnly: true,
                  lowCue: 'Jump your feet wide as your arms go up',
                  passedText: 'Feet went wide with the arms',
                  failedText: 'Feet stayed narrow while the arms went up'),
            ],
            setup: _front, down: 'Arms down', up: 'Arms up');
      case MovementPattern.singleLegExtension:
        return _reps(id, 'Hip', _hip, rest: 115, attempt: 125, peak: 150, opening: true, aggregate: AngleAggregate.furthest,
            checks: const [TorsoSwayCheck(15, cue: 'Keep your back and hips still')],
            setup: _floorSideOn, down: 'Return with control', up: 'Extend your leg');
      case MovementPattern.plankKneeDrive:
        return _reps(id, 'Hip', _hip, rest: 150, attempt: 140, peak: 110, aggregate: AngleAggregate.furthest, minRepMs: 300,
            maxAngleJump: 70,
            checks: const [
              JointRangeCheck(
                  id: 'stay_low',
                  label: 'Plank position',
                  measure: Measure.torsoLean,
                  min: 50,
                  lowCue: 'Stay low in your plank position',
                  passedText: 'Stayed in the plank position',
                  failedText: 'Body rose out of the plank'),
            ],
            setup: _floorSideOn, down: 'Drive your knee in', up: 'Step back');
      case MovementPattern.kneeTuck:
        return _reps(id, 'Hip', _hip, rest: 80, attempt: 72, peak: 55,
            checks: const [TorsoSwayCheck(15, cue: 'Keep your upper body still — move from the hips')],
            setup: _floorSideOn, down: 'Pull your knees in', up: 'Extend back');
      case MovementPattern.plankHold:
        final knees = _kneeSupported.contains(id);
        return _hold(id, 'Body line', knees ? _hip : _lineToAnkle,
            minAngle: knees ? 150 : 155,
            minLean: knees ? 45 : 50,
            bodyLineLeft: knees ? PoseIndex.leftKnee : PoseIndex.leftAnkle,
            bodyLineRight: knees ? PoseIndex.rightKnee : PoseIndex.rightAnkle,
            cue: 'Get into position: shoulders, hips and ${knees ? 'knees' : 'ankles'} in one line',
            checks: const [HipLineCheck()],
            setup: _floorSideOn);
      case MovementPattern.wallSitHold:
        return _hold(id, 'Knee', _knee,
            minAngle: 70,
            maxAngle: 120,
            maxLean: 35,
            cue: 'Slide down the wall until your knees are bent, back against the wall',
            checks: const [
              JointRangeCheck(
                  id: 'knee_depth',
                  label: 'Knee angle',
                  measure: Measure.knee,
                  min: 70,
                  max: 120,
                  lowCue: 'Slide up a little — knees at about a right angle',
                  highCue: 'Slide a little lower down the wall',
                  passedText: 'Knees stayed near a right angle',
                  failedText: 'Knee angle drifted out of the hold position'),
              TorsoLeanCheck(35, cue: 'Keep your back against the wall', failedText: 'Back came away from the wall'),
            ],
            setup: _sideOn);
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

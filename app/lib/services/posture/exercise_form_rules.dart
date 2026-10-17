import 'pose_landmark.dart';
import 'pose_math.dart';

/// Three landmarks; the measured angle is at [vertex].
class JointTriple {
  final int a;
  final int vertex;
  final int c;
  const JointTriple(this.a, this.vertex, this.c);
}

/// The values the form rules work from, for one valid frame.
class PoseMeasurements {
  /// The angle that drives repetition counting (knee for squats, elbow for
  /// push-ups), averaged over the sides that are visible.
  final double primaryAngle;
  final double? leftPrimary;
  final double? rightPrimary;

  /// Lean of the hip→shoulder line from vertical, degrees.
  final double? torsoLean;

  /// Shoulder–hip–leg angle; 180° is a straight body line.
  final double? bodyLine;

  /// True when the user is square-on to the camera (wide shoulders in frame).
  final bool facingCamera;

  /// Knee separation ÷ ankle separation. Only measured when [facingCamera].
  final double? kneeToAnkleRatio;

  // --- secondary measurements (Module 5 form evaluation for all movement patterns) ---

  /// Mean of the visible sides, degrees: hip–knee–ankle, shoulder–elbow–wrist, shoulder–hip–knee.
  final double? kneeAngle;
  final double? elbowAngle;
  final double? hipAngle;

  /// Upper arm away from the torso (hip–shoulder–elbow), degrees; small = arm by the side.
  final double? upperArmAngle;

  /// Hip position against the shoulder→ankle (or knee) line, as a fraction of that line's length, measured only when the
  /// body is roughly horizontal (plank, push-up). Positive = hips above the line (piking), negative = below (sagging).
  final double? hipOffset;

  /// |left − right| of the rep-driving angle, only when both sides are visible and the person faces the camera.
  final double? armAsymmetry;

  /// Ankle separation ÷ hip width, only when facing the camera.
  final double? ankleSpread;

  /// Set by the engine: change of [torsoLean] from the person's own starting posture in this set.
  final double? torsoSway;

  /// Set by the engine: true while the movement is at its turning point (bottom of a squat, top of a press).
  final bool atPeak;

  const PoseMeasurements({
    required this.primaryAngle,
    this.leftPrimary,
    this.rightPrimary,
    this.torsoLean,
    this.bodyLine,
    this.facingCamera = false,
    this.kneeToAnkleRatio,
    this.kneeAngle,
    this.elbowAngle,
    this.hipAngle,
    this.upperArmAngle,
    this.hipOffset,
    this.armAsymmetry,
    this.ankleSpread,
    this.torsoSway,
    this.atPeak = false,
  });

  /// The same frame with the engine's context added.
  PoseMeasurements withContext({double? torsoSway, bool atPeak = false}) => PoseMeasurements(
        primaryAngle: primaryAngle,
        leftPrimary: leftPrimary,
        rightPrimary: rightPrimary,
        torsoLean: torsoLean,
        bodyLine: bodyLine,
        facingCamera: facingCamera,
        kneeToAnkleRatio: kneeToAnkleRatio,
        kneeAngle: kneeAngle,
        elbowAngle: elbowAngle,
        hipAngle: hipAngle,
        upperArmAngle: upperArmAngle,
        hipOffset: hipOffset,
        armAsymmetry: armAsymmetry,
        ankleSpread: ankleSpread,
        torsoSway: torsoSway,
        atPeak: atPeak,
      );
}

enum CheckOutcome { pass, fail, notApplicable }

/// A posture rule evaluated on every valid frame while the user is moving.
abstract class FormCheck {
  String get id;

  /// Short name of what is being checked, e.g. "Back alignment".
  String get label;

  /// Live correction shown (and spoken) when the rule is broken.
  String get cue;
  String get passedText;
  String get failedText;

  /// Landmarks to highlight on the skeleton when the rule is broken.
  List<int> get highlight;

  CheckOutcome evaluate(PoseMeasurements m);

  /// The correction for this particular failure (e.g. "raise" vs "lower" your hips). Usually [cue].
  String cueFor(PoseMeasurements m);
}

/// Torso must not fold forward past [maxLeanDegrees] from vertical.
class TorsoLeanCheck implements FormCheck {
  final double maxLeanDegrees;
  final String? _cue;
  final String? _failed;
  const TorsoLeanCheck(this.maxLeanDegrees, {String? cue, String? failedText})
      : _cue = cue,
        _failed = failedText;

  @override
  String get id => 'torso';
  @override
  String get label => 'Back alignment';
  @override
  String get cue => _cue ?? 'Keep your back straight — lift your chest';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Back alignment was maintained';
  @override
  String get failedText => _failed ?? 'Torso leaned too far forward';
  @override
  List<int> get highlight =>
      const [PoseIndex.leftShoulder, PoseIndex.rightShoulder, PoseIndex.leftHip, PoseIndex.rightHip];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final lean = m.torsoLean;
    if (lean == null) return CheckOutcome.notApplicable;
    return lean <= maxLeanDegrees ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Knees must not collapse inward. Needs a front view, so it reports
/// "not applicable" when the user is side-on.
class KneeTrackingCheck implements FormCheck {
  final double minKneeToAnkleRatio;
  const KneeTrackingCheck(this.minKneeToAnkleRatio);

  @override
  String get id => 'knees';
  @override
  String get label => 'Knee tracking';
  @override
  String get cue => 'Push your knees out over your toes';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Knees tracked properly over toes';
  @override
  String get failedText => 'Knees collapsed inward';
  @override
  List<int> get highlight => const [PoseIndex.leftKnee, PoseIndex.rightKnee];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final ratio = m.kneeToAnkleRatio;
    if (!m.facingCamera || ratio == null) return CheckOutcome.notApplicable;
    return ratio >= minKneeToAnkleRatio ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Shoulders, hips and legs must stay in one line (no sagging or piking).
class BodyLineCheck implements FormCheck {
  final double minAngle;
  const BodyLineCheck(this.minAngle);

  @override
  String get id => 'body_line';
  @override
  String get label => 'Body line';
  @override
  String get cue => 'Keep your body in a straight line — brace your core';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Body stayed in a straight line';
  @override
  String get failedText => 'Hips sagged or lifted out of line';
  @override
  List<int> get highlight => const [PoseIndex.leftHip, PoseIndex.rightHip];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final line = m.bodyLine;
    if (line == null) return CheckOutcome.notApplicable;
    return line >= minAngle ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Repetitions (a movement cycle) or a static hold (time in position).
enum TrackingKind { reps, hold }

/// How much the form checks of a configuration can be trusted.
enum FormEvaluation {
  /// Checks and posture score; thresholds tuned on real movements (the original four exercises).
  validated,

  /// Real, measurable checks with live corrections, awaiting real-device validation: no numeric score is shown.
  experimental,

  /// No form checks: repetitions or hold time only.
  none,
}

/// How the two sides are combined into the rep-driving angle.
enum AngleAggregate {
  /// Both limbs move together (squat, push-up).
  mean,

  /// The limb that moves furthest drives the count: the more bent one for a bending movement, the more open one for an
  /// opening movement (lunge front knee, alternating knee lifts, one-arm curls and raises).
  furthest,
}

/// Form rules for one exercise. Every threshold is per-exercise and can be
/// changed here without touching the engine.
///
/// ASSUMPTIONS: the angles below are starting values chosen by the project
/// team from common coaching cues (e.g. "thighs about parallel" ≈ 100° at the
/// knee). They have not been validated on test subjects or reviewed by a
/// physiotherapist, and they are not medical criteria.
class ExerciseFormConfig {
  final String exerciseId;

  /// Name of the rep-driving joint, for the on-screen angle badges.
  final String primaryJoint;
  final JointTriple leftPrimary;
  final JointTriple rightPrimary;

  /// At or above this angle the joint counts as extended (start/end position).
  /// For an [opening] movement: at or BELOW this angle the joint is at rest.
  final double extendedAngle;

  /// Below this angle a repetition attempt has started. The gap to
  /// [extendedAngle] is hysteresis against jitter. For an [opening] movement: above it.
  final double attemptAngle;

  /// At or below this angle the movement has reached valid depth. For an [opening] movement: at or above it.
  final double flexedAngle;

  /// True when a repetition starts bent and opens up (overhead press, glute bridge, arm raise, leg extension); the three
  /// angles above then mean rest, attempt and peak. False (default) for movements that start extended and bend.
  final bool opening;

  final AngleAggregate aggregate;
  final TrackingKind kind;

  /// Posture checks and the posture score are reported only for configurations that were tried on real movements
  /// (the four original exercises, [FormEvaluation.validated]). Experimental configurations run real checks and give live
  /// corrections but show no score; [FormEvaluation.none] counts movement cycles or hold time only.
  final FormEvaluation evaluation;
  bool get scored => evaluation == FormEvaluation.validated;

  /// Hold: the person is "in position" while the rep-driving angle is within [holdMinAngle]–[holdMaxAngle] and the torso
  /// lean from vertical within [holdMinLean]–[holdMaxLean] (null bounds are not checked).
  final double? holdMinAngle;
  final double? holdMaxAngle;
  final double? holdMinLean;
  final double? holdMaxLean;
  final String holdCue;

  /// Landmarks below this visibility are treated as missing.
  final double minVisibility;

  /// Faster "repetitions" than this are treated as landmark noise.
  final int minRepMs;

  /// Repetitions faster than this count but fail the tempo criterion.
  final int controlledRepMs;

  /// A larger change between consecutive frames is rejected as an outlier.
  final double maxAngleJump;

  /// Lower end of the body line (ankles, or knees for knee push-ups); null to
  /// skip that measurement.
  final int? bodyLineLeft;
  final int? bodyLineRight;

  final List<FormCheck> checks;
  final String depthCue;
  final String depthPassedText;
  final String depthFailedText;
  final String setupHint;
  final String downCue;
  final String upCue;

  const ExerciseFormConfig({
    required this.exerciseId,
    required this.primaryJoint,
    required this.leftPrimary,
    required this.rightPrimary,
    required this.extendedAngle,
    required this.attemptAngle,
    required this.flexedAngle,
    this.minVisibility = 0.5,
    this.minRepMs = 600,
    this.controlledRepMs = 1200,
    this.maxAngleJump = 50,
    this.bodyLineLeft,
    this.bodyLineRight,
    this.opening = false,
    this.aggregate = AngleAggregate.mean,
    this.kind = TrackingKind.reps,
    this.evaluation = FormEvaluation.validated,
    this.holdMinAngle,
    this.holdMaxAngle,
    this.holdMinLean,
    this.holdMaxLean,
    this.holdCue = '',
    required this.checks,
    required this.depthCue,
    required this.depthPassedText,
    required this.depthFailedText,
    required this.setupHint,
    required this.downCue,
    required this.upCue,
  });
}

/// The exercises camera detection supports, and their rules.
class ExerciseFormRules {
  ExerciseFormRules._();

  static const _knee = (
    left: JointTriple(PoseIndex.leftHip, PoseIndex.leftKnee, PoseIndex.leftAnkle),
    right: JointTriple(PoseIndex.rightHip, PoseIndex.rightKnee, PoseIndex.rightAnkle),
  );
  static const _elbow = (
    left: JointTriple(PoseIndex.leftShoulder, PoseIndex.leftElbow, PoseIndex.leftWrist),
    right: JointTriple(PoseIndex.rightShoulder, PoseIndex.rightElbow, PoseIndex.rightWrist),
  );

  static final Map<String, ExerciseFormConfig> _configs = {
    for (final c in [
      ExerciseFormConfig(
        exerciseId: 'squat',
        primaryJoint: 'Knee',
        leftPrimary: _knee.left,
        rightPrimary: _knee.right,
        extendedAngle: 160,
        attemptAngle: 140,
        flexedAngle: 100,
        checks: const [TorsoLeanCheck(60), KneeTrackingCheck(0.65)],
        depthCue: 'Lower your hips more',
        depthPassedText: 'Good depth on every rep',
        depthFailedText: 'Hip depth could be lower',
        setupHint: 'Stand side-on, 2–3 m away, with your whole body in the frame',
        downCue: 'Sit back and down',
        upCue: 'Drive up through your heels',
      ),
      // Sit-to-stand only goes down to chair height, and rising from a chair
      // needs more forward lean than a free squat.
      ExerciseFormConfig(
        exerciseId: 'chair_squat',
        primaryJoint: 'Knee',
        leftPrimary: _knee.left,
        rightPrimary: _knee.right,
        extendedAngle: 160,
        attemptAngle: 140,
        flexedAngle: 110,
        checks: const [TorsoLeanCheck(70), KneeTrackingCheck(0.65)],
        depthCue: 'Lower all the way to the chair',
        depthPassedText: 'Reached the chair on every rep',
        depthFailedText: 'Did not lower fully to the chair',
        setupHint: 'Place the chair side-on to the camera with your whole body in the frame',
        downCue: 'Lower slowly to the chair',
        upCue: 'Stand up tall',
      ),
      ExerciseFormConfig(
        exerciseId: 'pushup',
        primaryJoint: 'Elbow',
        leftPrimary: _elbow.left,
        rightPrimary: _elbow.right,
        extendedAngle: 155,
        attemptAngle: 135,
        flexedAngle: 95,
        bodyLineLeft: PoseIndex.leftAnkle,
        bodyLineRight: PoseIndex.rightAnkle,
        checks: const [BodyLineCheck(155)],
        depthCue: 'Lower your chest closer to the floor',
        depthPassedText: 'Full range on every rep',
        depthFailedText: 'Chest did not get low enough',
        setupHint: 'Place the phone at floor level, side-on, with your whole body in the frame',
        downCue: 'Lower with control',
        upCue: 'Press back up',
      ),
      ExerciseFormConfig(
        exerciseId: 'knee_pushup',
        primaryJoint: 'Elbow',
        leftPrimary: _elbow.left,
        rightPrimary: _elbow.right,
        extendedAngle: 155,
        attemptAngle: 135,
        flexedAngle: 95,
        bodyLineLeft: PoseIndex.leftKnee,
        bodyLineRight: PoseIndex.rightKnee,
        checks: const [BodyLineCheck(150)],
        depthCue: 'Lower your chest closer to the floor',
        depthPassedText: 'Full range on every rep',
        depthFailedText: 'Chest did not get low enough',
        setupHint: 'Place the phone at floor level, side-on, with your whole body in the frame',
        downCue: 'Lower with control',
        upCue: 'Press back up',
      ),
    ])
      c.exerciseId: c,
  };

  static ExerciseFormConfig? forExercise(String exerciseId) => _configs[exerciseId];
  static bool supports(String exerciseId) => _configs.containsKey(exerciseId);
  static List<String> get supportedIds => _configs.keys.toList();
}

/// Turns raw landmarks into [PoseMeasurements], rejecting frames where the
/// joints the exercise needs are missing, invalid or not confidently visible.
class PoseAnalyzer {
  PoseAnalyzer._();

  /// Shoulder width ÷ torso length above which the user is facing the camera.
  static const _facingRatio = 0.45;

  static PoseMeasurements? measure(PoseFrame frame, ExerciseFormConfig config) {
    if (!frame.hasPose) return null;
    final image = frame.landmarks;

    bool visible(int i) => image[i].isFinite && image[i].visibility >= config.minVisibility;
    Vec3 img(int i) => Vec3(image[i].x * frame.aspectRatio, image[i].y);
    // Angles use the 3-D world landmarks when the model supplies them.
    Vec3 pt(int i) {
      if (!frame.hasWorld) return img(i);
      final w = frame.worldLandmarks[i];
      return Vec3(w.x, w.y, w.z);
    }

    double? angle(JointTriple t) =>
        visible(t.a) && visible(t.vertex) && visible(t.c) ? PoseMath.jointAngle(pt(t.a), pt(t.vertex), pt(t.c)) : null;

    final left = angle(config.leftPrimary);
    final right = angle(config.rightPrimary);
    final primary = config.aggregate == AngleAggregate.furthest
        ? (config.opening ? _max(left, right) : _min(left, right))
        : _mean(left, right);
    if (primary == null) return null;

    const ls = PoseIndex.leftShoulder, rs = PoseIndex.rightShoulder;
    const lh = PoseIndex.leftHip, rh = PoseIndex.rightHip;
    final leftTorso = visible(ls) && visible(lh);
    final rightTorso = visible(rs) && visible(rh);

    final torsoLean = _mean(
      leftTorso ? PoseMath.leanFromVertical(pt(lh), pt(ls)) : null,
      rightTorso ? PoseMath.leanFromVertical(pt(rh), pt(rs)) : null,
    );

    double? bodyLine;
    final endL = config.bodyLineLeft, endR = config.bodyLineRight;
    if (endL != null && endR != null) {
      bodyLine = _mean(
        leftTorso && visible(endL) ? PoseMath.jointAngle(pt(ls), pt(lh), pt(endL)) : null,
        rightTorso && visible(endR) ? PoseMath.jointAngle(pt(rs), pt(rh), pt(endR)) : null,
      );
    }

    double? meanAngle(JointTriple l, JointTriple r) => _mean(angle(l), angle(r));
    const le = PoseIndex.leftElbow, re = PoseIndex.rightElbow, lw = PoseIndex.leftWrist, rw = PoseIndex.rightWrist;
    const lk = PoseIndex.leftKnee, rk = PoseIndex.rightKnee, la = PoseIndex.leftAnkle, ra = PoseIndex.rightAnkle;
    final kneeAngle = meanAngle(const JointTriple(lh, lk, la), const JointTriple(rh, rk, ra));
    final elbowAngle = meanAngle(const JointTriple(ls, le, lw), const JointTriple(rs, re, rw));
    final hipAngle = meanAngle(const JointTriple(ls, lh, lk), const JointTriple(rs, rh, rk));
    final upperArm = meanAngle(const JointTriple(lh, ls, le), const JointTriple(rh, rs, re));

    // Hips against the shoulder→ankle (or knee) line, image coordinates, only when the body is roughly horizontal.
    double? hipOffset;
    final lineL = config.bodyLineLeft ?? la, lineR = config.bodyLineRight ?? ra;
    double? offsetFor(int s, int h, int e) {
      if (!visible(s) || !visible(h) || !visible(e)) return null;
      final sp = img(s), hp = img(h), ep = img(e);
      final dx = ep.x - sp.x, dy = ep.y - sp.y;
      final length = (ep - sp).length;
      if (length < 1e-6 || dx.abs() < dy.abs()) return null; // more vertical than horizontal: not a plank-like position
      final t = (hp.x - sp.x) / dx;
      if (t < 0.05 || t > 0.95) return null;
      final lineY = sp.y + t * dy;
      return (lineY - hp.y) / length; // image y grows downwards
    }

    hipOffset = _mean(offsetFor(ls, lh, lineL), offsetFor(rs, rh, lineR));

    var facing = false;
    double? kneeRatio;
    double? armAsymmetry;
    double? ankleSpread;
    if (leftTorso && rightTorso) {
      final shoulderWidth = (img(ls) - img(rs)).length;
      final torso = (Vec3.midpoint(img(ls), img(rs)) - Vec3.midpoint(img(lh), img(rh))).length;
      facing = torso > 1e-6 && shoulderWidth / torso >= _facingRatio;
      if (facing && visible(lk) && visible(rk) && visible(la) && visible(ra)) {
        final ankles = (img(la).x - img(ra).x).abs();
        // Feet together give a meaningless ratio, so require a real stance.
        if (ankles > shoulderWidth * 0.3) kneeRatio = (img(lk).x - img(rk).x).abs() / ankles;
        final hipWidth = (img(lh).x - img(rh).x).abs();
        if (hipWidth > 1e-6) ankleSpread = ankles / hipWidth;
      }
      if (facing && left != null && right != null) armAsymmetry = (left - right).abs();
    }

    return PoseMeasurements(
      primaryAngle: primary,
      leftPrimary: left,
      rightPrimary: right,
      torsoLean: torsoLean,
      bodyLine: bodyLine,
      facingCamera: facing,
      kneeToAnkleRatio: kneeRatio,
      kneeAngle: kneeAngle,
      elbowAngle: elbowAngle,
      hipAngle: hipAngle,
      upperArmAngle: upperArm,
      hipOffset: hipOffset,
      armAsymmetry: armAsymmetry,
      ankleSpread: ankleSpread,
    );
  }

  static double? _max(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  static double? _min(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  /// Landmarks the configuration needs that are missing or below the visibility threshold in [frame].
  static List<int> missingLandmarks(PoseFrame frame, ExerciseFormConfig config) {
    if (!frame.hasPose) return const [];
    bool visible(int i) => frame.landmarks[i].isFinite && frame.landmarks[i].visibility >= config.minVisibility;
    bool sideOk(JointTriple t) => visible(t.a) && visible(t.vertex) && visible(t.c);
    if (sideOk(config.leftPrimary) || sideOk(config.rightPrimary)) return const [];
    return {
      for (final t in [config.leftPrimary, config.rightPrimary])
        for (final i in [t.a, t.vertex, t.c])
          if (!visible(i)) i,
    }.toList()
      ..sort();
  }

  static double? _mean(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return (a + b) / 2;
  }
}

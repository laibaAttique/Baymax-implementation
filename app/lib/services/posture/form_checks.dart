import 'exercise_form_rules.dart';
import 'pose_landmark.dart';

/// Reusable posture checks for the movement patterns (Module 5). Each one measures something MediaPipe's landmarks
/// actually show and reports "not applicable" when the measurement is not available from the current camera angle, so
/// no correction is ever given without the condition having been measured.
///
/// ASSUMPTIONS: thresholds are team-chosen starting values from common coaching cues, not validated on test subjects and
/// not clinical criteria. Configurations using these checks are [FormEvaluation.experimental] until validated on a device.

/// Torso must not swing away from the person's own starting posture (curls, raises, rows, presses).
class TorsoSwayCheck implements FormCheck {
  final double maxDegrees;
  @override
  final String cue;
  const TorsoSwayCheck(this.maxDegrees, {this.cue = 'Keep your body still — don\'t swing'});

  @override
  String get id => 'sway';
  @override
  String get label => 'Torso stability';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Torso stayed steady';
  @override
  String get failedText => 'Torso swung to help the movement';
  @override
  List<int> get highlight => const [PoseIndex.leftShoulder, PoseIndex.rightShoulder, PoseIndex.leftHip, PoseIndex.rightHip];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final sway = m.torsoSway;
    if (sway == null) return CheckOutcome.notApplicable;
    return sway <= maxDegrees ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Upper arm stays by the side (curls, triceps pushdowns, kickbacks).
class UpperArmStillCheck implements FormCheck {
  final double maxDegrees;
  const UpperArmStillCheck(this.maxDegrees);

  @override
  String get id => 'upper_arm';
  @override
  String get label => 'Upper-arm position';
  @override
  String get cue => 'Keep your upper arm still, close to your body';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Upper arm stayed in place';
  @override
  String get failedText => 'Upper arm moved forward to help';
  @override
  List<int> get highlight => const [PoseIndex.leftElbow, PoseIndex.rightElbow];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final a = m.upperArmAngle;
    if (a == null) return CheckOutcome.notApplicable;
    return a <= maxDegrees ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Hips in line with shoulders and ankles/knees: catches both sagging and piking, and says which.
class HipLineCheck implements FormCheck {
  /// Largest allowed drop below / rise above the line, as a fraction of the line's length.
  final double maxSag;
  final double maxPike;
  const HipLineCheck({this.maxSag = 0.06, this.maxPike = 0.10});

  @override
  String get id => 'hips';
  @override
  String get label => 'Hip position';
  @override
  String get cue => 'Keep your hips in line with your shoulders';
  @override
  String cueFor(PoseMeasurements m) {
    final o = m.hipOffset;
    if (o != null && o < -maxSag) return 'Raise your hips slightly — don\'t let them sag';
    if (o != null && o > maxPike) return 'Lower your hips into a straight line';
    return cue;
  }

  @override
  String get passedText => 'Hips stayed in line';
  @override
  String get failedText => 'Hips sagged or rose out of line';
  @override
  List<int> get highlight => const [PoseIndex.leftHip, PoseIndex.rightHip];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final o = m.hipOffset;
    if (o == null) return CheckOutcome.notApplicable;
    return (o >= -maxSag && o <= maxPike) ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Both arms move together (presses, raises) — only when the person faces the camera and both arms are visible.
class ArmSymmetryCheck implements FormCheck {
  final double maxDifference;
  const ArmSymmetryCheck(this.maxDifference);

  @override
  String get id => 'symmetry';
  @override
  String get label => 'Arm symmetry';
  @override
  String get cue => 'Move both arms evenly';
  @override
  String cueFor(PoseMeasurements m) => cue;
  @override
  String get passedText => 'Both arms moved evenly';
  @override
  String get failedText => 'One arm lagged behind the other';
  @override
  List<int> get highlight => const [PoseIndex.leftElbow, PoseIndex.rightElbow];

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    final d = m.armAsymmetry;
    if (d == null) return CheckOutcome.notApplicable;
    return d <= maxDifference ? CheckOutcome.pass : CheckOutcome.fail;
  }
}

/// Which secondary measurement a [JointRangeCheck] reads.
enum Measure { knee, elbow, hip, torsoLean, ankleSpread }

/// A secondary measurement must stay within a range, optionally only at the movement's turning point.
/// E.g. straight arms in a lateral raise, straight legs in a leg raise, knees bent ~90° at the top of a bridge.
class JointRangeCheck implements FormCheck {
  @override
  final String id;
  @override
  final String label;
  final Measure measure;
  final double? min;
  final double? max;

  /// Cue when below [min] / above [max].
  final String lowCue;
  final String highCue;
  @override
  final String passedText;
  @override
  final String failedText;
  final bool atPeakOnly;

  const JointRangeCheck({
    required this.id,
    required this.label,
    required this.measure,
    this.min,
    this.max,
    this.lowCue = '',
    this.highCue = '',
    required this.passedText,
    required this.failedText,
    this.atPeakOnly = false,
  });

  double? _value(PoseMeasurements m) => switch (measure) {
        Measure.knee => m.kneeAngle,
        Measure.elbow => m.elbowAngle,
        Measure.hip => m.hipAngle,
        Measure.torsoLean => m.torsoLean,
        Measure.ankleSpread => m.ankleSpread,
      };

  @override
  String get cue => lowCue.isNotEmpty ? lowCue : highCue;

  @override
  String cueFor(PoseMeasurements m) {
    final v = _value(m);
    if (v != null && min != null && v < min!) return lowCue;
    if (v != null && max != null && v > max!) return highCue;
    return cue;
  }

  @override
  List<int> get highlight => switch (measure) {
        Measure.knee => const [PoseIndex.leftKnee, PoseIndex.rightKnee],
        Measure.elbow => const [PoseIndex.leftElbow, PoseIndex.rightElbow],
        Measure.hip || Measure.torsoLean => const [PoseIndex.leftHip, PoseIndex.rightHip],
        Measure.ankleSpread => const [PoseIndex.leftAnkle, PoseIndex.rightAnkle],
      };

  @override
  CheckOutcome evaluate(PoseMeasurements m) {
    if (atPeakOnly && !m.atPeak) return CheckOutcome.notApplicable;
    final v = _value(m);
    if (v == null) return CheckOutcome.notApplicable;
    if (min != null && v < min!) return CheckOutcome.fail;
    if (max != null && v > max!) return CheckOutcome.fail;
    return CheckOutcome.pass;
  }
}

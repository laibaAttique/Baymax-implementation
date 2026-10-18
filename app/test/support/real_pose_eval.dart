import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/hold_tracker.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/posture_engine.dart';

/// Evaluates one tracker configuration on a pair of real photos (start and end position of the movement), with the
/// production analyzer and engine. Shared by the replay test; mirrors the on-device test.
class PairResult {
  final bool measurable;
  final double? a0;
  final double? a1;

  /// Reps: one photo at rest and the other past the turning point.
  final bool span;

  /// Reps: the engine counted exactly one rep for rest → end → rest.
  final bool repCounted;

  /// Holds: the photo(s) are in position.
  final bool inPosition;
  final bool isHold;

  /// Checks that fired on the demonstrated (correct) form.
  final List<String> falseAlarms;

  /// Checks that could not be assessed on either photo (camera angle).
  final List<String> notApplicable;

  /// Measurements for calibration.
  final Map<String, Object?> measures;

  const PairResult({
    required this.measurable,
    this.a0,
    this.a1,
    this.span = false,
    this.repCounted = false,
    this.inPosition = false,
    this.isHold = false,
    this.falseAlarms = const [],
    this.notApplicable = const [],
    this.measures = const {},
  });
}

List<PoseLandmark> _unpack(List<dynamic> l) => [
      for (final p in l)
        PoseLandmark((p[0] as num).toDouble(), (p[1] as num).toDouble(), (p[2] as num).toDouble(), (p[3] as num).toDouble()),
    ];

PoseFrame frameFromJson(Map<String, dynamic> f, int ts) => PoseFrame(
      landmarks: _unpack(f['lm'] as List),
      worldLandmarks: _unpack(f['world'] as List),
      timestampMs: ts,
      aspectRatio: (f['aspect'] as num).toDouble(),
    );

Map<String, Object?> _m(PoseMeasurements m) => {
      'primary': m.primaryAngle,
      'lean': m.torsoLean,
      'knee': m.kneeAngle,
      'elbow': m.elbowAngle,
      'hip': m.hipAngle,
      'upperArm': m.upperArmAngle,
      'hipOffset': m.hipOffset,
      'kneeRatio': m.kneeToAnkleRatio,
      'ankleSpread': m.ankleSpread,
      'asym': m.armAsymmetry,
      'bodyLine': m.bodyLine,
      'facing': m.facingCamera,
    };

PairResult evaluatePair(ExerciseFormConfig cfg, PoseFrame f0, PoseFrame f1) {
  final m0 = PoseAnalyzer.measure(f0, cfg);
  final m1 = PoseAnalyzer.measure(f1, cfg);
  if (m0 == null || m1 == null) return const PairResult(measurable: false);
  final a0 = m0.primaryAngle, a1 = m1.primaryAngle;
  if (cfg.kind == TrackingKind.hold) {
    final tracker = HoldTracker(cfg);
    final ok0 = tracker.matches(m0), ok1 = tracker.matches(m1);
    return PairResult(
      measurable: true,
      a0: a0,
      a1: a1,
      isHold: true,
      inPosition: ok0 || ok1,
      falseAlarms: {
        for (final (m, ok) in [(m0, ok0), (m1, ok1)])
          if (ok)
            for (final c in cfg.checks)
              if (c.evaluate(m) == CheckOutcome.fail) c.id,
      }.toList(),
      measures: {'p0': _m(m0), 'p1': _m(m1)},
    );
  }
  bool atRest(double a) => cfg.opening ? a <= cfg.extendedAngle : a >= cfg.extendedAngle;
  bool pastTurn(double a) => cfg.opening ? a >= cfg.flexedAngle : a <= cfg.flexedAngle;
  // The rest photo is the one nearer the rest side.
  final restIsFirst = cfg.opening ? a0 <= a1 : a0 >= a1;
  final restF = restIsFirst ? f0 : f1, turnF = restIsFirst ? f1 : f0;
  final mRest = restIsFirst ? m0 : m1, mTurn = restIsFirst ? m1 : m0;
  final span = atRest(mRest.primaryAngle) && pastTurn(mTurn.primaryAngle);

  final engine = PostureEngine(cfg);
  var ts = 0;
  for (final f in [...List.filled(10, restF), ...List.filled(10, turnF), ...List.filled(10, restF)]) {
    ts += 100;
    engine.process(PoseFrame(landmarks: f.landmarks, worldLandmarks: f.worldLandmarks, timestampMs: ts, aspectRatio: f.aspectRatio));
  }

  final leanR = mRest.torsoLean, leanT = mTurn.torsoLean;
  final sway = leanR != null && leanT != null ? (leanT - leanR).abs() : null;
  final turnCtx = mTurn.withContext(torsoSway: sway, atPeak: true);
  final restCtx = mRest.withContext(torsoSway: 0);
  return PairResult(
    measurable: true,
    a0: a0,
    a1: a1,
    span: span,
    repCounted: engine.reps == 1,
    falseAlarms: {
      for (final c in cfg.checks)
        if (c.evaluate(turnCtx) == CheckOutcome.fail || c.evaluate(restCtx) == CheckOutcome.fail) c.id,
    }.toList(),
    notApplicable: [
      for (final c in cfg.checks)
        if (c.evaluate(turnCtx) == CheckOutcome.notApplicable && c.evaluate(restCtx) == CheckOutcome.notApplicable) c.id,
    ],
    measures: {'rest': _m(mRest), 'turn': _m(mTurn), 'sway': sway},
  );
}

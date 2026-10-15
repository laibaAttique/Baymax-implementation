import '../../models/workout_session.dart';
import 'exercise_form_rules.dart';
import 'pose_landmark.dart';
import 'rep_counter.dart';

/// The message shown in the feedback banner for the current frame.
class LiveFeedback {
  final String message;

  /// True for a form correction (as opposed to guidance or praise).
  final bool isWarning;

  /// Landmarks to highlight on the skeleton.
  final List<int> highlight;
  const LiveFeedback(this.message, {this.isWarning = false, this.highlight = const []});
}

/// The engine's result for one camera frame.
class PostureAnalysis {
  final bool landmarksDetected;
  final bool anglesCalculated;
  final PoseMeasurements? measurements;
  final RepPhase phase;
  final int reps;
  final int partialReps;
  final RepEvent? repEvent;
  final LiveFeedback feedback;
  final int? postureScore;

  const PostureAnalysis({
    required this.landmarksDetected,
    required this.anglesCalculated,
    required this.measurements,
    required this.phase,
    required this.reps,
    required this.partialReps,
    required this.repEvent,
    required this.feedback,
    required this.postureScore,
  });
}

/// Form results for a whole session, produced when it stops.
class SessionFormReport {
  final int reps;
  final int partialReps;
  final int? postureScore;
  final int? accuracy;
  final List<FormFeedbackItem> feedback;
  final int validFrames;
  final int totalFrames;

  const SessionFormReport({
    required this.reps,
    required this.partialReps,
    required this.postureScore,
    required this.accuracy,
    required this.feedback,
    required this.validFrames,
    required this.totalFrames,
  });
}

class _Tally {
  int evaluated = 0;
  int passed = 0;
}

/// Evaluates exercise form frame by frame (Module 5, FR-4 … FR-9).
///
/// Pure Dart with no camera or UI dependency: feed it [PoseFrame]s, read back
/// [PostureAnalysis]. All timing comes from the frame timestamps.
///
/// SCORING (both values are fitness feedback, not a medical assessment):
///
///  * Posture score = 100 × acceptable reps ÷ attempted reps, where
///    attempted = counted reps + partial attempts (report FR18.1). A rep is
///    acceptable when it reached valid depth and every posture check that
///    could be assessed passed on at least [repPassRate] of that rep's valid
///    frames. Null until at least one attempt has finished.
///  * Accuracy = 100 × passed check-frames ÷ assessed check-frames across the
///    session. Null below [minFramesForAccuracy] assessed frames.
///
/// Frames with missing or low-visibility landmarks never enter either value,
/// and checks are only assessed while the user is moving (not standing idle).
class PostureEngine {
  final ExerciseFormConfig config;
  final RepCounter _counter;

  PostureEngine(this.config) : _counter = RepCounter(config);

  static const repPassRate = 0.8;
  static const minFramesForAccuracy = 15;
  static const _minFramesPerRepCheck = 3;
  static const _framesToWarn = 3;

  final Map<String, _Tally> _repWindow = {};
  final Map<String, _Tally> _sessionChecks = {};
  final Map<String, int> _failStreak = {};
  final _Tally _tempo = _Tally();
  final _Tally _frames = _Tally();
  int _acceptableReps = 0;
  int _validFrames = 0;
  int _totalFrames = 0;

  LiveFeedback? _transient;
  int _transientUntilMs = 0;

  int get reps => _counter.count;
  int get partialReps => _counter.partialAttempts;

  int? get postureScore {
    final attempts = reps + partialReps;
    return attempts == 0 ? null : (100 * _acceptableReps / attempts).round().clamp(0, 100);
  }

  int? get accuracy => _frames.evaluated < minFramesForAccuracy
      ? null
      : (100 * _frames.passed / _frames.evaluated).round().clamp(0, 100);

  PostureAnalysis process(PoseFrame frame) {
    _totalFrames++;
    if (!frame.hasPose) {
      _failStreak.clear();
      return _result(false, null, null, const LiveFeedback('Step into the frame so the camera can see you'));
    }
    final m = PoseAnalyzer.measure(frame, config);
    if (m == null) {
      _failStreak.clear();
      return _result(true, null, null, LiveFeedback(config.setupHint));
    }
    _validFrames++;

    final event = _counter.update(m.primaryAngle, frame.timestampMs);
    final phase = _counter.phase;
    final moving = phase == RepPhase.descending || phase == RepPhase.bottom || phase == RepPhase.ascending;

    FormCheck? failing;
    if (moving) {
      for (final check in config.checks) {
        final outcome = check.evaluate(m);
        if (outcome == CheckOutcome.notApplicable) {
          _failStreak.remove(check.id);
          continue;
        }
        final passed = outcome == CheckOutcome.pass;
        final window = _repWindow.putIfAbsent(check.id, _Tally.new);
        window.evaluated++;
        _frames.evaluated++;
        if (passed) {
          window.passed++;
          _frames.passed++;
          _failStreak.remove(check.id);
        } else {
          final streak = _failStreak[check.id] = (_failStreak[check.id] ?? 0) + 1;
          if (streak >= _framesToWarn) failing ??= check;
        }
      }
    } else {
      _failStreak.clear();
    }

    if (event != null) _finishRep(event, frame.timestampMs);

    LiveFeedback feedback;
    if (failing != null) {
      feedback = LiveFeedback(failing.cue, isWarning: true, highlight: failing.highlight);
    } else if (_transient != null && frame.timestampMs < _transientUntilMs) {
      feedback = _transient!;
    } else {
      feedback = LiveFeedback(_guidance(phase));
    }
    return _result(true, m, event, feedback);
  }

  void _finishRep(RepEvent event, int nowMs) {
    FormCheck? firstFailed;
    var acceptable = event.counted;
    for (final check in config.checks) {
      final window = _repWindow[check.id];
      if (window == null || window.evaluated < _minFramesPerRepCheck) continue;
      final passed = window.passed / window.evaluated >= repPassRate;
      final session = _sessionChecks.putIfAbsent(check.id, _Tally.new);
      session.evaluated++;
      if (passed) {
        session.passed++;
      } else {
        acceptable = false;
        firstFailed ??= check;
      }
    }
    _repWindow.clear();

    if (event.counted) {
      _tempo.evaluated++;
      if (event.durationMs >= config.controlledRepMs) _tempo.passed++;
    }
    if (acceptable) _acceptableReps++;

    if (!event.counted) {
      _setTransient(LiveFeedback(config.depthCue, isWarning: true, highlight: _primaryJoints), nowMs, 2500);
    } else if (firstFailed != null) {
      _setTransient(LiveFeedback(firstFailed.cue, isWarning: true, highlight: firstFailed.highlight), nowMs, 2500);
    } else {
      _setTransient(const LiveFeedback('Great rep — good form!'), nowMs, 2000);
    }
  }

  List<int> get _primaryJoints => [config.leftPrimary.vertex, config.rightPrimary.vertex];

  void _setTransient(LiveFeedback feedback, int nowMs, int forMs) {
    _transient = feedback;
    _transientUntilMs = nowMs + forMs;
  }

  String _guidance(RepPhase phase) {
    switch (phase) {
      case RepPhase.unknown:
        return 'Get into the start position to begin';
      case RepPhase.top:
        return reps == 0 ? 'Ready — start when you like' : 'Good — keep going';
      case RepPhase.descending:
        return config.downCue;
      case RepPhase.bottom:
      case RepPhase.ascending:
        return config.upCue;
    }
  }

  PostureAnalysis _result(bool landmarks, PoseMeasurements? m, RepEvent? event, LiveFeedback feedback) {
    return PostureAnalysis(
      landmarksDetected: landmarks,
      anglesCalculated: m != null,
      measurements: m,
      phase: _counter.phase,
      reps: reps,
      partialReps: partialReps,
      repEvent: event,
      feedback: feedback,
      postureScore: postureScore,
    );
  }

  /// The end-of-session report. Safe to call at any time.
  SessionFormReport buildReport() {
    final attempts = reps + partialReps;
    final items = <FormFeedbackItem>[];

    if (attempts == 0) {
      items.add(const FormFeedbackItem(
        id: 'depth',
        verdict: FeedbackVerdict.notAssessed,
        text: 'No repetitions were detected, so form could not be assessed',
      ));
    } else if (partialReps == 0) {
      items.add(FormFeedbackItem(id: 'depth', verdict: FeedbackVerdict.passed, text: config.depthPassedText));
    } else {
      items.add(FormFeedbackItem(
        id: 'depth',
        verdict: FeedbackVerdict.failed,
        text: '${config.depthFailedText} in $partialReps of $attempts attempts',
      ));
    }

    for (final check in config.checks) {
      final tally = _sessionChecks[check.id];
      if (tally == null || tally.evaluated == 0) {
        items.add(FormFeedbackItem(
          id: check.id,
          verdict: FeedbackVerdict.notAssessed,
          text: attempts == 0
              ? '${check.label} was not assessed'
              : '${check.label} could not be assessed from this camera angle',
        ));
      } else if (tally.passed / tally.evaluated >= repPassRate) {
        items.add(FormFeedbackItem(id: check.id, verdict: FeedbackVerdict.passed, text: check.passedText));
      } else {
        items.add(FormFeedbackItem(
          id: check.id,
          verdict: FeedbackVerdict.failed,
          text: '${check.failedText} in ${tally.evaluated - tally.passed} of ${tally.evaluated} reps',
        ));
      }
    }

    if (_tempo.evaluated == 0) {
      items.add(const FormFeedbackItem(
          id: 'tempo', verdict: FeedbackVerdict.notAssessed, text: 'Rep speed was not assessed'));
    } else if (_tempo.passed / _tempo.evaluated >= repPassRate) {
      items.add(const FormFeedbackItem(
          id: 'tempo', verdict: FeedbackVerdict.passed, text: 'Controlled rep speed throughout'));
    } else {
      items.add(FormFeedbackItem(
        id: 'tempo',
        verdict: FeedbackVerdict.failed,
        text: '${_tempo.evaluated - _tempo.passed} of ${_tempo.evaluated} reps were rushed — slow down',
      ));
    }

    return SessionFormReport(
      reps: reps,
      partialReps: partialReps,
      postureScore: postureScore,
      accuracy: accuracy,
      feedback: items,
      validFrames: _validFrames,
      totalFrames: _totalFrames,
    );
  }
}

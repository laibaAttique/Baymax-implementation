import 'dart:math' as math;

import 'exercise_form_rules.dart';

/// Where the user is in the movement cycle.
///
/// top (extended) → descending → bottom (valid depth) → ascending → top
enum RepPhase { unknown, top, descending, bottom, ascending }

/// Emitted when a movement cycle ends back at the top.
class RepEvent {
  /// True for a full repetition; false for an attempt that turned back before
  /// reaching valid depth (not counted).
  final bool counted;
  final double minAngle;
  final int durationMs;
  const RepEvent({required this.counted, required this.minAngle, required this.durationMs});
}

/// Counts repetitions from the rep-driving joint angle (Module 5, FR-6).
///
/// A repetition is counted once, and only for a complete cycle: the joint
/// must start extended, flex to valid depth, and extend again.
///
/// Safeguards:
///  * hysteresis between [ExerciseFormConfig.extendedAngle] and
///    [ExerciseFormConfig.attemptAngle], so jitter at the top cannot start a rep;
///  * exponential smoothing of the angle;
///  * a single-frame jump larger than `maxAngleJump` is discarded as an outlier
///    (three in a row are accepted as a real change);
///  * cycles faster than `minRepMs` are discarded as noise;
///  * bouncing at the bottom cannot count twice, because the count only
///    happens on the return to the top;
///  * if tracking is lost for longer than [trackingTimeoutMs] the cycle in
///    progress is dropped and the user must return to the top first.
class RepCounter {
  final ExerciseFormConfig config;
  final int trackingTimeoutMs;

  RepCounter(this.config, {this.trackingTimeoutMs = 1500});

  static const _smoothing = 0.5;
  static const _framesToConfirmTop = 2;

  RepPhase phase = RepPhase.unknown;
  int count = 0;
  int partialAttempts = 0;

  double? _smoothed;
  double? _lastRaw;
  int? _lastSampleMs;
  int _outliers = 0;
  int _topFrames = 0;
  int _repStartMs = 0;
  double _minAngle = 180;

  /// The smoothed angle the state machine is working from.
  double? get smoothedAngle => _smoothed;

  /// Feed one valid angle sample. Returns an event when a cycle ends.
  RepEvent? update(double angle, int timestampMs) {
    if (!angle.isFinite) return null;
    final last = _lastSampleMs;
    if (last != null && timestampMs - last > trackingTimeoutMs) _resetTracking();

    final lastRaw = _lastRaw;
    if (lastRaw != null && (angle - lastRaw).abs() > config.maxAngleJump && _outliers < 2) {
      _outliers++;
      _lastSampleMs = timestampMs;
      return null;
    }
    _outliers = 0;
    _lastRaw = angle;
    _lastSampleMs = timestampMs;
    final previous = _smoothed;
    final s = previous == null ? angle : previous + _smoothing * (angle - previous);
    _smoothed = s;

    switch (phase) {
      case RepPhase.unknown:
        _topFrames = s >= config.extendedAngle ? _topFrames + 1 : 0;
        if (_topFrames >= _framesToConfirmTop) phase = RepPhase.top;
        return null;
      case RepPhase.top:
        if (s < config.attemptAngle) {
          phase = RepPhase.descending;
          _repStartMs = timestampMs;
          _minAngle = s;
        }
        return null;
      case RepPhase.descending:
        _minAngle = math.min(_minAngle, s);
        if (s <= config.flexedAngle) {
          phase = RepPhase.bottom;
        } else if (s >= config.extendedAngle) {
          return _finish(timestampMs, reachedDepth: false);
        }
        return null;
      case RepPhase.bottom:
        _minAngle = math.min(_minAngle, s);
        if (s > config.flexedAngle + 15) phase = RepPhase.ascending;
        return null;
      case RepPhase.ascending:
        if (s <= config.flexedAngle) {
          _minAngle = math.min(_minAngle, s);
          phase = RepPhase.bottom;
        } else if (s >= config.extendedAngle) {
          return _finish(timestampMs, reachedDepth: true);
        }
        return null;
    }
  }

  RepEvent? _finish(int timestampMs, {required bool reachedDepth}) {
    phase = RepPhase.top;
    final duration = timestampMs - _repStartMs;
    if (duration < config.minRepMs) return null; // too fast to be a real movement
    if (reachedDepth) {
      count++;
    } else {
      partialAttempts++;
    }
    return RepEvent(counted: reachedDepth, minAngle: _minAngle, durationMs: duration);
  }

  void _resetTracking() {
    phase = RepPhase.unknown;
    _smoothed = null;
    _lastRaw = null;
    _outliers = 0;
    _topFrames = 0;
  }
}

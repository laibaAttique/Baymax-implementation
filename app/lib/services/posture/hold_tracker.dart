import 'exercise_form_rules.dart';

/// Times a static hold (plank, wall sit) from the camera: only the time the person is actually in position counts.
///
/// "In position" means the rep-driving angle and the torso lean are inside the configured ranges
/// ([ExerciseFormConfig.holdMinAngle] …). Safeguards against landmark jitter:
///  * entering the position needs [framesToEnter] consecutive matching frames;
///  * leaving it needs [graceMs] without a matching frame, so one noisy frame does not stop the clock;
///  * time is added frame to frame, never more than [maxStepMs] at once, so a stalled camera cannot add time;
///  * a frame without a usable pose counts as "not matching".
class HoldTracker {
  final ExerciseFormConfig config;
  HoldTracker(this.config);

  static const framesToEnter = 3;
  static const graceMs = 800;
  static const maxStepMs = 250;

  bool inPosition = false;
  int heldMs = 0;
  int longestMs = 0;

  /// How many separate times the position was taken.
  int entries = 0;

  int _matchFrames = 0;
  int? _lastMatchMs;
  int? _lastMs;
  int _currentMs = 0;

  bool matches(PoseMeasurements m) {
    bool within(double? v, double? lo, double? hi) {
      if (lo == null && hi == null) return true;
      if (v == null) return false;
      return (lo == null || v >= lo) && (hi == null || v <= hi);
    }

    return within(m.primaryAngle, config.holdMinAngle, config.holdMaxAngle) &&
        within(m.torsoLean, config.holdMinLean, config.holdMaxLean);
  }

  /// Feed every frame; [m] is null when no usable pose was found.
  void update(PoseMeasurements? m, int timestampMs) {
    final last = _lastMs;
    _lastMs = timestampMs;
    final ok = m != null && matches(m);
    if (ok) {
      _lastMatchMs = timestampMs;
      _matchFrames++;
      if (!inPosition && _matchFrames >= framesToEnter) {
        inPosition = true;
        entries++;
        _currentMs = 0;
        return;
      }
    } else {
      _matchFrames = 0;
      final lastMatch = _lastMatchMs;
      if (inPosition && (lastMatch == null || timestampMs - lastMatch > graceMs)) {
        inPosition = false;
        return;
      }
    }
    if (inPosition && last != null && ok) {
      final step = (timestampMs - last).clamp(0, maxStepMs);
      heldMs += step;
      _currentMs += step;
      if (_currentMs > longestMs) longestMs = _currentMs;
    }
  }

  int get heldSeconds => heldMs ~/ 1000;
}

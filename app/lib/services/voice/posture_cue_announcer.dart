import '../../models/workout_session.dart';
import '../workout_session/workout_session_controller.dart';
import 'speech_output.dart';
import 'voice_assistant_controller.dart';

/// Speaks posture corrections during a camera session (Module 6, FR-5).
///
/// The pose engine produces feedback many times a second, so cues are rate
/// limited: only corrections are spoken (not routine guidance), never while
/// something else is being said or the assistant is open, at most one every
/// [minGap], and the same correction is not repeated within [repeatAfter].
class PostureCueAnnouncer {
  final WorkoutSessionContext session;
  final SpeechOutput output;
  final Duration minGap;
  final Duration repeatAfter;
  final DateTime Function() _now;

  PostureCueAnnouncer({
    required this.session,
    required this.output,
    this.minGap = const Duration(seconds: 5),
    this.repeatAfter = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool enabled = true;
  String? _lastMessage;
  DateTime? _lastSpokenAt;

  void attach() => session.addListener(_onSessionChanged);

  void detach() => session.removeListener(_onSessionChanged);

  void _onSessionChanged() {
    if (!enabled || session.status != SessionStatus.active || session.mode != SessionMode.camera) return;
    final message = session.feedbackMessage;
    if (message == null || !session.feedbackIsWarning) return;
    if (output.isSpeaking.value || VoiceAssistantController.openAssistants > 0) return;

    final now = _now();
    final last = _lastSpokenAt;
    if (last != null) {
      final since = now.difference(last);
      if (since < minGap) return;
      if (message == _lastMessage && since < repeatAfter) return;
    }
    _lastMessage = message;
    _lastSpokenAt = now;
    output.speak(message);
  }
}

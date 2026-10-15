import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_permissions.dart';
import '../workout_session/workout_session_controller.dart';
import 'coach_responder.dart';
import 'dialogflow_intent_service.dart';
import 'intent_service.dart';
import 'speech_output.dart';
import 'speech_recognizer.dart';

/// The real state of the voice interaction. The screen renders exactly this.
enum VoiceState {
  idle,
  listening,
  processing,
  speaking,

  /// Something went wrong this turn; the user can retry.
  error,

  /// Speech recognition cannot be used (no service or no permission).
  unavailable,
}

/// Runs one voice turn at a time (Module 6):
///
///   speech-to-text → intent recognition → contextual response → text-to-speech
///
/// The microphone is only opened by [startListening] (a user action) and is
/// released by [close].
class VoiceAssistantController extends ChangeNotifier {
  final SpeechRecognizer recognizer;
  final SpeechOutput output;
  final IntentService intents;
  final WorkoutSessionController session;
  final CoachResponder _responder;

  VoiceAssistantController({
    SpeechRecognizer? recognizer,
    SpeechOutput? output,
    IntentService? intents,
    WorkoutSessionController? session,
    WorkoutScheduleProvider schedule = const UserPlanScheduleProvider(),
  })  : recognizer = recognizer ?? DeviceSpeechRecognizer(),
        output = output ?? DeviceSpeechOutput.instance,
        intents = intents ?? HybridIntentService(),
        session = session ?? WorkoutSessionController.instance,
        _responder = CoachResponder(session: session ?? WorkoutSessionController.instance, schedule: schedule) {
    openAssistants++;
    final engine = this.intents;
    if (engine is HybridIntentService) unawaited(engine.warmUp());
  }

  /// Number of assistants currently open. Posture voice cues stay quiet while
  /// the user is talking to the assistant.
  static int openAssistants = 0;

  /// Upper bound for intent recognition. Report FR19.3 targets a reply within
  /// 3 s; this leaves room for Dialogflow's own limit plus the on-device
  /// fallback, which answers immediately.
  static const responseTimeout = Duration(milliseconds: 4500);

  VoiceState _state = VoiceState.idle;
  String _transcript = '';
  CoachResponse? _response;
  String? _errorMessage;
  bool _settingsNeeded = false;
  bool _speechOutputFailed = false;
  bool _awaitingStopConfirmation = false;
  bool _closed = false;

  /// Incremented whenever a turn starts or is abandoned, so late callbacks
  /// from an old turn are ignored.
  int _turn = 0;

  VoiceState get state => _state;

  /// What the recogniser has heard in the current/last turn.
  String get transcript => _transcript;
  CoachResponse? get response => _response;
  String? get errorMessage => _errorMessage;

  /// True when microphone access must be enabled in the system settings.
  bool get settingsNeeded => _settingsNeeded;

  /// True when the last reply could not be spoken and is shown as text only.
  bool get speechOutputFailed => _speechOutputFailed;
  ValueListenable<double> get soundLevel => recognizer.soundLevel;
  String _lastEngine = '';

  /// Engine that recognised the last question, or the configured engine
  /// before any question.
  String get engineName => _lastEngine.isNotEmpty ? _lastEngine : intents.engineName;

  /// The mic button: start listening, or stop and use what was heard.
  Future<void> toggleMic() async {
    if (_state == VoiceState.processing) return;
    if (_state == VoiceState.listening) {
      await recognizer.stop();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (_closed) return;
    final turn = ++_turn;
    await output.stop();

    final permission = await AppPermissions.instance.requestMicrophone();
    if (turn != _turn || _closed) return;
    if (permission != PermissionOutcome.granted) {
      _settingsNeeded = permission == PermissionOutcome.permanentlyDenied;
      _fail(
        VoiceState.unavailable,
        _settingsNeeded
            ? 'Microphone access is turned off for Baymax. Enable it in Settings to use voice commands.'
            : 'Microphone access is needed for voice commands. You can still tap a suggestion below.',
      );
      return;
    }
    _settingsNeeded = false;

    final availability = await recognizer.initialize();
    if (turn != _turn || _closed) return;
    if (availability != SpeechAvailability.available) {
      _fail(
        VoiceState.unavailable,
        availability == SpeechAvailability.permissionDenied
            ? 'Microphone access is needed for voice commands. You can still tap a suggestion below.'
            : 'Speech recognition is not available on this device. You can still tap a suggestion below.',
      );
      return;
    }

    _transcript = '';
    _errorMessage = null;
    _state = VoiceState.listening;
    notifyListeners();

    var handled = false;
    try {
      await recognizer.listen(
        onResult: (text, isFinal) {
          if (turn != _turn || handled) return;
          _transcript = text;
          if (isFinal) {
            handled = true;
            unawaited(_process(text, turn));
          } else {
            notifyListeners();
          }
        },
        onError: (error) {
          if (turn != _turn || handled) return;
          handled = true;
          _fail(VoiceState.error, error.userMessage);
        },
        onDone: () {
          if (turn != _turn || handled) return;
          handled = true;
          // Listening ended without a final result: use what was heard, but
          // never submit an empty query.
          unawaited(_process(_transcript, turn));
        },
      );
    } catch (_) {
      if (turn != _turn) return;
      _fail(VoiceState.error, 'The microphone could not be started. Please try again.');
    }
  }

  /// Stops listening and throws away whatever was heard.
  Future<void> cancelListening() async {
    if (_state != VoiceState.listening) return;
    _turn++;
    await recognizer.cancel();
    _transcript = '';
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Runs a typed or tapped phrase (the quick-action chips) through the same
  /// intent → response → speech pipeline.
  Future<void> submitText(String text) async {
    if (_closed || _state == VoiceState.processing) return;
    final turn = ++_turn;
    if (_state == VoiceState.listening) await recognizer.cancel();
    _transcript = text;
    await _process(text, turn);
  }

  Future<void> _process(String text, int turn) async {
    final query = text.trim();
    if (query.isEmpty) {
      _fail(VoiceState.error, "I didn't catch that. Tap the mic and try again.");
      return;
    }
    _state = VoiceState.processing;
    _errorMessage = null;
    notifyListeners();

    final IntentResult result;
    try {
      result = await intents.detect(query).timeout(responseTimeout);
    } catch (_) {
      if (turn != _turn) return;
      _fail(VoiceState.error, "I couldn't work that out in time. Please try again.");
      return;
    }
    if (turn != _turn || _closed) return;

    _lastEngine = result.engine;
    final response = _responder.respond(result, awaitingStopConfirmation: _awaitingStopConfirmation);
    _awaitingStopConfirmation = response.action == CoachAction.askStopConfirmation;
    _apply(response.action);
    _response = response;
    _speechOutputFailed = false;
    _state = VoiceState.speaking;
    notifyListeners();

    final spoken = await output.speak(response.text);
    if (turn != _turn || _closed) return;
    _speechOutputFailed = !spoken;
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Only the three session controls below can be triggered by voice, each
  /// validated by the session controller; ending a session needs a spoken or
  /// tapped confirmation first.
  void _apply(CoachAction action) {
    switch (action) {
      case CoachAction.pauseSession:
        session.pause();
      case CoachAction.resumeSession:
        session.resume();
      case CoachAction.stopSession:
        session.requestFinish();
      case CoachAction.askStopConfirmation:
      case CoachAction.none:
        break;
    }
  }

  Future<void> replay() async {
    final response = _response;
    if (response == null || _state == VoiceState.listening || _state == VoiceState.processing) return;
    final turn = ++_turn;
    _state = VoiceState.speaking;
    notifyListeners();
    final spoken = await output.speak(response.text);
    if (turn != _turn || _closed) return;
    _speechOutputFailed = !spoken;
    _state = VoiceState.idle;
    notifyListeners();
  }

  Future<void> stopSpeaking() async {
    if (_state != VoiceState.speaking) return;
    _turn++;
    await output.stop();
    _state = VoiceState.idle;
    notifyListeners();
  }

  void _fail(VoiceState state, String message) {
    _state = state;
    _errorMessage = message;
    notifyListeners();
  }

  /// Releases the microphone, stops speech and discards any pending command.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _turn++;
    openAssistants--;
    await recognizer.cancel();
    await output.stop();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechAvailability {
  available,
  permissionDenied,

  /// No speech-recognition service on this device.
  unavailable,
}

enum SpeechErrorKind { noMatch, timeout, permission, network, other }

class SpeechError {
  final SpeechErrorKind kind;
  const SpeechError(this.kind);

  String get userMessage {
    switch (kind) {
      case SpeechErrorKind.noMatch:
        return "I didn't catch that. Tap the mic and try again.";
      case SpeechErrorKind.timeout:
        return "I didn't hear anything. Tap the mic and try again.";
      case SpeechErrorKind.permission:
        return 'Microphone access is needed for voice commands.';
      case SpeechErrorKind.network:
        return 'Speech recognition needs a network connection on this device.';
      case SpeechErrorKind.other:
        return 'Speech recognition stopped unexpectedly. Please try again.';
    }
  }
}

/// Speech-to-text (Module 6, FR-1). The assistant depends on this interface.
abstract class SpeechRecognizer {
  Future<SpeechAvailability> initialize();

  /// Starts listening. [onResult] receives the live transcript and, once, the
  /// final one. [onDone] fires when listening ends for any reason.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechError error) onError,
    required VoidCallback onDone,
  });

  /// Stops listening and delivers what was heard so far.
  Future<void> stop();

  /// Stops listening and discards what was heard.
  Future<void> cancel();

  /// Live microphone level, 0..1, for the waveform.
  ValueListenable<double> get soundLevel;
}

/// [SpeechRecognizer] backed by the platform recogniser via `speech_to_text`.
class DeviceSpeechRecognizer implements SpeechRecognizer {
  final SpeechToText _speech = SpeechToText();
  final ValueNotifier<double> _level = ValueNotifier<double>(0);

  bool _ready = false;
  void Function(SpeechError)? _onError;
  VoidCallback? _onDone;

  @override
  ValueListenable<double> get soundLevel => _level;

  @override
  Future<SpeechAvailability> initialize() async {
    if (_ready) return SpeechAvailability.available;
    try {
      _ready = await _speech.initialize(onError: _handleError, onStatus: _handleStatus);
      if (_ready) return SpeechAvailability.available;
      return await _speech.hasPermission ? SpeechAvailability.unavailable : SpeechAvailability.permissionDenied;
    } on PlatformException {
      return SpeechAvailability.unavailable;
    } on MissingPluginException {
      return SpeechAvailability.unavailable;
    }
  }

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechError error) onError,
    required VoidCallback onDone,
  }) async {
    _onError = onError;
    _onDone = onDone;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: (db) => _level.value = ((db + 2) / 12).clamp(0.0, 1.0),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _handleError(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    final SpeechErrorKind kind;
    if (msg.contains('no_match')) {
      kind = SpeechErrorKind.noMatch;
    } else if (msg.contains('timeout')) {
      kind = SpeechErrorKind.timeout;
    } else if (msg.contains('permission')) {
      kind = SpeechErrorKind.permission;
    } else if (msg.contains('network') || msg.contains('server')) {
      kind = SpeechErrorKind.network;
    } else {
      kind = SpeechErrorKind.other;
    }
    _level.value = 0;
    _onError?.call(SpeechError(kind));
  }

  void _handleStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _level.value = 0;
      if (status == 'done') _onDone?.call();
    }
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _level.value = 0;
  }

  @override
  Future<void> cancel() async {
    _onError = null;
    _onDone = null;
    await _speech.cancel();
    _level.value = 0;
  }
}

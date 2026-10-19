import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech (Module 6, FR-4).
abstract class SpeechOutput {
  /// True while audio is playing.
  ValueListenable<bool> get isSpeaking;

  /// Speaks [text], first stopping anything already playing so two utterances
  /// never overlap. Completes when playback ends. Returns false when the
  /// device could not speak it (the text is still shown on screen).
  Future<bool> speak(String text);
  Future<void> stop();
}

/// [SpeechOutput] backed by the platform engine via `flutter_tts`. One shared
/// instance, so the assistant and the posture cues cannot talk over each other.
class DeviceSpeechOutput implements SpeechOutput {
  DeviceSpeechOutput._();
  static final DeviceSpeechOutput instance = DeviceSpeechOutput._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> _speaking = ValueNotifier<bool>(false);
  bool _configured = false;
  Completer<bool>? _current;

  @override
  ValueListenable<bool> get isSpeaking => _speaking;

  Future<void> _configure() async {
    if (_configured) return;
    _tts.setStartHandler(() => _speaking.value = true);
    _tts.setCompletionHandler(() => _finish(true));
    _tts.setCancelHandler(() => _finish(true));
    _tts.setErrorHandler((_) => _finish(false));
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    _configured = true;
  }

  void _finish(bool ok) {
    _speaking.value = false;
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  @override
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      await _configure();
      if (_speaking.value || _current != null) await stop();
      final completer = _current = Completer<bool>();
      final started = await _tts.speak(text);
      if (started != 1) {
        _finish(false);
        return false;
      }
      // Guard against an engine that never reports completion.
      return await completer.future.timeout(Duration(seconds: 10 + text.length ~/ 8), onTimeout: () {
        _finish(true);
        return true;
      });
    } on PlatformException {
      _finish(false);
      return false;
    } on MissingPluginException {
      _finish(false);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on PlatformException {
      // Nothing was playing.
    } on MissingPluginException {
      // No engine on this platform.
    }
    _finish(true);
  }
}

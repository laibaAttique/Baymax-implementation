import 'package:app/services/app_permissions.dart';
import 'package:app/services/voice/coach_responder.dart';
import 'package:app/services/voice/speech_output.dart';
import 'package:app/services/voice/speech_recognizer.dart';
import 'package:flutter/foundation.dart';

class FakePermissions extends AppPermissions {
  PermissionOutcome camera;
  PermissionOutcome microphone;
  int cameraRequests = 0;
  int microphoneRequests = 0;

  FakePermissions({this.camera = PermissionOutcome.granted, this.microphone = PermissionOutcome.granted});

  @override
  Future<PermissionOutcome> requestCamera() async {
    cameraRequests++;
    return camera;
  }

  @override
  Future<PermissionOutcome> requestMicrophone() async {
    microphoneRequests++;
    return microphone;
  }

  @override
  Future<bool> openSettings() async => true;
}

/// A recogniser the test drives by hand.
class FakeSpeechRecognizer implements SpeechRecognizer {
  SpeechAvailability availability = SpeechAvailability.available;
  final ValueNotifier<double> level = ValueNotifier<double>(0);
  int listenCalls = 0;
  int cancelCalls = 0;
  bool listening = false;

  void Function(String text, bool isFinal)? _onResult;
  void Function(SpeechError error)? _onError;
  VoidCallback? _onDone;

  @override
  ValueListenable<double> get soundLevel => level;

  @override
  Future<SpeechAvailability> initialize() async => availability;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(SpeechError error) onError,
    required VoidCallback onDone,
  }) async {
    listenCalls++;
    listening = true;
    _onResult = onResult;
    _onError = onError;
    _onDone = onDone;
  }

  void hear(String text, {bool isFinal = false}) {
    if (isFinal) listening = false;
    _onResult?.call(text, isFinal);
  }

  void fail(SpeechErrorKind kind) {
    listening = false;
    _onError?.call(SpeechError(kind));
  }

  /// The platform stopped listening without a final result.
  void finish() {
    listening = false;
    _onDone?.call();
  }

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> cancel() async {
    cancelCalls++;
    listening = false;
  }
}

class FakeSpeechOutput implements SpeechOutput {
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);
  final List<String> spoken = [];
  bool works = true;
  int stops = 0;

  /// Most utterances that were ever playing at once.
  int maxConcurrent = 0;
  int _playing = 0;

  @override
  ValueListenable<bool> get isSpeaking => speaking;

  @override
  Future<bool> speak(String text) async {
    if (!works) return false;
    await stop();
    spoken.add(text);
    _playing++;
    if (_playing > maxConcurrent) maxConcurrent = _playing;
    speaking.value = true;
    await Future<void>.delayed(Duration.zero);
    _playing--;
    speaking.value = false;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    speaking.value = false;
  }
}

class FakeSchedule implements WorkoutScheduleProvider {
  @override
  final bool hasPlan;
  final TodaySchedule? schedule;
  const FakeSchedule({this.hasPlan = false, this.schedule});

  @override
  TodaySchedule? today() => schedule;
}

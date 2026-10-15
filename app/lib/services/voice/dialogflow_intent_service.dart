import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../exercise_library.dart';
import 'intent_service.dart';

/// Sends recognised text to the backend and returns its raw JSON reply.
typedef DialogflowTransport = Future<dynamic> Function(String text, String session);

/// Dialogflow ES intent recognition (report Module 6, FR-2).
///
/// The app never talks to Dialogflow directly: it sends the transcript to
/// `POST /api/voice/intent` on the Baymax backend, which holds the
/// service-account key (`backend/routes/voice.js`). Only the transcript is
/// sent — no audio and no camera data. Agent definition:
/// `backend/dialogflow/agent/`, whose intent names equal [CoachIntent] names.
class DialogflowIntentService implements IntentService {
  final DialogflowTransport _transport;

  /// Groups this app run's queries into one Dialogflow session.
  final String _session = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  DialogflowIntentService({DialogflowTransport? transport}) : _transport = transport ?? _viaBackend;

  static Future<dynamic> _viaBackend(String text, String session) => ApiClient.instance.send(
        'POST',
        '/api/voice/intent',
        body: {'text': text, 'session': session},
        timeout: HybridIntentService.primaryTimeout,
      );

  /// Opens the connection, refreshes the sign-in token and lets the backend
  /// prepare its Dialogflow credentials before the first question.
  /// Returns whether Dialogflow is available.
  static Future<bool> warmUp() async {
    try {
      final json = await ApiClient.instance.send('GET', '/api/voice/status', timeout: const Duration(seconds: 8));
      return json is Map && json['dialogflow'] == true;
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] warm-up failed: $e');
      return false;
    }
  }

  @override
  String get engineName => 'Dialogflow';

  @override
  Future<IntentResult> detect(String utterance) async {
    final text = utterance.trim();
    if (text.isEmpty) return IntentResult(CoachIntent.unknown, engine: engineName);
    final json = await _transport(text.length > 256 ? text.substring(0, 256) : text, _session);
    if (json is! Map) throw const ApiException('Unexpected reply from the intent service.');

    final name = json['intent'];
    final intent = json['isFallback'] == true || name is! String
        ? CoachIntent.unknown
        : (CoachIntent.values.asNameMap()[name] ?? CoachIntent.unknown);
    final params = json['parameters'] is Map ? json['parameters'] as Map : const {};
    final exerciseId = params['exercise'];
    final topic = params['topic'];
    return IntentResult(
      intent,
      exercise: exerciseId is String && exerciseId.isNotEmpty && ExerciseLibrary.isLoaded
          ? ExerciseLibrary.byId(exerciseId)
          : null,
      topic: topic is String && topic.isNotEmpty ? topic : null,
      utterance: utterance,
      engine: engineName,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

/// Dialogflow first, the on-device rules as fallback.
///
///  * Safety reports (pain, dizziness …) are always handled on-device first,
///    so they never depend on the network.
///  * If the backend says Dialogflow is not configured, or does not answer in
///    time, the rules answer and Dialogflow is skipped for a while instead of
///    adding a delay to every question.
///  * If Dialogflow returns its fallback intent, or a low-confidence match
///    that disagrees with a rule match, the rules' answer is used.
class HybridIntentService implements IntentService {
  final IntentService primary;
  final IntentService fallback;
  final DateTime Function() _now;

  HybridIntentService({IntentService? primary, IntentService? fallback, DateTime Function()? now})
      : primary = primary ?? DialogflowIntentService(),
        fallback = fallback ?? RuleBasedIntentService(),
        _now = now ?? DateTime.now;

  static const _notConfiguredBackoff = Duration(minutes: 5);
  static const _failureBackoff = Duration(seconds: 10);

  /// How long to wait for Dialogflow before answering with the rules.
  static const primaryTimeout = Duration(milliseconds: 3500);

  /// Below this Dialogflow confidence a disagreeing rule match wins.
  static const minConfidence = 0.6;

  DateTime? _skipPrimaryUntil;
  bool _lastPrimaryFailed = false;

  /// True after Dialogflow has failed or is not configured; the next attempt
  /// happens after a back-off.
  bool get primaryUnavailable => _lastPrimaryFailed;

  /// Warms up the Dialogflow route (see [DialogflowIntentService.warmUp]).
  /// A failure here does not trigger the back-off; the first real question
  /// still tries Dialogflow.
  Future<void> warmUp() async {
    if (primary is DialogflowIntentService) await DialogflowIntentService.warmUp();
  }

  @override
  String get engineName =>
      _lastPrimaryFailed ? '${fallback.engineName} (Dialogflow unavailable)' : '${primary.engineName}, with on-device fallback';

  @override
  Future<IntentResult> detect(String utterance) async {
    final local = await fallback.detect(utterance);
    if (local.intent == CoachIntent.painOrSymptom) return local;

    final skipUntil = _skipPrimaryUntil;
    if (skipUntil != null && _now().isBefore(skipUntil)) {
      if (kDebugMode) debugPrint('[voice] skipping Dialogflow until $skipUntil after an earlier failure');
      return _offline(local);
    }

    try {
      final remote = await primary.detect(utterance).timeout(primaryTimeout);
      _lastPrimaryFailed = false;
      _skipPrimaryUntil = null;
      if (local.intent != CoachIntent.unknown && remote.intent != local.intent) {
        final confidence = remote.confidence;
        if (remote.intent == CoachIntent.unknown || (confidence != null && confidence < minConfidence)) return local;
      }
      return remote.exercise == null && local.exercise != null ? remote.copyWith(exercise: local.exercise) : remote;
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[voice] Dialogflow unavailable: ${e.statusCode ?? '-'} ${e.message}');
      _markDown(e.statusCode == 503 ? _notConfiguredBackoff : _failureBackoff);
    } catch (e) {
      if (kDebugMode) debugPrint('[voice] Dialogflow unavailable: $e');
      _markDown(_failureBackoff);
    }
    return _offline(local);
  }

  void _markDown(Duration backoff) {
    _lastPrimaryFailed = true;
    _skipPrimaryUntil = _now().add(backoff);
  }

  IntentResult _offline(IntentResult local) =>
      local.copyWith(engine: '${fallback.engineName} (Dialogflow unavailable)');
}

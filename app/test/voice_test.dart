import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/models/workout_session.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/voice/coach_responder.dart';
import 'package:app/services/voice/dialogflow_intent_service.dart';
import 'package:app/services/voice/intent_service.dart';
import 'package:app/services/voice/posture_cue_announcer.dart';
import 'package:app/services/voice/speech_recognizer.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pose_fixtures.dart';
import 'support/voice_fakes.dart';

const _request = WorkoutSessionRequest(exercise: squatExercise);

/// Feeds a real movement through the real engine into [session].
PostureEngine _perform(WorkoutSessionController session, Motion motion, [PostureEngine? running]) {
  final engine = running ?? PostureEngine(ExerciseFormRules.forExercise('squat')!);
  for (final frame in motion.frames) {
    session.updatePosture(engine.process(frame), angleLabel: 'Knee');
  }
  return engine;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync(encoding: utf8));
  });

  group('Workout session state', () {
    test('camera session: live values, pause/resume and summary', () {
      final session = WorkoutSessionController();
      expect(session.hasActiveSession, isFalse);
      session.start(_request, SessionMode.camera);
      final engine = _perform(session, Motion().hold(400).squat().squat());
      expect(session.reps, 2);
      expect(session.postureScore, 100);
      expect(session.anglesCalculated, isTrue);
      expect(session.angles.keys, contains('Left knee'));

      expect(session.pause(), isTrue);
      expect(session.pause(), isFalse);
      // Frames arriving while paused are ignored.
      _perform(session, Motion(startMs: 9000).hold(400).squat());
      expect(session.reps, 2);
      expect(session.resume(), isTrue);

      final summary = session.finish(report: engine.buildReport(), averageFps: 21.5);
      expect(session.status, SessionStatus.finished);
      expect(summary.reps, 2);
      expect(summary.postureScore, 100);
      expect(summary.averageFps, 21.5);
      expect(summary.feedback, isNotEmpty);
      expect(session.lastSummary, same(summary));
      expect(session.history, [summary]);
    });

    test('manual session never has a posture score', () {
      final session = WorkoutSessionController()..start(_request, SessionMode.manual);
      session.recordManualSet(12);
      session.recordManualSet(12);
      final summary = session.finish(tooDifficult: true);
      expect(summary.reps, 24);
      expect(summary.setsCompleted, 2);
      expect(summary.postureScore, isNull);
      expect(summary.accuracy, isNull);
      expect(summary.postureAnalysed, isFalse);
      expect(summary.tooDifficult, isTrue);
    });

    test('listeners are not notified for frames that change nothing visible', () {
      final session = WorkoutSessionController()..start(_request, SessionMode.camera);
      var notifications = 0;
      session.addListener(() => notifications++);
      _perform(session, Motion().hold(2000));
      expect(notifications, lessThan(5));
    });
  });

  group('Intent recognition (local rules)', () {
    final intents = RuleBasedIntentService();
    const cases = <String, CoachIntent>{
      'How many reps have I done?': CoachIntent.repCount,
      'rep count': CoachIntent.repCount,
      'how many squats did I complete so far': CoachIntent.repCount,
      'How many sets do I have?': CoachIntent.currentExercise,
      "How's my form?": CoachIntent.postureFeedback,
      'What am I doing wrong': CoachIntent.postureFeedback,
      "What's my posture score": CoachIntent.postureScore,
      'How do I do a squat?': CoachIntent.exerciseTechnique,
      'show me how to do this': CoachIntent.exerciseTechnique,
      'push ups': CoachIntent.exerciseTechnique,
      'What exercise is this?': CoachIntent.currentExercise,
      "What's next?": CoachIntent.nextExercise,
      "What's my workout today?": CoachIntent.schedule,
      'Show exercises': CoachIntent.schedule,
      'How long have I been going': CoachIntent.sessionTime,
      'Pause workout': CoachIntent.pauseSession,
      'Resume workout': CoachIntent.resumeSession,
      'Stop the session': CoachIntent.stopSession,
      'End session': CoachIntent.stopSession,
      'Yes, end it': CoachIntent.confirmYes,
      'No, keep going': CoachIntent.confirmNo,
      'My knee hurts': CoachIntent.painOrSymptom,
      'I feel dizzy': CoachIntent.painOrSymptom,
      'how should I breathe': CoachIntent.generalGuidance,
      'what can you do': CoachIntent.help,
      'hello': CoachIntent.greeting,
      'Start workout': CoachIntent.startWorkout,
      'what is the capital of France': CoachIntent.unknown,
      '   ': CoachIntent.unknown,
    };
    for (final entry in cases.entries) {
      test('"${entry.key}" → ${entry.value.name}', () async {
        expect((await intents.detect(entry.key)).intent, entry.value);
      });
    }

    test('picks the most specific exercise named', () async {
      expect((await intents.detect('how do I do a squat')).exercise?.id, 'squat');
      expect((await intents.detect('how do I do jump squats')).exercise?.id, 'jump_squats');
      expect((await intents.detect('how to do a pushup')).exercise?.id, 'pushup');
      expect((await intents.detect('teach me the chair squat')).exercise?.id, 'chair_squat');
    });

    test('a safety report wins over any other wording', () async {
      expect((await intents.detect('how many reps until this pain stops')).intent, CoachIntent.painOrSymptom);
    });
  });

  group('Dialogflow intent recognition', () {
    test('maps the agent reply to the app intent and its parameters', () async {
      final dialogflow = DialogflowIntentService(transport: (text, session) async {
        expect(text, 'teach me squats');
        expect(session, hasLength(16));
        return {
          'intent': 'exerciseTechnique',
          'isFallback': false,
          'confidence': 0.91,
          'parameters': {'exercise': 'squat'},
        };
      });
      final result = await dialogflow.detect('teach me squats');
      expect(result.intent, CoachIntent.exerciseTechnique);
      expect(result.exercise!.id, 'squat');
      expect(result.engine, 'Dialogflow');
    });

    test('fallback intent and unknown names become unknown', () async {
      final fallback = DialogflowIntentService(transport: (_, _) async => {'intent': 'Default Fallback Intent', 'isFallback': true});
      expect((await fallback.detect('blah')).intent, CoachIntent.unknown);
      final renamed = DialogflowIntentService(transport: (_, _) async => {'intent': 'somethingElse', 'isFallback': false});
      expect((await renamed.detect('blah')).intent, CoachIntent.unknown);
    });

    test('every agent intent name exists in the app', () {
      final dir = Directory('../backend/dialogflow/agent/intents');
      final names = [
        for (final f in dir.listSync().whereType<File>())
          if (!f.path.contains('_usersays_') && !f.path.contains('Default Fallback'))
            (jsonDecode(f.readAsStringSync()) as Map)['name'] as String,
      ];
      expect(names, isNotEmpty);
      for (final n in names) {
        expect(CoachIntent.values.asNameMap().containsKey(n), isTrue, reason: n);
      }
      // Every recognisable intent (not "unknown") is covered by the agent.
      expect(names.toSet(), {for (final i in CoachIntent.values) if (i != CoachIntent.unknown) i.name});
    });

    test('hybrid: uses Dialogflow when it answers', () async {
      var calls = 0;
      final hybrid = HybridIntentService(
        primary: DialogflowIntentService(transport: (_, _) async {
          calls++;
          return {'intent': 'repCount', 'isFallback': false, 'parameters': {}};
        }),
      );
      final result = await hybrid.detect('give me the tally');
      expect(result.intent, CoachIntent.repCount);
      expect(result.engine, 'Dialogflow');
      expect(calls, 1);
    });

    test('hybrid: safety reports never wait for the network', () async {
      var calls = 0;
      final hybrid = HybridIntentService(
        primary: DialogflowIntentService(transport: (_, _) async {
          calls++;
          return {'intent': 'repCount'};
        }),
      );
      expect((await hybrid.detect('my knee hurts')).intent, CoachIntent.painOrSymptom);
      expect(calls, 0);
    });

    test('hybrid: not configured → rules answer, and Dialogflow is skipped for a while', () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1);
      final hybrid = HybridIntentService(
        now: () => now,
        primary: DialogflowIntentService(transport: (_, _) async {
          calls++;
          throw const ApiException('Dialogflow is not configured', statusCode: 503);
        }),
      );
      final first = await hybrid.detect('how many reps');
      expect(first.intent, CoachIntent.repCount);
      expect(first.engine, contains('Dialogflow unavailable'));
      expect(hybrid.primaryUnavailable, isTrue);
      await hybrid.detect('check my form');
      expect(calls, 1, reason: 'backed off');
      now = now.add(const Duration(minutes: 6));
      await hybrid.detect('check my form');
      expect(calls, 2, reason: 'retried after the back-off');
    });

    test('hybrid: a timeout falls back to the rules', () async {
      final hybrid = HybridIntentService(
        primary: DialogflowIntentService(transport: (_, _) => Completer<dynamic>().future),
      );
      final result = await hybrid.detect('pause workout');
      expect(result.intent, CoachIntent.pauseSession);
    });

    test('hybrid: a low-confidence Dialogflow match defers to a disagreeing rule match', () async {
      HybridIntentService withReply(double confidence) => HybridIntentService(
            primary: DialogflowIntentService(
                transport: (_, _) async => {'intent': 'confirmYes', 'isFallback': false, 'confidence': confidence}),
          );
      expect((await withReply(0.45).detect('how many squats did I complete so far')).intent, CoachIntent.repCount);
      expect((await withReply(0.95).detect('how many squats did I complete so far')).intent, CoachIntent.confirmYes);
      // No rule match: Dialogflow's answer stands even at low confidence.
      expect((await withReply(0.45).detect('zzz qqq')).intent, CoachIntent.confirmYes);
    });

    test('hybrid: Dialogflow fallback intent defers to a rule match', () async {
      final hybrid = HybridIntentService(
        primary: DialogflowIntentService(transport: (_, _) async => {'intent': 'Default Fallback Intent', 'isFallback': true}),
      );
      expect((await hybrid.detect('how many reps')).intent, CoachIntent.repCount);
      expect((await hybrid.detect('what is the capital of France')).intent, CoachIntent.unknown);
    });
  });

  group('Contextual responses', () {
    late WorkoutSessionController session;
    late CoachResponder coach;
    final intents = RuleBasedIntentService();

    Future<CoachResponse> ask(String text, {bool awaiting = false}) async =>
        coach.respond(await intents.detect(text), awaitingStopConfirmation: awaiting);

    setUp(() {
      session = WorkoutSessionController();
      coach = CoachResponder(session: session, schedule: const FakeSchedule());
    });

    test('with no session, says so instead of inventing numbers', () async {
      for (final q in ['How many reps?', "How's my form?", 'Pause workout', 'How long have I been going']) {
        expect((await ask(q)).text, contains('no active workout session'), reason: q);
      }
    });

    test('rep query reads the live counter', () async {
      session.start(_request, SessionMode.camera);
      final engine = _perform(session, Motion().hold(400).squat().squat().squat(depth: 125));
      final reply = await ask('How many reps have I done?');
      expect(reply.text, contains("You've completed 2 reps of 36, 34 to go"));
      expect(reply.text, contains('1 more was too shallow'));

      _perform(session, Motion(startMs: 20000).hold(400).squat(), engine);
      expect((await ask('rep count')).text, contains('3 reps'));
    });

    test('form query reports the engine’s latest correction', () async {
      session.start(_request, SessionMode.camera);
      _perform(session, Motion().hold(400).moveTo(95, 900).hold(500, torsoLean: 75));
      final reply = await ask("What's wrong with my form?");
      expect(reply.text, contains('Here is what to fix'));
      expect(reply.text, contains(session.feedbackMessage!));
    });

    test('form query with good form, and when the body is not visible', () async {
      session.start(_request, SessionMode.camera);
      _perform(session, Motion().hold(400).squat());
      expect((await ask('Check my form')).text, contains("don't see a form problem"));
      expect((await ask('Check my form')).text, contains('100 percent'));

      session.updatePosture(
        PostureEngine(ExerciseFormRules.forExercise('squat')!).process(squatFrame(170, 99999, visibility: 0.1)),
        angleLabel: 'Knee',
      );
      expect((await ask('Check my form')).text, contains("can't see you clearly"));
    });

    test('score is withheld until there is data', () async {
      session.start(_request, SessionMode.camera);
      expect((await ask("What's my score?")).text, contains("isn't enough data"));
    });

    test('manual mode never claims to analyse posture', () async {
      session.start(_request, SessionMode.manual);
      session.recordManualSet(12);
      expect((await ask("How's my form?")).text, contains("not analysing your posture"));
      expect((await ask("What's my score?")).text, contains('no posture score'));
      expect((await ask('How many reps?')).text, contains('confirmed 1 of 3 sets, 12 reps'));
    });

    test('technique uses the exercise’s own instructions', () async {
      session.start(_request, SessionMode.manual);
      final current = await ask('How do I do this?');
      expect(current.text, contains('Bodyweight Squat'));
      expect(current.text, contains('Step 1: ${squatExercise.steps.first}'));

      final named = await ask('How do I do a plank?');
      expect(named.text, contains('Plank Hold'));
      expect(named.text, contains(ExerciseLibrary.byId('plank')!.steps.first));
    });

    test('technique with no exercise in context asks which one', () async {
      expect((await ask('show me how')).text, contains('Which exercise?'));
    });

    test('schedule: unavailable, rest day, and a real plan', () async {
      expect((await ask("What's my workout today?")).text, contains("don't have a workout schedule"));

      coach = CoachResponder(session: session, schedule: const FakeSchedule(hasPlan: true));
      expect((await ask("What's my workout today?")).text, contains('rest day'));

      coach = CoachResponder(
        session: session,
        schedule: const FakeSchedule(
          hasPlan: true,
          schedule: TodaySchedule(name: 'Lower Body', durationMin: 25, exercises: [squatExercise, plankExercise]),
        ),
      );
      final reply = await ask("What's my workout today?");
      expect(reply.text, contains('Lower Body'));
      expect(reply.text, contains('Bodyweight Squat and Plank Hold'));

      session.start(_request, SessionMode.manual);
      expect((await ask("What's next?")).text, contains('Plank Hold comes after Bodyweight Squat'));
    });

    test('next exercise: uses the handed-over queue, or admits it is unknown', () async {
      session.start(const WorkoutSessionRequest(exercise: squatExercise, upNext: [plankExercise]), SessionMode.manual);
      expect((await ask("What's next?")).text, contains('Next up is Plank Hold'));

      session.start(_request, SessionMode.manual);
      expect((await ask("What's next?")).text, contains("don't know the order"));
    });

    test('pain: stop advice, no diagnosis, and the session is paused', () async {
      session.start(_request, SessionMode.camera);
      final reply = await ask('my knee hurts');
      expect(reply.text, contains('Please stop the exercise now'));
      expect(reply.text, contains("can't diagnose"));
      expect(reply.text.toLowerCase(), isNot(contains('push through it')));
      expect(reply.action, CoachAction.pauseSession);
    });

    test('ending a session needs confirmation', () async {
      session.start(_request, SessionMode.camera);
      final first = await ask('stop the session');
      expect(first.action, CoachAction.askStopConfirmation);
      expect((await ask('yes', awaiting: true)).action, CoachAction.stopSession);
      expect((await ask('no', awaiting: true)).action, CoachAction.none);
      // "yes" on its own, with nothing pending, does nothing.
      expect((await ask('yes')).action, CoachAction.none);
    });

    test('unknown questions get a clear fallback and never more than three chips', () async {
      final reply = await ask('what is the capital of France');
      expect(reply.text, contains('only help with workout questions'));
      session.start(_request, SessionMode.camera);
      for (final q in cases) {
        expect((await ask(q)).chips.length, lessThanOrEqualTo(3), reason: q);
      }
    });
  });

  group('Voice pipeline', () {
    late FakeSpeechRecognizer recognizer;
    late FakeSpeechOutput output;
    late FakePermissions permissions;
    late WorkoutSessionController session;
    late VoiceAssistantController assistant;
    late List<VoiceState> states;

    setUp(() {
      recognizer = FakeSpeechRecognizer();
      output = FakeSpeechOutput();
      permissions = FakePermissions();
      AppPermissions.instance = permissions;
      session = WorkoutSessionController();
      assistant = VoiceAssistantController(
        recognizer: recognizer,
        output: output,
        intents: RuleBasedIntentService(),
        session: session,
        schedule: const FakeSchedule(),
      );
      states = [];
      assistant.addListener(() {
        if (states.isEmpty || states.last != assistant.state) states.add(assistant.state);
      });
    });

    tearDown(() async {
      await assistant.close();
      AppPermissions.instance = const AppPermissions();
    });

    test('listen → transcribe → intent → response → speech, with real states', () async {
      session.start(_request, SessionMode.camera);
      _perform(session, Motion().hold(400).squat().squat());

      expect(assistant.state, VoiceState.idle);
      await assistant.startListening();
      expect(assistant.state, VoiceState.listening);
      recognizer.hear('how many');
      expect(assistant.transcript, 'how many');
      recognizer.hear('how many reps have I done', isFinal: true);
      await _settle();

      expect(states, [VoiceState.listening, VoiceState.processing, VoiceState.speaking, VoiceState.idle]);
      expect(assistant.response!.text, contains("You've completed 2 reps"));
      expect(output.spoken, [assistant.response!.text]);
      expect(assistant.speechOutputFailed, isFalse);
    });

    test('microphone denied: never listens', () async {
      permissions.microphone = PermissionOutcome.denied;
      await assistant.startListening();
      expect(assistant.state, VoiceState.unavailable);
      expect(recognizer.listenCalls, 0);
      expect(assistant.errorMessage, contains('Microphone access'));
      expect(assistant.settingsNeeded, isFalse);

      permissions.microphone = PermissionOutcome.permanentlyDenied;
      await assistant.startListening();
      expect(assistant.settingsNeeded, isTrue);
      expect(recognizer.listenCalls, 0);
    });

    test('no recognition service on the device', () async {
      recognizer.availability = SpeechAvailability.unavailable;
      await assistant.startListening();
      expect(assistant.state, VoiceState.unavailable);
      expect(assistant.errorMessage, contains('not available on this device'));
      // Suggestions still work without the microphone.
      await assistant.submitText('hello');
      expect(assistant.response, isNotNull);
    });

    test('silence or an unrecognised utterance is not submitted', () async {
      await assistant.startListening();
      recognizer.finish();
      await _settle();
      expect(assistant.state, VoiceState.error);
      expect(assistant.response, isNull);
      expect(output.spoken, isEmpty);

      await assistant.startListening(); // retry
      recognizer.fail(SpeechErrorKind.noMatch);
      expect(assistant.state, VoiceState.error);
      expect(assistant.errorMessage, contains("didn't catch that"));

      await assistant.startListening();
      recognizer.fail(SpeechErrorKind.timeout);
      expect(assistant.errorMessage, contains("didn't hear anything"));
      expect(output.spoken, isEmpty);
    });

    test('tapping the mic again stops and uses what was heard', () async {
      await assistant.toggleMic();
      recognizer.hear('hello');
      await assistant.toggleMic();
      await _settle();
      expect(assistant.response!.text, startsWith('Hi!'));
    });

    test('cancel discards what was heard', () async {
      await assistant.startListening();
      recognizer.hear('pause workout');
      await assistant.cancelListening();
      recognizer.hear('pause workout', isFinal: true); // late callback
      await _settle();
      expect(assistant.state, VoiceState.idle);
      expect(assistant.response, isNull);
      expect(recognizer.cancelCalls, 1);
    });

    test('pause and resume by voice drive the session', () async {
      session.start(_request, SessionMode.camera);
      await assistant.submitText('pause workout');
      expect(session.status, SessionStatus.paused);
      await assistant.submitText('resume');
      expect(session.status, SessionStatus.active);
    });

    test('stop by voice asks first and only ends on yes', () async {
      session.start(_request, SessionMode.camera);
      await assistant.submitText('stop the session');
      expect(session.finishRequested, isFalse);
      await assistant.submitText('no, keep going');
      expect(session.finishRequested, isFalse);
      await assistant.submitText('yes');
      expect(session.finishRequested, isFalse, reason: 'the confirmation was already declined');

      await assistant.submitText('end session');
      await assistant.submitText('yes, end it');
      expect(session.finishRequested, isTrue);
    });

    test('TTS failure still shows the reply', () async {
      output.works = false;
      await assistant.submitText('hello');
      expect(assistant.state, VoiceState.idle);
      expect(assistant.response, isNotNull);
      expect(assistant.speechOutputFailed, isTrue);
    });

    test('replay speaks the same reply once more; replies never overlap', () async {
      await assistant.submitText('hello');
      await assistant.replay();
      expect(output.spoken.length, 2);
      expect(output.spoken[0], output.spoken[1]);
      expect(output.maxConcurrent, 1);
    });

    test('closing releases the microphone and ignores a pending command', () async {
      session.start(_request, SessionMode.camera);
      await assistant.startListening();
      await assistant.close();
      recognizer.hear('pause workout', isFinal: true);
      await _settle();
      expect(recognizer.cancelCalls, 1);
      expect(session.status, SessionStatus.active);
      expect(VoiceAssistantController.openAssistants, 0);
    });
  });

  group('Spoken posture cues', () {
    test('rate-limited: one warning is not repeated every frame', () async {
      final session = WorkoutSessionController()..start(_request, SessionMode.camera);
      final output = FakeSpeechOutput();
      var now = DateTime(2026, 1, 1);
      final cues = PostureCueAnnouncer(session: session, output: output, now: () => now)..attach();

      // ~3 s of continuous bad posture at 30 FPS.
      _perform(session, Motion().hold(400).moveTo(95, 900).hold(3000, torsoLean: 75));
      await _settle();
      expect(output.spoken, ['Keep your back straight — lift your chest']);

      // Routine guidance and praise are never spoken.
      now = now.add(const Duration(seconds: 30));
      _perform(session, Motion(startMs: 60000).hold(400).squat());
      await _settle();
      expect(output.spoken.length, 1);

      // A different correction after the minimum gap is spoken.
      _perform(session, Motion(startMs: 90000).hold(400).squat(depth: 125));
      await _settle();
      expect(output.spoken.last, 'Lower your hips more');
      expect(output.spoken.length, 2);
      expect(output.maxConcurrent, 1);

      // Muted, paused or detached: silent.
      cues.enabled = false;
      now = now.add(const Duration(seconds: 30));
      _perform(session, Motion(startMs: 120000).hold(400).moveTo(95, 900).hold(600, torsoLean: 75));
      await _settle();
      expect(output.spoken.length, 2);
      cues.detach();
    });

    test('stay quiet while the assistant is open', () async {
      final session = WorkoutSessionController()..start(_request, SessionMode.camera);
      final output = FakeSpeechOutput();
      final cues = PostureCueAnnouncer(session: session, output: output)..attach();
      final assistant = VoiceAssistantController(
          recognizer: FakeSpeechRecognizer(), output: output, session: session, schedule: const FakeSchedule());
      _perform(session, Motion().hold(400).moveTo(95, 900).hold(1000, torsoLean: 75));
      await _settle();
      expect(output.spoken, isEmpty);
      await assistant.close();
      cues.detach();
    });
  });
}

const cases = [
  'How many reps?',
  "How's my form?",
  'score',
  'How do I do a squat?',
  "What's next?",
  "What's my workout today?",
  'Pause workout',
  'Resume',
  'Stop session',
  'my back hurts',
  'help',
  'hello',
  'blah blah',
];

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/camera_detection.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/voice_assistant/voice_assistant_screen.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/pose_stream.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pose_fixtures.dart';
import 'support/session_fakes.dart';
import 'support/voice_fakes.dart';

const _squat = WorkoutSessionRequest(exercise: squatExercise);
const _plank = WorkoutSessionRequest(exercise: plankExercise);

/// Stands in for the camera + pose model; the test pushes frames by hand.
class FakePoseStream implements PoseStream {
  final StreamController<PoseFrame> controller = StreamController<PoseFrame>.broadcast();
  final ValueNotifier<double> rate = ValueNotifier<double>(0);
  PoseStreamException? startError;
  int starts = 0;
  int stops = 0;
  bool running = false;

  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    starts++;
    running = true;
  }

  @override
  Future<void> stop() async {
    if (running) stops++;
    running = false;
  }

  @override
  Stream<PoseFrame> get frames => controller.stream;
  @override
  Widget? buildPreview() => running ? const ColoredBox(color: Colors.black) : null;
  @override
  double get previewAspectRatio => 3 / 4;
  @override
  bool get mirrored => true;
  @override
  bool get canSwitchCamera => false;
  @override
  Future<void> switchCamera() async {}
  @override
  ValueListenable<double> get fps => rate;
  @override
  double? get averageFps => 20;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390x844 logical @3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.light(), home: screen));
  await tester.pump();
}

/// Lets navigation transitions finish without waiting on endless animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  late FakePermissions permissions;
  final session = WorkoutSessionController.instance;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync(encoding: utf8));
  });

  late FakeStore store;

  setUp(() {
    permissions = FakePermissions();
    AppPermissions.instance = permissions;
    store = FakeStore();
    session.store = store;
  });

  tearDown(() {
    AppPermissions.instance = const AppPermissions();
    session.abandon();
  });

  group('Mode selection', () {
    testWidgets('camera needs explicit consent before permission is even requested', (tester) async {
      await _pump(tester, const PostureModeSelection(request: _squat));
      expect(tester.takeException(), isNull);
      expect(find.text('Camera Detection'), findsOneWidget);
      expect(find.text('Manual Guidance'), findsOneWidget);
      expect(find.textContaining('never stored or sent', findRichText: true), findsOneWidget, reason: 'privacy notice');
      expect(tester.widget<Switch>(find.byKey(const Key('cameraConsent'))).value, isFalse);

      await _tapVisible(tester, find.text('Continue'));
      await _settle(tester);
      expect(permissions.cameraRequests, 0);
      expect(find.byType(CameraDetection), findsNothing);
      expect(find.textContaining('I agree to enable camera access'), findsWidgets);
    });

    testWidgets('permission denied: camera does not start and manual is offered', (tester) async {
      permissions.camera = PermissionOutcome.denied;
      await _pump(tester, const PostureModeSelection(request: _squat));
      await tester.tap(find.byKey(const Key('cameraConsent')));
      await tester.pump();
      await _tapVisible(tester, find.text('Continue'));
      await _settle(tester);

      expect(permissions.cameraRequests, 1);
      expect(find.byType(CameraDetection), findsNothing);
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(session.hasActiveSession, isFalse);

      await tester.tap(find.text('Use Manual Guidance'));
      await _settle(tester);
      await _tapVisible(tester, find.text('Continue'));
      await _settle(tester);
      expect(find.byType(ManualGuidance), findsOneWidget);
      expect(permissions.cameraRequests, 1);
    });

    testWidgets('manual guidance works with no camera permission at all', (tester) async {
      permissions.camera = PermissionOutcome.permanentlyDenied;
      await _pump(tester, const PostureModeSelection(request: _squat));
      await tester.tap(find.text('Manual Guidance'));
      await tester.pump();
      await _tapVisible(tester, find.text('Continue'));
      await _settle(tester);
      expect(permissions.cameraRequests, 0);
      expect(find.byType(ManualGuidance), findsOneWidget);
      expect(session.mode, SessionMode.manual);
      expect(session.exercise!.id, 'squat', reason: 'selected exercise is carried across');
    });

    testWidgets('an exercise the camera cannot follow can only use manual guidance, and says why', (tester) async {
      const calfRaise = WorkoutSessionRequest(
          exercise: SessionExercise(id: 'calf_raise', name: 'Calf Raises', group: 'legs', steps: ['Rise onto your toes'], sets: 2, reps: 12));
      await _pump(tester, const PostureModeSelection(request: calfRaise));
      expect(find.textContaining('Camera tracking is not available for Calf Raises'), findsOneWidget);
      expect(find.textContaining('too small for the camera'), findsOneWidget);
      await _tapVisible(tester, find.text('Continue'));
      await _settle(tester);
      expect(find.byType(ManualGuidance), findsOneWidget);
      expect(permissions.cameraRequests, 0);
    });

    testWidgets('a plank offers camera hold timing, labelled as basic tracking', (tester) async {
      await _pump(tester, const PostureModeSelection(request: _plank));
      expect(find.textContaining('times your hold'), findsOneWidget);
      expect(find.textContaining('Form is not scored'), findsOneWidget);
      expect(find.textContaining('Camera tracking is not available'), findsNothing);
    });

    testWidgets('skip returns to the previous screen', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const PostureModeSelection(request: _squat))),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      await _tapVisible(tester, find.text('Skip for now'));
      await _settle(tester);
      expect(find.byType(PostureModeSelection), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('Camera detection', () {
    testWidgets('counts real reps from pose frames and summarises the session', (tester) async {
      final stream = FakePoseStream();
      final output = FakeSpeechOutput();
      await _pump(tester, CameraDetection(request: _squat, poseStream: stream, speechOutput: output));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(stream.starts, 1);
      expect(find.text('Processing is done locally. No video is stored.'), findsOneWidget);
      expect(find.text('Looking for your body...'), findsOneWidget);
      expect(find.text('0'), findsWidgets);

      for (final frame in (Motion().hold(400).squat().squat()).frames) {
        stream.controller.add(frame);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.reps, 2);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Detecting posture...'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await _tapVisible(tester, find.text('Stop Session'));
      await _settle(tester);
      expect(stream.running, isFalse, reason: 'camera released');
      expect(find.byType(PostureFeedbackScreen), findsOneWidget);
      expect(find.byType(CameraDetection), findsNothing);
      expect(find.textContaining('Completed 2 reps'), findsOneWidget);
      expect(find.text('Good depth on every rep'), findsOneWidget);
      expect(find.textContaining('20.0 FPS'), findsOneWidget);
      expect(session.lastSummary!.postureScore, 100);
      await tester.pump();
      expect(store.saved.single.reps, 2);
      await tester.scrollUntilVisible(find.text('Saved to your workout history.'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pause releases the camera; resume reopens it', (tester) async {
      final stream = FakePoseStream();
      await _pump(tester, CameraDetection(request: _squat, poseStream: stream, speechOutput: FakeSpeechOutput()));
      await tester.pump();
      await _tapVisible(tester, find.text('Pause'));
      await _settle(tester);
      expect(stream.running, isFalse);
      expect(session.status, SessionStatus.paused);
      expect(find.textContaining('camera is off'), findsOneWidget);

      await _tapVisible(tester, find.text('Resume'));
      await _settle(tester);
      expect(stream.running, isTrue);
      expect(stream.starts, 2);
      expect(session.status, SessionStatus.active);

      // Leaving the screen releases the camera and drops the session.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(stream.running, isFalse);
      expect(session.hasActiveSession, isFalse);
    });

    testWidgets('a camera or model failure is shown, not hidden', (tester) async {
      final stream = FakePoseStream()
        ..startError = const PoseStreamException('model_missing', 'The pose model is not bundled with the app.');
      await _pump(tester, CameraDetection(request: _squat, poseStream: stream, speechOutput: FakeSpeechOutput()));
      await tester.pump();
      expect(find.text('The pose model is not bundled with the app.'), findsOneWidget);
      expect(find.text('Camera unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(session.reps, 0);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    });

    testWidgets('frames with no person never crash and never count', (tester) async {
      final stream = FakePoseStream();
      await _pump(tester, CameraDetection(request: _squat, poseStream: stream, speechOutput: FakeSpeechOutput()));
      await tester.pump();
      stream.controller.add(const PoseFrame(landmarks: [], timestampMs: 1));
      stream.controller.add(squatFrame(90, 2, visibility: 0.05));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(session.reps, 0);
      expect(session.postureScore, isNull);
      await _tapVisible(tester, find.text('Stop Session'));
      await _settle(tester);
      expect(find.text('Not enough data'), findsOneWidget);
    });
  });

  group('Manual guidance', () {
    testWidgets('user-confirmed sets, rest countdown, and a summary without a posture score', (tester) async {
      await _pump(tester, const ManualGuidance(request: _squat));
      expect(tester.takeException(), isNull);
      expect(find.text('Bodyweight Squat'), findsOneWidget);
      expect(find.text('LEGS'), findsOneWidget);
      expect(find.text('Stand with feet shoulder-width apart.'), findsOneWidget);
      expect(find.textContaining('Stop if you feel sharp pain'), findsOneWidget);
      expect(session.status, SessionStatus.active, reason: 'timer starts automatically');

      await _tapVisible(tester, find.text('Completed ✓'));
      await tester.pump();
      expect(session.reps, 12);
      expect(session.setsCompleted, 1);
      expect(find.textContaining('Resting'), findsOneWidget);

      // Rest (30 s) must pass before the next set can be confirmed.
      await tester.pump(const Duration(seconds: 31));
      await _tapVisible(tester, find.text('Completed ✓'));
      await tester.pump();
      expect(session.reps, 24);

      await _tapVisible(tester, find.text('Finish Session →'));
      await _settle(tester);
      expect(find.byType(PostureFeedbackScreen), findsOneWidget);
      expect(find.text('Posture not analysed'), findsOneWidget);
      expect(find.textContaining('Confirmed 24 reps'), findsOneWidget);
      expect(find.text('Posture Score'), findsNothing);
      expect(session.lastSummary!.postureScore, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pause stops the timers; too difficult is recorded', (tester) async {
      await _pump(tester, const ManualGuidance(request: _squat));
      await _tapVisible(tester, find.text('Pause'));
      await tester.pump();
      expect(session.status, SessionStatus.paused);
      expect(find.text('Paused'), findsOneWidget);
      await _tapVisible(tester, find.text('Resume'));
      await tester.pump();
      expect(session.status, SessionStatus.active);

      await _tapVisible(tester, find.text('Too Difficult'));
      await _settle(tester);
      expect(find.text('You marked this exercise as too difficult'), findsOneWidget);
      expect(session.lastSummary!.tooDifficult, isTrue);
      expect(store.flagged, ['squat'], reason: 'remembered for the next plan');
    });

    testWidgets('timed exercise counts down the hold and advances to the next exercise', (tester) async {
      await _pump(
        tester,
        const ManualGuidance(request: WorkoutSessionRequest(exercise: plankExercise, upNext: [squatExercise])),
      );
      expect(find.text('Hold 00:20'), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      expect(session.setsCompleted, 1);
      expect(find.text('Next Exercise →'), findsOneWidget);
      await _tapVisible(tester, find.text('Next Exercise →'));
      await _settle(tester);
      expect(find.text('Bodyweight Squat'), findsOneWidget);
      expect(session.exercise!.id, 'squat');
      expect(session.history.last.exercise.id, 'plank');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    });
  });

  group('Voice assistant screen', () {
    testWidgets('shows the real state at each step and the spoken reply', (tester) async {
      final recognizer = FakeSpeechRecognizer();
      final output = FakeSpeechOutput();
      final assistant = VoiceAssistantController(
          recognizer: recognizer, output: output, session: session, schedule: const FakeSchedule());
      await _pump(tester, VoiceAssistantScreen(controller: assistant));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Listening...'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(permissions.microphoneRequests, 1);

      recognizer.hear('how do I do a squat', isFinal: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Listening...'), findsNothing);
      expect(find.text('Tap the mic to speak'), findsOneWidget);
      expect(find.text('“how do I do a squat”'), findsOneWidget);
      expect(output.spoken.single, contains('Here is how to do Bodyweight Squat'));
      expect(find.byType(ActionChip).evaluate().length, lessThanOrEqualTo(3));
      expect(find.textContaining('Intent engine: On-device rules (Dialogflow unavailable)'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(recognizer.cancelCalls, 1, reason: 'microphone released on close');
    });

    testWidgets('microphone denied shows why and offers a retry', (tester) async {
      permissions.microphone = PermissionOutcome.denied;
      final recognizer = FakeSpeechRecognizer();
      final assistant = VoiceAssistantController(
          recognizer: recognizer, output: FakeSpeechOutput(), session: session, schedule: const FakeSchedule());
      await _pump(tester, VoiceAssistantScreen(controller: assistant));
      await tester.pump();
      expect(find.text('Voice input unavailable'), findsOneWidget);
      expect(find.textContaining('Microphone access is needed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Listening...'), findsNothing);
      expect(recognizer.listenCalls, 0);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    });
  });
}

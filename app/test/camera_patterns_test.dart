import 'dart:convert';
import 'dart:io';

import 'package:app/models/movement_pattern.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/camera_detection.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/voice/coach_responder.dart';
import 'package:app/services/voice/intent_service.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pattern_fixtures.dart';
import 'support/session_fakes.dart';
import 'support/voice_fakes.dart';

/// Module 5: camera tracking for every generated exercise, through movement patterns.

ExerciseFormConfig _form(MovementPattern p, [String id = 'test']) => MovementPatterns.resolve(id, p).form!;

/// Natural start and turn-around angles a little beyond the configured thresholds.
(double, double) _range(ExerciseFormConfig c) =>
    c.opening ? (c.extendedAngle - 10, c.flexedAngle + 10) : (c.extendedAngle + 10, c.flexedAngle - 10);

void main() {
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync(encoding: utf8));
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync(encoding: utf8));
  });

  group('Exercise → movement pattern mapping', () {
    test('the Dart patterns and reasons are exactly the importer\'s', () {
      final py = File('ml/exercise_catalog/movement_patterns.py').readAsStringSync();
      Set<String> pySet(String name) {
        final body = RegExp('$name = \\{([^}]*)\\}', dotAll: true).firstMatch(py)!.group(1)!;
        return RegExp("'([A-Za-z]+)'").allMatches(body).map((m) => m.group(1)!).toSet();
      }

      expect(pySet('PATTERNS'), MovementPattern.values.map((p) => p.name).toSet());
      final reasons = NoTrackingReason.values.map((r) => r.name).toSet();
      expect(reasons.containsAll(pySet('NONE_REASONS')), isTrue);
    });

    test('every catalogue exercise carries a pattern from the importer, keyed by its dataset id', () {
      for (final e in ExerciseCatalog.all) {
        expect(e.movementValue, isNotNull, reason: e.id);
        if (e.movement == MovementPattern.none) expect(e.noTrackingValue, isNotNull, reason: '${e.id} has no reason');
      }
    });

    test('dataset exercises are classified by movement, not by muscle', () {
      const expected = {
        'Barbell_Squat': MovementPattern.squat,
        'Leg_Extensions': MovementPattern.legExtension, // also quadriceps, different movement
        'Dumbbell_Bicep_Curl': MovementPattern.curl,
        'Hammer_Curls': MovementPattern.curl,
        'Barbell_Bench_Press_-_Medium_Grip': MovementPattern.benchPress,
        'Dumbbell_Shoulder_Press': MovementPattern.overheadPress,
        'Side_Lateral_Raise': MovementPattern.armRaise,
        'Bent_Over_Barbell_Row': MovementPattern.row,
        'Pullups': MovementPattern.pulldown,
        'Triceps_Pushdown': MovementPattern.tricepsPushdown,
        'Romanian_Deadlift': MovementPattern.hinge,
        'Dumbbell_Lunges': MovementPattern.lunge,
        'Lying_Leg_Curls': MovementPattern.legCurl,
        'Plank': MovementPattern.plankHold,
        'Sit-Up': MovementPattern.sitUp,
      };
      for (final MapEntry(key: id, value: p) in expected.entries) {
        expect(ExerciseCatalog.byId(id)!.movement, p, reason: id);
      }
      const untracked = {
        'Standing_Calf_Raises': NoTrackingReason.smallMovement,
        'Elliptical_Trainer': NoTrackingReason.machineCardio,
        'Straight-Arm_Pulldown': NoTrackingReason.noTracker,
        'Dumbbell_Flyes': NoTrackingReason.smallMovement,
        'Russian_Twist': NoTrackingReason.rotation,
      };
      for (final MapEntry(key: id, value: r) in untracked.entries) {
        final e = ExerciseCatalog.byId(id);
        if (e == null) continue; // not every name exists in this dataset version
        expect(e.movement, MovementPattern.none, reason: id);
        expect(e.noTrackingReason, r, reason: id);
      }
    });

    test('every curated exercise is mapped by hand: a pattern, or a stated reason', () {
      for (final e in ExerciseLibrary.all) {
        final c = MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason);
        if (c.supportsCameraTracking) {
          expect(c.form, isNotNull, reason: e.id);
        } else {
          expect(c.unsupportedReason, isNotEmpty, reason: e.id);
        }
      }
      expect(ExerciseLibrary.byId('cooldown')!.noTrackingReason, NoTrackingReason.sequence);
      expect(ExerciseLibrary.byId('hamstring_stretch_lying')!.noTrackingReason, NoTrackingReason.stretch);
    });

    test('every camera-tracked exercise has real form checks and a score; only the four tuned ones are validated', () {
      final validated = [
        for (final e in [...ExerciseLibrary.all, ...ExerciseCatalog.all])
          if (MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason).scoreValidated) e.id,
      ]..sort();
      expect(validated, ['chair_squat', 'knee_pushup', 'pushup', 'squat']);
      for (final e in [...ExerciseLibrary.all, ...ExerciseCatalog.all]) {
        final c = MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason);
        if (!c.supportsCameraTracking) continue;
        expect(c.showsPostureScore, isTrue, reason: e.id);
        expect(c.form!.checks, isNotEmpty, reason: '${e.id}: every tracked exercise runs at least one form check');
        expect(c.level, isNot(CameraSupportLevel.basicTracking), reason: e.id);
        expect(c.scoreLabel, 'Posture score', reason: 'one consistent label');
        expect(c.validationNote, c.scoreValidated ? isNull : ExercisePostureConfig.unvalidatedNote, reason: 'never called validated unless it is');
      }
    });

    test('the session request carries the pattern from Module 4', () {
      final curl = ExerciseCatalog.byId('Dumbbell_Bicep_Curl')!;
      final req = WorkoutSessionRequest.fromPlanned(PlannedExercise(exercise: curl, sets: 3, reps: 10, seconds: 0, restSeconds: 60));
      expect(req.exercise.movement, MovementPattern.curl);
      final c = MovementPatterns.forSession(req.exercise);
      expect(c.level, CameraSupportLevel.experimentalForm);
      expect(c.checkLabels, containsAll(['Upper-arm position', 'Torso stability']));
      expect(c.requiredLandmarks, containsAll([PoseIndex.leftElbow, PoseIndex.rightWrist]));
    });
  });

  group('Repetition counting for every pattern', () {
    for (final p in MovementPattern.values) {
      final c = p == MovementPattern.none ? null : MovementPatterns.resolve('test', p).form;
      if (c == null || c.kind == TrackingKind.hold) continue;
      test('${p.name}: three full cycles count three reps; a short one is not counted', () {
        final (start, turn) = _range(c);
        final engine = PostureEngine(c);
        // Overhead presses: wrists above the shoulders, as in a real press (a hanging arm is ignored by design).
        final motion = JointMotion(c, startAngle: start, baseDeg: c.ignoreLoweredArm ? -100 : 0).hold(300);
        for (var i = 0; i < 3; i++) {
          motion.moveTo(turn, 700).hold(150).moveTo(start, 700).hold(250);
        }
        // A partial movement: past the attempt threshold but not to the turn-around point.
        final halfway = c.attemptAngle + (c.opening ? 5 : -5);
        // (slow enough to be a real movement, not landmark noise: the counter ignores cycles under minRepMs)
        motion.moveTo(halfway, 900).hold(400).moveTo(start, 900).hold(250);
        PostureAnalysis? last;
        for (final f in motion.frames) {
          last = engine.process(f);
        }
        expect(engine.reps, 3, reason: '${p.name} start=$start turn=$turn');
        expect(engine.partialReps, 1, reason: p.name);
        // Score = acceptable reps ÷ attempts (the same formula as the validated four); the short attempt counts against it.
        expect(last!.postureScore, isNotNull, reason: p.name);
        expect(last.postureScore!, lessThanOrEqualTo(75), reason: '${p.name}: 4 attempts, at most 3 acceptable');
        final report = engine.buildReport(movement: p.measures);
        expect(report.postureScore, last.postureScore);
        expect(report.feedback.first.id, 'not_validated');
        expect(report.feedback.first.text, contains("hasn't been validated"));
        expect(report.feedback.any((f) => f.id == 'depth' && f.verdict == FeedbackVerdict.failed), isTrue,
            reason: 'the short attempt is reported as incomplete range');
      });
    }

    test('an opening movement does not count a rep when the person simply starts at the peak', () {
      final c = _form(MovementPattern.overheadPress);
      final engine = PostureEngine(c);
      for (final f in JointMotion(c, startAngle: 170).hold(2000).frames) {
        engine.process(f);
      }
      expect(engine.reps, 0);
    });

    test('one arm curling while the other hangs still counts (furthest limb drives the count)', () {
      final c = _form(MovementPattern.curl);
      final engine = PostureEngine(c);
      var t = 0;
      PoseFrame frame(double working) {
        t += 33;
        final f = jointFrame(c, working, t);
        // the other arm stays straight
        final straight = jointFrame(c, 170, t);
        final points = [...f.landmarks];
        for (final i in [c.rightPrimary.a, c.rightPrimary.vertex, c.rightPrimary.c]) {
          points[i] = straight.landmarks[i];
        }
        return PoseFrame(landmarks: points, timestampMs: t);
      }

      for (var rep = 0; rep < 2; rep++) {
        for (var a = 165.0; a >= 55; a -= 4) {
          engine.process(frame(a));
        }
        for (var a = 55.0; a <= 165; a += 4) {
          engine.process(frame(a));
        }
        for (var i = 0; i < 8; i++) {
          engine.process(frame(165));
        }
      }
      expect(engine.reps, 2);
    });

    test('the tested squat configuration is unchanged by the pattern layer', () {
      expect(MovementPatterns.resolve('squat', MovementPattern.squat).form, same(ExerciseFormRules.forExercise('squat')));
      expect(MovementPatterns.resolve('squat', MovementPattern.squat).form!.scored, isTrue);
    });
  });

  group('Static holds', () {
    test('plank: only time in position counts, glitches do not stop the clock, standing up does', () {
      final c = _form(MovementPattern.plankHold, 'plank');
      final engine = PostureEngine(c);
      var t = 0;
      void run(int ms, double line, {double base = 90, bool noPose = false}) {
        for (var i = 0; i < ms ~/ 33; i++) {
          t += 33;
          engine.process(noPose ? PoseFrame(landmarks: const [], timestampMs: t) : jointFrame(c, line, t, baseDeg: base));
        }
      }

      run(1000, 176, base: 0); // standing tall: straight line but upright, not a plank
      expect(engine.holdSeconds, 0);
      run(5000, 176); // plank
      run(66, 120); // two noisy frames
      run(3000, 176);
      final held = engine.holdSeconds!;
      expect(held, inInclusiveRange(7, 8));
      run(3000, 140); // hips sag: out of position
      expect(engine.holdSeconds, held, reason: 'sagging does not add time');
      run(2000, 176, noPose: true); // walked out of frame
      expect(engine.holdSeconds, held);

      final report = engine.buildReport(targetSeconds: 40);
      expect(report.reps, 0);
      expect(report.postureScore, isNotNull, reason: 'share of the hold in a correct position');
      expect(report.postureScore!, lessThan(100), reason: 'the sagging part counts against it');
      expect(report.holdSeconds, held);
      final item = report.feedback.firstWhere((f) => f.id == 'hold');
      expect(item.verdict, FeedbackVerdict.failed);
      expect(item.text, contains('of the planned 40 s'));
    });

    test('wall sit: knees bent with an upright back is in position; standing is not', () {
      final c = _form(MovementPattern.wallSitHold, 'wall_sit');
      final engine = PostureEngine(c);
      for (final f in JointMotion(c, startAngle: 170).hold(1500).frames) {
        engine.process(f);
      }
      expect(engine.holdSeconds, 0);
      for (final f in JointMotion(c, startAngle: 95, startMs: 2000).hold(4000).frames) {
        engine.process(f);
      }
      expect(engine.holdSeconds, inInclusiveRange(3, 4));
    });

    test('a knee-supported side plank measures the line to the knee', () {
      final c = _form(MovementPattern.plankHold, 'side_plank_knee');
      expect(c.leftPrimary.c, PoseIndex.leftKnee);
    });
  });

  group('Camera positioning guidance', () {
    test('missing landmarks are named', () {
      final squat = _form(MovementPattern.squat, 'Barbell_Squat');
      final hidden = {PoseIndex.leftKnee, PoseIndex.rightKnee, PoseIndex.leftAnkle, PoseIndex.rightAnkle};
      final a = PostureEngine(squat).process(jointFrame(squat, 170, 33, hidden: hidden));
      expect(a.anglesCalculated, isFalse);
      expect(a.feedback.message, startsWith("Can't see your knees and ankles"));

      final curl = _form(MovementPattern.curl, 'Dumbbell_Bicep_Curl');
      final b = PostureEngine(curl).process(jointFrame(curl, 160, 33, hidden: {PoseIndex.leftWrist, PoseIndex.rightWrist}));
      expect(b.feedback.message, contains('wrists'));
    });

    test('no person in the frame', () {
      final a = PostureEngine(_form(MovementPattern.row)).process(const PoseFrame(landmarks: [], timestampMs: 1));
      expect(a.landmarksDetected, isFalse);
      expect(a.feedback.message, contains('Step into the frame'));
    });
  });

  group('Voice coach during basic tracking (Module 6)', () {
    final intents = RuleBasedIntentService();

    test('form and score questions never claim a form verdict; reps and hold time are reported', () async {
      final session = WorkoutSessionController();
      final coach = CoachResponder(session: session, schedule: const FakeSchedule());
      Future<String> ask(String q) async => (await coach.respond(await intents.detect(q))).text;

      final curl = SessionExercise.fromPlanned(
          PlannedExercise(exercise: ExerciseCatalog.byId('Sit-Up')!, sets: 2, reps: 10, seconds: 0, restSeconds: 60));
      final c = MovementPatterns.forSession(curl);
      expect(c.level, CameraSupportLevel.experimentalForm);
      session.start(WorkoutSessionRequest(exercise: curl), SessionMode.camera,
          formScored: c.scoreValidated, formChecked: c.supportsFormEvaluation);
      final engine = PostureEngine(c.form!);
      final m = JointMotion(c.form!, startAngle: 125).hold(300).moveTo(70, 700).hold(150).moveTo(125, 700).hold(250);
      for (final f in m.frames) {
        session.updatePosture(engine.process(f), angleLabel: c.form!.primaryJoint);
      }
      expect(await ask('How many reps?'), contains('1 rep'));
      expect(await ask('Check my form'), isNot(contains('Experimental')));
      final score = await ask("What's my posture score?");
      expect(score, contains('percent'));
      expect(score, contains("hasn't been validated"), reason: 'the coach still says so, briefly');
      expect(score, isNot(contains('validated on real users. It is')));

      final plank = SessionExercise.fromPlanned(
          PlannedExercise(exercise: ExerciseLibrary.byId('plank')!, sets: 2, reps: 0, seconds: 20, restSeconds: 30));
      final h = MovementPatterns.forSession(plank);
      session.start(WorkoutSessionRequest(exercise: plank), SessionMode.camera, formScored: false, formChecked: true);
      final holdEngine = PostureEngine(h.form!);
      for (final f in JointMotion(h.form!, startAngle: 176, baseDeg: 90).hold(4000).frames) {
        session.updatePosture(holdEngine.process(f), angleLabel: h.form!.primaryJoint);
      }
      expect(await ask('How many reps?'), allOf(contains("You've held the position for"), contains('of the planned 40')));
    });
  });

  group('Screens', () {
    late FakePermissions permissions;
    late FakeStore store;
    final session = WorkoutSessionController.instance;

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

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: ThemeData.light(), home: screen));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    SessionExercise planned(String datasetId, {int sets = 2, int reps = 10}) => SessionExercise.fromPlanned(PlannedExercise(
        exercise: ExerciseCatalog.byId(datasetId)!, sets: sets, reps: reps, seconds: 0, restSeconds: 60));

    testWidgets('a dataset exercise can now choose Camera Detection, labelled as experimental form feedback', (tester) async {
      final curl = planned('Dumbbell_Bicep_Curl');
      await pump(tester, PostureModeSelection(request: WorkoutSessionRequest(exercise: curl)));
      expect(find.text('Track posture using live camera for real-time adjustments and analysis.'), findsOneWidget,
          reason: 'the same description as the validated exercises');
      expect(find.textContaining('xperimental'), findsNothing);
      expect(find.textContaining('Camera tracking is not available'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('cameraConsent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cameraConsent')));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(permissions.cameraRequests, 1);
      expect(find.byType(CameraDetection), findsOneWidget);
      expect(session.mode, SessionMode.camera);
    });

    testWidgets('experimental evaluation counts curls, shows a labelled posture score and saves it', (tester) async {
      final curl = planned('Dumbbell_Bicep_Curl');
      final stream = ScriptedPoseStream();
      await pump(tester, CameraDetection(request: WorkoutSessionRequest(exercise: curl), poseStream: stream, speechOutput: FakeSpeechOutput()));
      await tester.pump();
      expect(find.textContaining('xperimental'), findsNothing, reason: 'no prominent experimental label');
      expect(find.text('Posture score'), findsOneWidget);
      expect(find.text('Too shallow'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('validation-note')));
      expect(find.text(ExercisePostureConfig.unvalidatedNote), findsOneWidget, reason: 'subtle note instead');

      final c = MovementPatterns.forSession(curl).form!;
      final m = JointMotion(c, startAngle: 165).hold(300);
      for (var i = 0; i < 4; i++) {
        m.moveTo(60, 700).hold(150).moveTo(165, 700).hold(250);
      }
      for (final f in m.frames) {
        stream.controller.add(f);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.reps, 4);
      expect(find.text('4'), findsWidgets, reason: 'reps badge, as for the validated exercises');
      // (this simple joint fixture has no realistic torso, so the score value itself is checked in posture_evaluation_test)
      expect(session.postureScore, isNotNull);
      expect(find.text('${session.postureScore}%'), findsOneWidget, reason: 'the live score is shown');

      await tester.ensureVisible(find.text('Stop Session'));
      await tester.tap(find.text('Stop Session'));
      await settle(tester);
      expect(find.byType(PostureFeedbackScreen), findsOneWidget);
      expect(find.text('Posture Score'), findsOneWidget);
      expect(find.byKey(const ValueKey('validation-note')), findsOneWidget);
      expect(session.lastSummary!.postureScore, isNotNull);
      expect(store.saved.single.postureScore, session.lastSummary!.postureScore);
      expect(session.lastSummary!.formScored, isFalse, reason: 'not a validated score');
      expect(session.lastSummary!.formChecked, isTrue);
      await tester.pump();
      expect(store.saved.single.reps, 4);
      expect(store.saved.single.mode, SessionMode.camera);
    });

    testWidgets('a plank in camera mode times the hold and saves it', (tester) async {
      final plank = SessionExercise.fromPlanned(
          PlannedExercise(exercise: ExerciseLibrary.byId('plank')!, sets: 2, reps: 0, seconds: 20, restSeconds: 30));
      final stream = ScriptedPoseStream();
      await pump(tester, CameraDetection(request: WorkoutSessionRequest(exercise: plank), poseStream: stream, speechOutput: FakeSpeechOutput()));
      await tester.pump();
      expect(find.text('HOLD'), findsOneWidget);
      expect(find.text('In position'), findsOneWidget);
      final c = MovementPatterns.forSession(plank).form!;
      for (final f in JointMotion(c, startAngle: 176, baseDeg: 90).hold(6000).frames) {
        stream.controller.add(f);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.holdSeconds, inInclusiveRange(5, 6));

      await tester.ensureVisible(find.text('Stop Session'));
      await tester.tap(find.text('Stop Session'));
      await settle(tester);
      expect(find.text('Held'), findsOneWidget);
      expect(session.lastSummary!.holdSeconds, inInclusiveRange(5, 6));
      await tester.pump();
      expect(store.saved.single.feedback.map((f) => f.text).join(' '), contains('of the planned 40 s'));
    });

    testWidgets('an exercise the camera cannot follow explains why and keeps Manual Guidance', (tester) async {
      final calf = planned('Standing_Calf_Raises');
      await pump(tester, PostureModeSelection(request: WorkoutSessionRequest(exercise: calf)));
      expect(find.textContaining('Camera tracking is not available for ${calf.name}'), findsOneWidget);
      expect(find.textContaining('too small for the camera'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(permissions.cameraRequests, 0);
      expect(session.mode, SessionMode.manual);
    });

    testWidgets('camera permission refused: the camera does not start for a basic-tracking exercise either', (tester) async {
      permissions.camera = PermissionOutcome.denied;
      await pump(tester, PostureModeSelection(request: WorkoutSessionRequest(exercise: planned('Barbell_Squat'))));
      await tester.ensureVisible(find.byKey(const Key('cameraConsent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cameraConsent')));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.byType(CameraDetection), findsNothing);
      expect(find.text('Camera access needed'), findsOneWidget);
    });
  });
}

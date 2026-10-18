// Automated FUNCTIONAL test cases for Modules 4, 5 and 6 (report section 5.2): real screens in a headless widget tree.
// IDs: ATC-M4-F03.., ATC-M5-F01.., ATC-M6-F01..   Run: flutter test test/atc/atc_m456_functional_test.dart
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/camera_detection.dart';
import 'package:app/screens/posture_detection/exercise_picker.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_home.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/voice_assistant/voice_assistant_screen.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/screens/workout_and_exercise/workout_plan.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_session/plan_progress.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide same;

import '../support/pattern_fixtures.dart';
import '../support/pose_fixtures.dart';
import '../support/session_fakes.dart';
import '../support/voice_fakes.dart';
import 'atc_helper.dart';

HealthProfile _p({List<String> conditions = const [], int freq = 6}) => HealthProfile(
    fullName: 'Test User', dob: '1996-04-04', gender: 'Female', heightValue: 168, weightValue: 64, medicalConditions: conditions,
    primaryGoal: 'Maintain & Stay Fit', activityLevel: 'Moderately Active', workoutFrequency: freq);

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: w));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

int _n(Finder f) => f.evaluate().length;

void main() {
  late FakePermissions permissions;
  late FakeStore store;
  final session = WorkoutSessionController.instance;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
  });
  setUp(() {
    permissions = FakePermissions();
    AppPermissions.instance = permissions;
    store = FakeStore();
    session.store = store;
  });
  tearDown(() {
    AppPermissions.instance = const AppPermissions();
    session.abandon();
    UserSession.instance.clear();
    UserSession.instance.loading = false;
    PlanProgress.instance.reset();
  });

  Future<void> signIn(WidgetTester t, {List<String> conditions = const []}) async {
    UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
    await t.runAsync(() => UserSession.instance.setProfile(_p(conditions: conditions)));
  }

  // ================================================================ Module 4
  group('Functional Testing: Module 4 workout plan and exercise detail', () {
    atcWidget('ATC-M4-F03', req: 'M4-FR6', objective: 'Exercise detail shows the prescribed dose and a start/end illustration',
        input: 'Planned "Jumping Jacks": 2 sets of 30 s, rest 40 s', expected: 'Sets, per-set time and rest shown; illustration caption shown',
        run: (t) async {
          final pe = PlannedExercise(exercise: ExerciseLibrary.byId('jumping_jacks')!, sets: 2, reps: 0, seconds: 30, restSeconds: 40);
          await _pump(t, ExerciseDetail(planned: pe));
          final ok = _n(find.text('Sets')) == 1 && _n(find.text('30s')) == 1 && _n(find.text('40s')) == 1 &&
              _n(find.textContaining('Illustration of the start and end position')) == 1;
          return check(ok, 'Sets ${_n(find.text('Sets'))}; "30s" ${_n(find.text('30s'))}; rest "40s" ${_n(find.text('40s'))}; '
              'illustration caption ${_n(find.textContaining('Illustration of the start and end position'))}');
        });
    atcWidget('ATC-M4-F04', req: 'M4-FR6', objective: 'A dataset exercise shows its photos with the source caption',
        input: 'Planned "Dumbbell Bicep Curl": 3 × 10', expected: 'Caption "Photos: free-exercise-db (public domain)…"; technique steps listed',
        run: (t) async {
          final pe = PlannedExercise(exercise: ExerciseCatalog.byId('Dumbbell_Bicep_Curl')!, sets: 3, reps: 10, seconds: 0, restSeconds: 60);
          await _pump(t, ExerciseDetail(planned: pe));
          final cap = _n(find.textContaining('Photos: free-exercise-db (public domain)'));
          return check(cap == 1 && _n(find.text('Technique')) == 1, 'Photo caption $cap; Technique heading ${_n(find.text('Technique'))}');
        });
    atcWidget('ATC-M4-F05', req: 'M4-SFR4', objective: '"Start exercise" opens mode selection linked to the planned exercise',
        input: 'Generated plan, Monday, 4th exercise', expected: 'Mode selection opens with plan link (Monday, entry 3)', run: (t) async {
          await signIn(t);
          final day = UserSession.instance.plan!.week[0]!;
          await _pump(t, ExerciseDetail(planned: day.exercises[3], queue: day.exercises, weekday: 0));
          await t.tap(find.text('Start exercise'));
          await t.pumpAndSettle();
          final m = t.widget<PostureModeSelection>(find.byType(PostureModeSelection));
          return check(m.request.plan?.weekday == 0 && m.request.plan?.entryIndex == 3 && m.request.exercise.id == day.exercises[3].exercise.id,
              'Opened ${m.request.exercise.name}; plan day ${m.request.plan?.weekday}; entry ${m.request.plan?.entryIndex}');
        });
    atcWidget('ATC-M4-F06', req: 'M4-FR2', objective: 'The workout tab shows the training profile of the health classification',
        input: 'Profile with "Heart Disease", doctor\'s clearance given', expected: '"Your training profile: Cardiac" with "Highest intensity scheduled: Moderate"',
        run: (t) async {
          await signIn(t, conditions: ['Heart Disease']);
          await _pump(t, const WorkoutPlan());
          final card = find.byKey(const ValueKey('training-profile'));
          await t.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
          final a = _n(find.text('Your training profile: Cardiac')), b = _n(find.textContaining('Highest intensity scheduled: Moderate'));
          return check(a == 1 && b == 1, 'Profile title $a; intensity line $b');
        });
  });

  // ================================================================ Module 5
  group('Functional Testing: Module 5 posture detection screens', () {
    atcWidget('ATC-M5-F01', req: 'M5-SFR3', objective: 'Posture Detection offers Today\'s workout, My plan and the Exercise library',
        input: 'Signed-in user with a 6-day plan', expected: 'Three tabs', run: (t) async {
          await signIn(t);
          await _pump(t, const PostureDetectionHome());
          final n = ['tab-today', 'tab-plan', 'tab-library'].where((k) => _n(find.byKey(ValueKey(k))) == 1).length;
          return check(n == 3, '$n of 3 tabs present');
        });
    atcWidget('ATC-M5-F02', req: 'M5-SFR3', objective: 'Without a plan an empty state is shown, not invented exercises', input: 'No health profile',
        expected: '"No personalised plan yet" and "Create my health profile"', run: (t) async {
          await _pump(t, const PostureDetectionHome());
          return check(_n(find.text('No personalised plan yet')) == 1 && _n(find.text('Create my health profile')) == 1,
              'Empty state ${_n(find.text('No personalised plan yet'))}; button ${_n(find.text('Create my health profile'))}');
        });
    atcWidget('ATC-M5-F03', req: 'M5-SFR3', objective: 'My plan lists the real plan day with camera capability and starts an entry with its plan link',
        input: 'Tab "My plan", Monday, 3rd exercise', expected: 'Entry and capability shown; mode selection receives exercise, sets and plan link',
        run: (t) async {
          await signIn(t);
          final day = UserSession.instance.plan!.week[0]!;
          await _pump(t, const PostureDetectionHome());
          await t.tap(find.byKey(const ValueKey('tab-plan')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('day-0')));
          await t.pumpAndSettle();
          final cap = _n(find.byKey(const ValueKey('capability-0-2')));
          await t.tap(find.byKey(const ValueKey('entry-0-2')));
          await t.pumpAndSettle();
          final m = t.widget<PostureModeSelection>(find.byType(PostureModeSelection));
          final ok = cap == 1 && m.request.exercise.id == day.exercises[2].exercise.id && m.request.exercise.sets == day.exercises[2].sets && m.request.plan?.entryIndex == 2;
          return check(ok, 'Capability label $cap; opened ${m.request.exercise.name} (${m.request.exercise.sets} sets), plan entry ${m.request.plan?.entryIndex}');
        });
    atcWidget('ATC-M5-F04', req: 'M5-SFR3', objective: 'The generic exercise library is kept with camera and manual sections', input: 'Tab "Exercise library"',
        expected: 'Note that it is not the personalised plan; "Camera posture detection" and "Manual guidance" sections', run: (t) async {
          await _pump(t, const PostureDetectionHome(initialTab: 2));
          await t.pumpAndSettle();
          final note = _n(find.textContaining('not your personalised plan')), cam = _n(find.text('Camera posture detection'));
          await t.scrollUntilVisible(find.text('Manual guidance'), 400,
              scrollable: find.descendant(of: find.byType(ExerciseLibraryList), matching: find.byType(Scrollable)).first);
          final man = _n(find.text('Manual guidance'));
          return check(note == 1 && cam == 1 && man == 1, 'Generic-library note $note; camera section $cam; manual section $man');
        });
    atcWidget('ATC-M5-F05', req: 'M5-FR15.3', objective: 'Camera permission is not requested before the consent toggle is on',
        input: 'Bodyweight Squat; Continue tapped with consent off', expected: 'Both modes shown; 0 permission requests; consent prompt shown', run: (t) async {
          await _pump(t, const PostureModeSelection(request: WorkoutSessionRequest(exercise: squatExercise)));
          final modes = _n(find.text('Camera Detection')) + _n(find.text('Manual Guidance'));
          await _tap(t, find.text('Continue'));
          await _settle(t);
          return check(modes == 2 && permissions.cameraRequests == 0 && _n(find.byType(CameraDetection)) == 0,
              'Mode options $modes; camera requests ${permissions.cameraRequests}; camera screen opened ${_n(find.byType(CameraDetection))}');
        });
    atcWidget('ATC-M5-F06', req: 'M5-FR15.4', objective: '"Skip for now" returns to the previous screen', input: 'Mode selection opened from a screen; tap "Skip for now"',
        expected: 'Mode selection closed', run: (t) async {
          await _pump(t, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const PostureModeSelection(request: WorkoutSessionRequest(exercise: squatExercise)))), child: const Text('open')))));
          await t.tap(find.text('open'));
          await _settle(t);
          await _tap(t, find.text('Skip for now'));
          await _settle(t);
          return check(_n(find.byType(PostureModeSelection)) == 0 && _n(find.text('open')) == 1, 'Mode selection still open: ${_n(find.byType(PostureModeSelection))}');
        });
    atcWidget('ATC-M5-F07', req: 'M5-FR15.1', objective: 'Refused camera permission keeps the camera off and offers Manual Guidance',
        input: 'Consent on; camera permission denied', expected: '"Camera access needed" and "Use Manual Guidance"; camera screen not opened', run: (t) async {
          permissions.camera = PermissionOutcome.denied;
          await _pump(t, const PostureModeSelection(request: WorkoutSessionRequest(exercise: squatExercise)));
          await _tap(t, find.byKey(const Key('cameraConsent')));
          await t.pump();
          await _tap(t, find.text('Continue'));
          await _settle(t);
          return check(_n(find.text('Camera access needed')) == 1 && _n(find.text('Use Manual Guidance')) == 1 && _n(find.byType(CameraDetection)) == 0,
              'Dialog ${_n(find.text('Camera access needed'))}; manual offered ${_n(find.text('Use Manual Guidance'))}; camera screen ${_n(find.byType(CameraDetection))}');
        });
    atcWidget('ATC-M5-F08', req: 'M5-FR16.3', objective: 'Camera screen counts reps from pose frames and shows status and privacy notice',
        input: '2 squats fed as pose frames', expected: 'Reps 2; "Landmarks detected", "Angles calculated"; local-processing notice', run: (t) async {
          final stream = ScriptedPoseStream();
          await _pump(t, CameraDetection(request: const WorkoutSessionRequest(exercise: squatExercise), poseStream: stream, speechOutput: FakeSpeechOutput()));
          for (final f in (Motion().hold(400).squat().squat()).frames) {
            stream.controller.add(f);
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          final ok = session.reps == 2 && _n(find.text('Landmarks detected')) == 1 && _n(find.text('Angles calculated')) == 1 &&
              _n(find.text('Processing is done locally. No video is stored.')) == 1;
          return check(ok, 'Reps ${session.reps}; status chips ${_n(find.text('Landmarks detected'))}/${_n(find.text('Angles calculated'))}; notice ${_n(find.text('Processing is done locally. No video is stored.'))}');
        });
    atcWidget('ATC-M5-F09', req: 'M5-FR16.5', objective: '"Stop Session" ends the session and shows the summary with score, stats and feedback',
        input: '2 good squats, then Stop Session', expected: 'Summary: "Session Complete!", posture score 100%, Total Reps, Accuracy, form feedback; session saved',
        run: (t) async {
          final stream = ScriptedPoseStream();
          await _pump(t, CameraDetection(request: const WorkoutSessionRequest(exercise: squatExercise), poseStream: stream, speechOutput: FakeSpeechOutput()));
          for (final f in (Motion().hold(400).squat().squat()).frames) {
            stream.controller.add(f);
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          await _tap(t, find.text('Stop Session'));
          await _settle(t);
          await t.pump();
          final ok = _n(find.byType(PostureFeedbackScreen)) == 1 && _n(find.textContaining('Session Complete')) == 1 && session.lastSummary?.postureScore == 100 &&
              _n(find.text('Total Reps')) == 1 && _n(find.text('Accuracy')) == 1 && _n(find.text('Good depth on every rep')) == 1 && store.saved.length == 1;
          return check(ok, 'Summary ${_n(find.byType(PostureFeedbackScreen))}; score ${session.lastSummary?.postureScore}%; '
              'stats ${_n(find.text('Total Reps'))}/${_n(find.text('Accuracy'))}; feedback ${_n(find.text('Good depth on every rep'))}; saved ${store.saved.length}');
        });
    atcWidget('ATC-M5-F10', req: 'M5-FR17.2', objective: 'Manual guidance: confirmed sets add reps; the form checklist and response buttons are shown',
        input: 'Bodyweight Squat 3 × 12; tap "Completed ✓" once', expected: '12 reps, 1 set; checklist step and Skip / Too Difficult buttons present',
        run: (t) async {
          await _pump(t, const ManualGuidance(request: WorkoutSessionRequest(exercise: squatExercise)));
          final steps = _n(find.text('Stand with feet shoulder-width apart.'));
          await _tap(t, find.text('Completed ✓'));
          await t.pump();
          final ok = session.reps == 12 && session.setsCompleted == 1 && steps == 1 && _n(find.text('Too Difficult')) == 1 && _n(find.text('Skip')) >= 1;
          final msg = 'Reps ${session.reps}; sets ${session.setsCompleted}; checklist step $steps; Too Difficult ${_n(find.text('Too Difficult'))}; Skip ${_n(find.text('Skip'))}';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
    atcWidget('ATC-M5-F11', req: 'M5-FR17.5', objective: '"Next Exercise" advances to the following exercise', input: 'Plank 1 × 20 s then Squat; hold finished',
        expected: 'Next exercise is Bodyweight Squat; plank saved in history', run: (t) async {
          await _pump(t, const ManualGuidance(request: WorkoutSessionRequest(exercise: plankExercise, upNext: [squatExercise])));
          await t.pump(const Duration(seconds: 21));
          await _tap(t, find.text('Next Exercise →'));
          await _settle(t);
          final ok = session.exercise?.id == 'squat' && session.history.last.exercise.id == 'plank';
          final msg = 'Current exercise ${session.exercise?.id}; last finished ${session.history.last.exercise.id}';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
    atcWidget('ATC-M5-F12', req: 'M5-SFR2', objective: 'A plank in camera mode shows a hold timer instead of a rep counter', input: 'Plank 2 × 20 s; 6 s in position',
        expected: '"HOLD" badge and "In position"; about 5–6 s held', run: (t) async {
          final plank = SessionExercise.fromPlanned(PlannedExercise(exercise: ExerciseLibrary.byId('plank')!, sets: 2, reps: 0, seconds: 20, restSeconds: 30));
          final stream = ScriptedPoseStream();
          await _pump(t, CameraDetection(request: WorkoutSessionRequest(exercise: plank), poseStream: stream, speechOutput: FakeSpeechOutput()));
          await t.pump();
          final badge = _n(find.text('HOLD')), inPos = _n(find.text('In position'));
          final cfg = MovementPatterns.forSession(plank).form!;
          for (final f in JointMotion(cfg, startAngle: 176, baseDeg: 90).hold(6000).frames) {
            stream.controller.add(f);
          }
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          final held = session.holdSeconds ?? 0;
          return check(badge == 1 && inPos == 1 && held >= 5 && held <= 6, 'HOLD badge $badge; "In position" $inPos; held $held s');
        });
    atcWidget('ATC-M5-F13', req: 'M5-FR15.1', objective: 'An exercise the camera cannot follow explains why and keeps Manual Guidance',
        input: 'Calf Raises', expected: 'Camera not available with the reason; Continue opens Manual Guidance', run: (t) async {
          await _pump(t, const PostureModeSelection(request: WorkoutSessionRequest(exercise: SessionExercise(id: 'calf_raise', name: 'Calf Raises', group: 'legs', steps: ['Rise onto your toes'], sets: 2, reps: 12))));
          final why = _n(find.textContaining('too small for the camera'));
          await _tap(t, find.text('Continue'));
          await _settle(t);
          final ok = why == 1 && session.mode == SessionMode.manual && permissions.cameraRequests == 0;
          final msg = 'Reason shown $why; session mode ${session.mode?.name}; camera requests ${permissions.cameraRequests}';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
  });

  // ================================================================ Module 6
  group('Functional Testing: Module 6 voice assistant screen', () {
    atcWidget('ATC-M6-F01', req: 'M6-FR19.1', objective: 'Opening the assistant asks for the microphone and shows the listening state',
        input: 'Voice assistant opened', expected: '"Listening..." and "Cancel"; 1 microphone request', run: (t) async {
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), session: session, schedule: const FakeSchedule());
          await _pump(t, VoiceAssistantScreen(controller: a));
          await t.pump();
          final ok = _n(find.text('Listening...')) == 1 && _n(find.text('Cancel')) == 1 && permissions.microphoneRequests == 1;
          final msg = 'Listening ${_n(find.text('Listening...'))}; Cancel ${_n(find.text('Cancel'))}; microphone requests ${permissions.microphoneRequests}';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
    atcWidget('ATC-M6-F02', req: 'M6-FR19.3', objective: 'A spoken question shows the transcript, the reply card, at most three chips and is spoken aloud',
        input: 'Recognised speech "how do I do a squat" (simulated recogniser)', expected: 'Transcript shown; reply about Bodyweight Squat spoken; ≤ 3 chips', run: (t) async {
          final rec = FakeSpeechRecognizer(), out = FakeSpeechOutput();
          final a = VoiceAssistantController(recognizer: rec, output: out, session: session, schedule: const FakeSchedule());
          await _pump(t, VoiceAssistantScreen(controller: a));
          await t.pump();
          rec.hear('how do I do a squat', isFinal: true);
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          final chips = _n(find.byType(ActionChip));
          final ok = _n(find.text('“how do I do a squat”')) == 1 && out.spoken.length == 1 && out.spoken.single.contains('Bodyweight Squat') && chips <= 3;
          final msg = 'Transcript ${_n(find.text('“how do I do a squat”'))}; spoken "${out.spoken.isEmpty ? '' : out.spoken.single.split('.').first}"; chips $chips';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
    atcWidget('ATC-M6-F03', req: 'M6-FR19.2', objective: 'A refused microphone is explained and a retry is offered', input: 'Microphone permission denied',
        expected: '"Voice input unavailable", the reason and "Try again"; not listening', run: (t) async {
          permissions.microphone = PermissionOutcome.denied;
          final rec = FakeSpeechRecognizer();
          final a = VoiceAssistantController(recognizer: rec, output: FakeSpeechOutput(), session: session, schedule: const FakeSchedule());
          await _pump(t, VoiceAssistantScreen(controller: a));
          await t.pump();
          final ok = _n(find.text('Voice input unavailable')) == 1 && _n(find.textContaining('Microphone access is needed')) == 1 && _n(find.text('Try again')) == 1 && rec.listenCalls == 0;
          final msg = 'Unavailable ${_n(find.text('Voice input unavailable'))}; reason ${_n(find.textContaining('Microphone access is needed'))}; retry ${_n(find.text('Try again'))}; listen calls ${rec.listenCalls}';
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          return check(ok, msg);
        });
    atcWidget('ATC-M6-F04', req: 'M6-FR19.4', objective: 'Leaving the assistant releases the microphone without running a command',
        input: 'Assistant listening; screen closed; a late "pause workout"', expected: 'Recognizer cancelled once; no command executed', run: (t) async {
          final rec = FakeSpeechRecognizer();
          session.start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final a = VoiceAssistantController(recognizer: rec, output: FakeSpeechOutput(), session: session, schedule: const FakeSchedule());
          await _pump(t, VoiceAssistantScreen(controller: a));
          await t.pump();
          await t.pumpWidget(const MaterialApp(home: SizedBox()));
          rec.hear('pause workout', isFinal: true);
          await t.pump();
          return check(rec.cancelCalls == 1 && session.status == SessionStatus.active, 'Cancel calls ${rec.cancelCalls}; session ${session.status.name}');
        });
  });
}

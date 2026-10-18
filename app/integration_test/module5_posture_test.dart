// Module 5 (posture detection) on the real phone: Posture Detection home, the plan-linked lists, mode selection, a real
// camera session (camera plugin + on-device MediaPipe), Stop Session and its summary, Manual Guidance and error states.
//
// These cases prove that the screens and the camera pipeline work on the device. They do NOT prove that posture is detected
// or judged correctly on a real person; that needs the separate real-person checklist (docs/chapter5/REAL_PERSON_VALIDATION.md).
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/module5_posture_test.dart -d <device-id>
import 'package:app/models/plan.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/camera_detection.dart';
import 'package:app/screens/posture_detection/exercise_picker.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_home.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/posture_detection/widgets/pose_overlay_painter.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/navigation_helpers.dart';
import 'helpers/test_app.dart';
import 'helpers/test_fixtures.dart';

/// Denies the camera without any dialog, to exercise the app's denial path (the phone's real permission is not changed).
class _DeniedCamera extends DevicePermissions {
  const _DeniedCamera();
  @override
  Future<PermissionOutcome> requestCamera() async => PermissionOutcome.denied;
}

/// A plan entry the camera counts repetitions for (validated pattern first), as (weekday, index).
(int, int) cameraRepEntry(PersonalizedPlan p) {
  (int, int)? best;
  for (var w = 0; w < 7; w++) {
    final d = p.week[w];
    if (d == null) continue;
    for (var i = 0; i < d.exercises.length; i++) {
      final c = MovementPatterns.forSession(SessionExercise.fromPlanned(d.exercises[i]));
      if (!c.supportsRepCounting) continue;
      if (c.scoreValidated) return (w, i);
      best ??= (w, i);
    }
  }
  return best!;
}

final Finder cameraRunning = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PoseOverlayPainter, description: 'live camera overlay');

Future<void> openPostureHome(WidgetTester t) async {
  await launchApp(t);
  await waitFor(t, find.text("TODAY'S WORKOUT"));
  await tapOn(t, find.byTooltip('Open menu'), what: 'the menu button');
  await tapOn(t, find.text('Posture check'), what: 'Posture check in the menu');
  await waitFor(t, find.byType(PostureDetectionHome), what: 'Posture Detection');
}

/// Opens mode selection for plan entry [w]/[i] through "My plan".
Future<void> openPlanEntry(WidgetTester t, int w, int i) async {
  await openPostureHome(t);
  await tapOn(t, find.byKey(const ValueKey('tab-plan')), what: 'My plan');
  await tapOn(t, find.byKey(ValueKey('day-$w')), what: 'plan day $w');
  final entry = find.byKey(ValueKey('entry-$w-$i'));
  await scrollTo(t, entry, within: find.byType(PostureDetectionHome));
  await tapOn(t, entry, what: 'plan entry $w-$i');
  await waitFor(t, find.byType(PostureModeSelection), what: 'mode selection');
}

void main() {
  binding;
  module5Tests();
}

void module5Tests() {
  group('Module 5 posture detection (real device)', () {
    deviceCase('ATC-DEV-M5-01', req: 'M5-SFR3', file: 'module5_posture_test.dart',
        objective: 'Posture check opens Posture Detection with Today\'s workout, My plan and the Exercise library',
        input: 'Home → menu → "Posture check"',
        expected: 'Tabs "Today\'s workout", "My plan", "Exercise library"',
        body: (t) async {
          await startControlledSession(t);
          await openPostureHome(t);
          final tabs = ["Today's workout", 'My plan', 'Exercise library'].where((x) => count(find.text(x)) == 1).toList();
          return Outcome(tabs.length == 3, 'Tabs shown: ${tabs.join(', ')}');
        });

    deviceCase('ATC-DEV-M5-02', req: 'M5-SFR3', file: 'module5_posture_test.dart',
        objective: 'Today\'s workout lists today\'s plan entries (or the rest day) from the personalised plan',
        input: 'Posture Detection → "Today\'s workout"',
        expected: 'One entry per exercise of today\'s plan day, or the rest-day message when today is a rest day',
        body: (t) async {
          await startControlledSession(t);
          final today = DateTime.now().weekday - 1;
          final day = UserSession.instance.plan!.week[today];
          await openPostureHome(t);
          if (day == null) {
            final rest = count(find.byKey(const ValueKey('rest-day')));
            return Outcome(rest == 1, 'Today (weekday $today) is a rest day in the plan; rest-day message shown $rest');
          }
          final first = find.byKey(ValueKey('entry-$today-0'));
          await waitFor(t, first);
          final last = find.byKey(ValueKey('entry-$today-${day.exercises.length - 1}'));
          await scrollTo(t, last, within: find.byType(PostureDetectionHome));
          return Outcome(count(last) == 1, 'Today ${day.name}: ${day.exercises.length} entries; first and last entry shown');
        });

    deviceCase('ATC-DEV-M5-03', req: 'M5-SFR3', file: 'module5_posture_test.dart',
        objective: 'My plan shows every day of the complete plan with each entry\'s camera capability',
        input: 'Posture Detection → "My plan" → each training day',
        expected: 'For every training day: its entries with a capability label',
        body: (t) async {
          await startControlledSession(t);
          final plan = UserSession.instance.plan!;
          await openPostureHome(t);
          await tapOn(t, find.byKey(const ValueKey('tab-plan')), what: 'My plan');
          final seen = <String>[];
          for (var w = 0; w < 7; w++) {
            final d = plan.week[w];
            if (d == null) continue;
            await tapOn(t, find.byKey(ValueKey('day-$w')), what: 'day $w');
            await waitFor(t, find.byKey(ValueKey('entry-$w-0')), what: 'first entry of day $w');
            final cap = count(find.byKey(ValueKey('capability-$w-0')));
            seen.add('${d.name}: ${d.exercises.length} entries, capability label $cap');
            if (cap != 1) return Outcome(false, seen.join('; '));
          }
          return Outcome(seen.length == plan.workoutDays, '${seen.length} training days checked. ${seen.join('; ')}');
        });

    deviceCase('ATC-DEV-M5-04', req: 'M5-SFR3', file: 'module5_posture_test.dart',
        objective: 'The generic Exercise library keeps its camera and manual sections',
        input: 'Posture Detection → "Exercise library"',
        expected: '"Camera posture detection" and "Manual guidance" sections',
        body: (t) async {
          await startControlledSession(t);
          await openPostureHome(t);
          await tapOn(t, find.byKey(const ValueKey('tab-library')), what: 'Exercise library');
          await waitFor(t, find.text('Camera posture detection'));
          await scrollTo(t, find.text('Manual guidance'), within: find.byType(PostureDetectionHome));
          return Outcome(count(find.text('Manual guidance')) == 1, 'Camera section shown; manual section shown ${count(find.text('Manual guidance'))}');
        });

    deviceCase('ATC-DEV-M5-05', req: 'M5-FR15.3', file: 'module5_posture_test.dart',
        objective: 'A planned camera exercise opens mode selection; Continue without consent does not start the camera',
        input: 'My plan → a camera-tracked planned exercise → Continue with the consent toggle off',
        expected: 'Both modes and the consent switch; the consent message; no camera screen',
        body: (t) async {
          await startControlledSession(t);
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          final modes = count(find.text('Camera Detection')) + count(find.text('Manual Guidance'));
          final consent = count(find.byKey(const Key('cameraConsent')));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.textContaining('I agree to enable camera access'), what: 'the consent message');
          return Outcome(modes == 2 && consent == 1 && count(find.byType(CameraDetection)) == 0,
              'Entry $w-$i: modes $modes, consent switch $consent, consent message shown, camera screen ${count(find.byType(CameraDetection))}');
        });

    deviceCase('ATC-DEV-M5-06', req: 'M5-FR16.5', file: 'module5_posture_test.dart',
        objective: 'With consent the real camera session starts on the phone, and Stop Session ends it with a summary',
        input: 'Planned camera exercise → consent on → Continue → about 8 s of live camera → "Stop Session"',
        expected: 'Live camera overlay running, exercise name or setup hint, privacy notice; after Stop: "Session Summary" whose reps equal the session counter; saved in memory only',
        timeout: const Duration(minutes: 3),
        body: (t) async {
          await startControlledSession(t);
          await requireCameraPermission();
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          await tapOn(t, find.byKey(const Key('cameraConsent')), what: 'the consent switch');
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.byType(CameraDetection), what: 'the camera screen');
          final failed = find.text('Try again');
          final end = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(end) && count(cameraRunning) == 0 && count(failed) == 0) {
            await t.pump(const Duration(milliseconds: 100));
          }
          if (count(cameraRunning) == 0) {
            final err = find.descendant(of: find.byType(CameraDetection), matching: find.byType(Text));
            return Outcome(false, 'Camera did not start: ${t.widgetList<Text>(err).map((x) => x.data).whereType<String>().join(' | ')}');
          }
          final session = WorkoutSessionController.instance;
          final active = session.status == SessionStatus.active;
          await pumpFor(t, const Duration(seconds: 8));
          final notice = count(find.text('Processing is done locally. No video is stored.'));
          final landmarks = session.landmarksDetected;
          final repsBefore = session.reps;
          await tapOn(t, find.text('Stop Session'));
          await waitFor(t, find.byType(PostureFeedbackScreen), what: 'the session summary');
          final s = session.lastSummary!;
          await pumpFor(t, const Duration(milliseconds: 800));
          return Outcome(active && notice == 1 && s.reps == repsBefore && sessionLog.saved.length == 1 && s.mode == SessionMode.camera,
              '${s.exercise.name}: camera running, session active $active, privacy notice $notice, landmarks seen during the 8 s: $landmarks; '
              'summary reps ${s.reps} (counter $repsBefore), score ${s.postureScore ?? 'not available'}; saved to the in-memory log ${sessionLog.saved.length}');
        });

    deviceCase('ATC-DEV-M5-07', req: 'M5-FR17.2', file: 'module5_posture_test.dart',
        objective: 'Manual Guidance shows the set counter, checklist and controls, and Pause stops the clock',
        input: 'Planned exercise → Manual Guidance → Continue → Pause → Resume',
        expected: '"Manual Guidance", "Proper Form", "Completed ✓", "Skip", "Too Difficult"; Pause switches to "Resume" and back',
        body: (t) async {
          await startControlledSession(t);
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          await tapOn(t, find.text('Manual Guidance'));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.byType(ManualGuidance), what: 'Manual Guidance');
          final shown = ['Proper Form', 'Completed ✓', 'Skip', 'Too Difficult'].where((x) => count(find.text(x)) >= 1).toList();
          await tapOn(t, find.text('Pause'));
          final paused = count(find.text('Resume'));
          await tapOn(t, find.text('Resume'));
          final resumed = count(find.text('Pause'));
          return Outcome(shown.length == 4 && paused == 1 && resumed == 1, 'Shown: ${shown.join(', ')}; Resume after Pause $paused; Pause after Resume $resumed');
        });

    deviceCase('ATC-DEV-M5-08', req: 'M5-FR15.1', file: 'module5_posture_test.dart',
        objective: 'A refused camera permission keeps the camera off and offers Manual Guidance (denial simulated in the app, no system dialog)',
        input: 'Camera permission answer "denied" (AppPermissions override); consent on → Continue → "Use Manual Guidance" → Continue',
        expected: '"Camera access needed" dialog; no camera screen; the mode switches to Manual Guidance and Continue opens it',
        body: (t) async {
          await startControlledSession(t);
          AppPermissions.instance = const _DeniedCamera();
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          await tapOn(t, find.byKey(const Key('cameraConsent')));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.text('Camera access needed'));
          final cam = count(find.byType(CameraDetection));
          await tapOn(t, find.text('Use Manual Guidance'));
          await waitGone(t, find.text('Camera access needed'), what: 'the dialog');
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.byType(ManualGuidance), what: 'Manual Guidance');
          return Outcome(cam == 0, 'Dialog shown; camera screen $cam; mode switched to Manual Guidance; Continue opened Manual Guidance');
        });

    deviceCase('ATC-DEV-M5-09', req: 'M5-FR15.1', file: 'module5_posture_test.dart',
        objective: 'An exercise the camera cannot follow says why and still offers Manual Guidance',
        input: 'Exercise library → first exercise in "Manual guidance" section',
        expected: 'Mode selection explains that camera detection is not available, with the reason; Manual Guidance available',
        body: (t) async {
          await startControlledSession(t);
          await openPostureHome(t);
          await tapOn(t, find.byKey(const ValueKey('tab-library')));
          final manualHeader = find.text('Manual guidance');
          await scrollTo(t, manualHeader, within: find.byType(PostureDetectionHome));
          final tile = find.descendant(of: find.byType(ExerciseLibraryList), matching: find.text('Manual Guidance only'));
          await scrollTo(t, tile.first, within: find.byType(PostureDetectionHome));
          await tapOn(t, tile, what: 'a Manual-Guidance-only exercise');
          await waitFor(t, find.byType(PostureModeSelection));
          final m = t.widget<PostureModeSelection>(find.byType(PostureModeSelection));
          final reason = MovementPatterns.forSession(m.request.exercise).unsupportedReason ?? '';
          final shown = reason.isNotEmpty && count(find.textContaining(reason.split('.').first)) >= 1;
          return Outcome(shown && count(find.text('Manual Guidance')) == 1,
              '${m.request.exercise.name}: reason "${reason.split('.').first}" shown $shown; Manual Guidance option ${count(find.text('Manual Guidance'))}');
        });
  });
}

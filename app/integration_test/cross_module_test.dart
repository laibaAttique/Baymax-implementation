// End-to-end flows across Modules 4, 5 and 6 on the real phone:
//   Home → Workout plan → today's exercise → Exercise Detail → Start exercise → Posture Detection (Manual Guidance) →
//   all sets → session summary → back to the plan → the planned exercise shows as done today;
//   and the voice assistant reading and controlling a running posture session.
// Sessions are kept in the in-memory log; nothing is uploaded.
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/cross_module_test.dart -d <device-id>
import 'package:app/models/plan.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/camera_detection.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/voice_assistant/voice_assistant_screen.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/workout_session/plan_progress.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/navigation_helpers.dart';
import 'helpers/test_app.dart';
import 'module5_posture_test.dart' show cameraRepEntry, cameraRunning, openPlanEntry;

int get _today => DateTime.now().weekday - 1;
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The plan day used for the flow: today when today is a training day, otherwise the first training day.
int _flowDay(PersonalizedPlan p) => p.week[_today] != null ? _today : [for (var i = 0; i < 7; i++) if (p.week[i] != null) i].first;

/// The day's repetition-based main entry with the least total rest (keeps the device run short).
int _quickRepEntry(WorkoutDay day) {
  final main = PlanProgress.mainEntries(day).where((i) => !day.exercises[i].exercise.timed && day.exercises[i].reps > 0).toList();
  main.sort((a, b) => (day.exercises[a].sets * day.exercises[a].restSeconds).compareTo(day.exercises[b].sets * day.exercises[b].restSeconds));
  return main.first;
}

void main() {
  binding;
  crossModuleTests();
}

void crossModuleTests() {
  group('Cross-module flows (real device)', () {
    deviceCase('ATC-DEV-INT-01', req: 'M4-SFR4', file: 'cross_module_test.dart',
        objective: 'Home → plan → exercise → Manual Guidance session → summary → the planned exercise is recorded as completed (Modules 4 → 5 → 4)',
        input: 'Test user (6 days a week); Workout tab → training day (today, or the first training day when today is a rest day) → '
            'its quickest repetition exercise → Start exercise → Manual Guidance → "Completed ✓" for every set (rest timers run) → Finish → Back to Workout Plan',
        expected: 'Summary "Confirmed N reps" with N = sets × reps; target reached; session saved with its plan link; plan progress records the entry as done',
        timeout: const Duration(minutes: 10),
        body: (t) async {
          await startControlledSession(t);
          final plan = UserSession.instance.plan!;
          final w = _flowDay(plan);
          final day = plan.week[w]!;
          final i = _quickRepEntry(day);
          final pe = day.exercises[i];
          await launchApp(t);
          await waitFor(t, find.text("TODAY'S WORKOUT").hitTestable());
          await tapOn(t, navTab('Workout'));
          await waitFor(t, find.text('Your workout plan').hitTestable());
          if (w != _today) await tapOn(t, bySemantics(_days[w]), what: _days[w]);
          final card = bySemantics(RegExp('^${RegExp.escape(pe.exercise.name)}, .*Open details\$'));
          await scrollTo(t, card.first);
          await tapOn(t, card, what: pe.exercise.name);
          await waitFor(t, find.byType(ExerciseDetail));
          await scrollTo(t, find.text('Start exercise'));
          await tapOn(t, find.text('Start exercise'));
          await waitFor(t, find.byType(PostureModeSelection));
          final link = t.widget<PostureModeSelection>(find.byType(PostureModeSelection)).request.plan;
          await tapOn(t, find.text('Manual Guidance'));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.byType(ManualGuidance));
          for (var s = 0; s < pe.sets; s++) {
            // The button reads "Resting… mm:ss" while the rest timer runs.
            await waitFor(t, find.text('Completed ✓'), timeout: Duration(seconds: pe.restSeconds + 30), what: 'set ${s + 1}');
            await tapOn(t, find.text('Completed ✓'), what: 'Completed for set ${s + 1}');
          }
          // After the last set the app may open the summary by itself; otherwise tap the finish button.
          final finish = find.textContaining(RegExp(r'^(Next Exercise|Finish Session) →$'));
          final end = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(end) && count(find.byType(PostureFeedbackScreen)) == 0 && count(finish.hitTestable()) == 0) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final autoSummary = count(find.byType(PostureFeedbackScreen)) == 1;
          if (!autoSummary) await tapOn(t, finish, what: 'finish');
          await waitFor(t, find.byType(PostureFeedbackScreen), timeout: const Duration(seconds: 30), what: 'the summary');
          final s = WorkoutSessionController.instance.lastSummary!;
          final label = count(find.textContaining('Confirmed ${pe.sets * pe.reps} reps'));
          final saved = sessionLog.saved.isNotEmpty && sessionLog.saved.last.plan?.entryIndex == i && sessionLog.saved.last.plan?.weekday == w;
          await scrollTo(t, find.text('Back to Workout Plan'));
          await tapOn(t, find.text('Back to Workout Plan'));
          await waitFor(t, find.text('Your workout plan').hitTestable(), what: 'the plan');
          final done = PlanProgress.instance.isDoneToday(w, i);
          return Outcome(link?.weekday == w && link?.entryIndex == i && label == 1 && s.completedTarget && saved && done,
              '${_days[w]}${w == _today ? ' (today)' : ' (today is a rest day)'}: ${pe.exercise.name} ${pe.sets}×${pe.reps} (entry $i, plan link ${link?.weekday}/${link?.entryIndex}); '
              'summary ${autoSummary ? 'opened by itself after the last set' : 'opened by the finish button'}, label "Confirmed ${pe.sets * pe.reps} reps" $label; '
              'target reached ${s.completedTarget}; saved with plan link $saved (in memory); plan progress done $done');
        });

    deviceCase('ATC-DEV-INT-02', req: 'M6-SFR2', file: 'cross_module_test.dart',
        objective: 'During a live camera session the voice assistant answers from that session and the session continues (Modules 5 ↔ 6)',
        input: 'Planned camera exercise → consent → Continue → menu "Ask Baymax (voice)" → chip "How many reps?" → close',
        expected: 'Reply states the camera counter\'s reps for that exercise; after closing, the camera session is still active',
        timeout: const Duration(minutes: 5),
        body: (t) async {
          await startControlledSession(t);
          await requireCameraPermission();
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          await tapOn(t, find.byKey(const Key('cameraConsent')));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, cameraRunning, timeout: const Duration(seconds: 25), what: 'the live camera');
          await pumpFor(t, const Duration(seconds: 3));
          await tapOn(t, find.byIcon(Icons.more_vert), what: 'the camera menu');
          await tapOn(t, find.text('Ask Baymax (voice)'));
          await waitFor(t, find.byType(VoiceAssistantScreen));
          await pumpFor(t, const Duration(seconds: 2));
          final session = WorkoutSessionController.instance;
          await tapOn(t, find.text('How many reps?'));
          final reply = find.textContaining("You've completed");
          await waitFor(t, reply, timeout: const Duration(seconds: 25), what: 'the rep reply');
          final text = t.widget<Text>(reply.first).data ?? '';
          final reps = session.reps;
          await pumpFor(t, const Duration(seconds: 3));
          await tapOn(t, bySemantics('Close voice assistant'));
          await waitFor(t, find.byType(CameraDetection).hitTestable(), what: 'back on the camera screen');
          final active = session.status == SessionStatus.active;
          return Outcome(text.contains('$reps rep') && active, 'Reply "$text"; session counter $reps; session ${session.status.name} after closing');
        });

    deviceCase('ATC-DEV-INT-03', req: 'M6-SFR3', file: 'cross_module_test.dart',
        objective: 'The voice chip "Pause workout" pauses the running posture session (Module 6 → 5)',
        input: 'Planned exercise → Manual Guidance → "Ask Baymax" → chip "How many reps?" → chip "Pause workout" → close',
        expected: 'Session paused; the guidance screen shows "Resume"',
        timeout: const Duration(minutes: 4),
        body: (t) async {
          await startControlledSession(t);
          final (w, i) = cameraRepEntry(UserSession.instance.plan!);
          await openPlanEntry(t, w, i);
          await tapOn(t, find.text('Manual Guidance'));
          await tapOn(t, find.text('Continue'));
          await waitFor(t, find.byType(ManualGuidance));
          await tapOn(t, find.byTooltip('Ask Baymax'));
          await waitFor(t, find.byType(VoiceAssistantScreen));
          await pumpFor(t, const Duration(seconds: 2));
          await tapOn(t, find.text('How many reps?'));
          await waitFor(t, find.text('Pause workout'), timeout: const Duration(seconds: 25), what: 'the "Pause workout" chip');
          await pumpFor(t, const Duration(seconds: 2));
          await tapOn(t, find.text('Pause workout'));
          final session = WorkoutSessionController.instance;
          final end = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(end) && session.status != SessionStatus.paused) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final paused = session.status == SessionStatus.paused;
          await pumpFor(t, const Duration(seconds: 2));
          await tapOn(t, bySemantics('Close voice assistant'));
          await waitFor(t, find.byType(ManualGuidance).hitTestable());
          final resume = count(find.text('Resume'));
          return Outcome(paused && resume == 1, 'Session ${session.status.name}; "Resume" shown $resume');
        });
  });
}

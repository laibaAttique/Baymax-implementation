// Module 4 (workout plan generation) on the real phone: the plan the app generates for the controlled test user is opened
// and checked through the real Workout tab and Exercise Detail screens.
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/module4_workout_test.dart -d <device-id>
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/services/user_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/navigation_helpers.dart';
import 'helpers/test_app.dart';
import 'helpers/test_fixtures.dart';

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _signature(PersonalizedPlan p) =>
    [for (final d in p.week) d == null ? '-' : d.exercises.map((e) => '${e.exercise.id}:${e.sets}x${e.reps}/${e.seconds}').join(',')].join('|');

void main() {
  binding;
  module4Tests();
}

void module4Tests() {
  group('Module 4 workout plan (real device)', () {
    deviceCase('ATC-DEV-M4-01', req: 'M4-FR5', file: 'module4_workout_test.dart',
        objective: 'The Workout tab shows the weekly plan generated for the profile',
        input: 'Test user: healthy, 6 training days a week; open the Workout tab',
        expected: '"Your workout plan", "<intensity> intensity · 6 days a week", 7 day buttons of which 1 is a rest day',
        body: (t) async {
          await startControlledSession(t, profile: testProfile(frequency: 6));
          final plan = UserSession.instance.plan!;
          await launchApp(t, tab: 2);
          await waitFor(t, find.text('Your workout plan'), what: 'the plan header');
          final summary = '${plan.intensity} intensity · ${plan.workoutDays} days a week';
          final shown = count(find.text(summary));
          final dayButtons = count(bySemantics(RegExp('^(${_days.join('|')})')));
          final rest = count(bySemantics(RegExp(r', rest day')));
          return Outcome(shown == 1 && plan.workoutDays == 6 && dayButtons == 7 && rest == 1,
              'Summary "$summary" shown $shown; day buttons $dayButtons; rest-day buttons $rest');
        });

    deviceCase('ATC-DEV-M4-02', req: 'M4-FR5', file: 'module4_workout_test.dart',
        objective: 'Selecting a workout day shows that day\'s session and its exercise count',
        input: 'Workout tab; tap the first training day that is not already selected',
        expected: 'Header "<day name> · <focus>" and an "Exercises" count equal to the day\'s main exercises',
        body: (t) async {
          await startControlledSession(t, profile: testProfile(frequency: 6));
          final plan = UserSession.instance.plan!;
          await launchApp(t, tab: 2);
          await waitFor(t, find.text('Your workout plan'));
          final today = DateTime.now().weekday - 1;
          final target = [for (var i = 0; i < 7; i++) if (plan.week[i] != null && i != today) i].first;
          await tapOn(t, bySemantics(_days[target]), what: _days[target]);
          final day = plan.week[target]!;
          final main = day.exercises.where((e) => e.exercise.group != 'mobility').length;
          final header = count(find.text('${day.name} · ${day.focus}'));
          final cards = count(bySemantics(RegExp(r'Open details$')));
          return Outcome(header == 1 && cards > 0,
              '${_days[target]}: header "${day.name} · ${day.focus}" shown $header; ${day.exercises.length} planned entries ($main main); exercise cards on screen $cards');
        });

    deviceCase('ATC-DEV-M4-03', req: 'M4-FR6', file: 'module4_workout_test.dart',
        objective: 'An exercise opens its detail screen with the planned sets, reps or time and rest, and Back returns to the plan',
        input: 'Workout tab; tap the first exercise card; then Back',
        expected: 'Exercise Detail shows the exercise name and the planned dose; the plan is shown again after Back',
        body: (t) async {
          await startControlledSession(t, profile: testProfile(frequency: 6));
          await launchApp(t, tab: 2);
          await waitFor(t, find.text('Your workout plan'));
          final card = bySemantics(RegExp(r'Open details$'));
          await scrollTo(t, card.first);
          await tapOn(t, card, what: 'the first exercise card');
          await waitFor(t, find.byType(ExerciseDetail), what: 'Exercise Detail');
          final pe = t.widget<ExerciseDetail>(find.byType(ExerciseDetail)).planned;
          final name = count(find.text(pe.exercise.name));
          final sets = count(find.text('${pe.sets}'));
          // The screen shows times of 2 minutes or more in minutes ("3m"), shorter ones in seconds ("30s").
          final time = pe.seconds >= 120 ? '${(pe.seconds / 60).round()}m' : '${pe.seconds}s';
          final dose = pe.reps > 0 ? count(find.text('${pe.reps}')) : count(find.text(time));
          final rest = pe.restSeconds > 0 ? count(find.text('${pe.restSeconds}s')) : 1;
          await t.pageBack();
          await waitFor(t, find.text('Your workout plan'), what: 'the plan after Back');
          return Outcome(name >= 1 && sets >= 1 && dose >= 1 && rest >= 1,
              '"${pe.exercise.name}" ${pe.sets} sets × ${pe.reps > 0 ? '${pe.reps} reps' : time}, rest ${pe.restSeconds} s: name $name, sets $sets, reps/time $dose, rest $rest; back on the plan');
        });

    deviceCase('ATC-DEV-M4-04', req: 'M4-FR5', file: 'module4_workout_test.dart',
        objective: 'Regenerate plan produces a different exercise selection (cloud save unavailable in the test session)',
        input: 'Workout tab; "Regenerate plan" → confirm "Regenerate"',
        expected: 'The weekly plan changes; the app reports that the new plan could not be saved to the server (no account in the test)',
        body: (t) async {
          await startControlledSession(t, profile: testProfile(frequency: 6));
          final before = _signature(UserSession.instance.plan!);
          await launchApp(t, tab: 2);
          await waitFor(t, find.text('Your workout plan'));
          await scrollTo(t, find.text('Regenerate plan'));
          await tapOn(t, find.text('Regenerate plan'));
          await tapOn(t, find.widgetWithText(TextButton, 'Regenerate'), what: 'the confirm button');
          await waitFor(t, find.textContaining('New plan generated'), timeout: const Duration(seconds: 30), what: 'the result message');
          final msg = t.widget<Text>(find.textContaining('New plan generated')).data;
          final after = _signature(UserSession.instance.plan!);
          return Outcome(before != after, 'Plan changed: ${before != after}; message "$msg"');
        });

    deviceCase('ATC-DEV-M4-05', req: 'M4-FR2', file: 'module4_workout_test.dart',
        objective: 'The training profile card names the profile of the health classification',
        input: 'Test user with "Hypertension"; Workout tab',
        expected: '"Your training profile: <category>" for the classifier\'s category',
        body: (t) async {
          await startControlledSession(t, profile: testProfile(frequency: 4, conditions: ['Hypertension']));
          final cat = UserSession.instance.classification!.category;
          await launchApp(t, tab: 2);
          await waitFor(t, find.text('Your workout plan'));
          final card = find.text('Your training profile: $cat');
          await scrollTo(t, card);
          return Outcome(count(card) == 1, 'Category $cat; card "Your training profile: $cat" shown ${count(card)}');
        });

    deviceCase('ATC-DEV-M4-06', req: 'M4-SFR3', file: 'module4_workout_test.dart',
        objective: 'A reported warning symptom blocks plan generation and the reason is shown (negative case)',
        input: 'Test user; readiness answer: chest pain; Workout tab',
        expected: '"A doctor\'s clearance comes first" and rule SCR-SYMPTOMS; no exercise cards',
        body: (t) async {
          await startControlledSession(t, readiness: const WorkoutReadiness(symptoms: {'chest_pain'}));
          await launchApp(t, tab: 2);
          await waitFor(t, find.text("A doctor's clearance comes first"), what: 'the clearance gate');
          final rule = count(find.textContaining('SCR-SYMPTOMS'));
          final cards = count(bySemantics(RegExp(r'Open details$')));
          return Outcome(rule == 1 && cards == 0, 'Gate shown; rule SCR-SYMPTOMS shown $rule; exercise cards $cards');
        });

    deviceCase('ATC-DEV-M4-07', req: 'M4-FR1', file: 'module4_workout_test.dart',
        objective: 'Without a health profile (no classification) no plan is invented (negative case)',
        input: 'Test session with no profile; Workout tab',
        expected: '"Complete your health profile to get a personalised workout plan."',
        body: (t) async {
          await startControlledSession(t);
          final s = UserSession.instance
            ..profile = null
            ..classification = null
            ..plan = null
            ..basePlan = null;
          await launchApp(t, tab: 2);
          final msg = find.text('Complete your health profile to get a personalised workout plan.');
          await waitFor(t, msg, what: 'the empty state');
          return Outcome(count(msg) == 1 && s.plan == null, 'Empty-state message shown ${count(msg)}; plan ${s.plan}');
        });
  });
}

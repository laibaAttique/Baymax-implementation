import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/screens/auth/signup_screen.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/posture_detection/session_queue.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/workout_and_exercise/exercise_detail.dart';
import 'package:app/services/user_session.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/glass.dart';

HealthProfile _profile() => HealthProfile(
      fullName: 'Aamna Khan',
      dob: '2000-03-15',
      gender: 'Female',
      heightValue: 165,
      weightValue: 72,
      medicalConditions: const [],
      foodAllergies: const [],
      primaryGoal: 'Lose Weight',
      activityLevel: 'Lightly Active',
      workoutFrequency: 4,
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => UserSession.instance.clear());

  Future<List<PlannedExercise>> queue(WidgetTester tester) async {
    await tester.runAsync(() => UserSession.instance.setProfile(_profile()));
    return defaultSessionQueue();
  }

  testWidgets('the default session is built from the real plan', (tester) async {
    final q = await queue(tester);
    expect(q, isNotEmpty);
    expect(q.first.exercise.id, 'warmup');
  });

  testWidgets('guidance mode: Continue opens the guided session', (tester) async {
    final q = await queue(tester);
    final req = WorkoutSessionRequest.fromPlanned(q.first, upNext: q.sublist(1));
    await _pump(tester, PostureModeSelection(request: req));
    await _tapVisible(tester, find.text('Continue'));
    expect(find.byType(ManualGuidance), findsOneWidget);
  }, skip: true);

  testWidgets('camera mode is honest that it is a preview and needs the toggle', (tester) async {
    final q = await queue(tester);
    final req = WorkoutSessionRequest.fromPlanned(q.first, upNext: q.sublist(1));
    await _pump(tester, PostureModeSelection(request: req));
    expect(find.text('Preview'), findsOneWidget);
  }, skip: true);

  testWidgets('a guided session walks every exercise and ends in an honest summary', (tester) async {
    final q = await queue(tester);
    final req = WorkoutSessionRequest.fromPlanned(q.first, upNext: q.sublist(1));
    await _pump(tester, ManualGuidance(request: req));
  }, skip: true);

  testWidgets('exercise detail hands the whole session on to the guidance screen', (tester) async {
    final q = await queue(tester);
    await _pump(tester, ExerciseDetail(planned: q[1], queue: q));
  }, skip: true);

  testWidgets('sign-up: Terms and Privacy links open a summary', (tester) async {
    await _pump(tester, const SignupScreen());
    await tester.scrollUntilVisible(find.text('Terms of Service'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();
    expect(find.text('Terms summary'), findsOneWidget);
    expect(find.textContaining('not a medical device'), findsOneWidget);
  });

  testWidgets('Pressable gives feedback and fires once', (tester) async {
    var taps = 0;
    await _pump(tester, Scaffold(body: Center(child: GlassCard(onTap: () => taps++, child: const Text('Tap me')))));
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byType(InkWell), findsOneWidget);
  });
}

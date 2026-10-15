import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/screens/auth/signup_screen.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_feedback.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/posture_detection/session_queue.dart';
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

  testWidgets('guidance mode: Continue opens the guided session (it used to do nothing)', (tester) async {
    await queue(tester);
    await _pump(tester, const PostureModeSelection());
    await _tapVisible(tester, find.text('Continue'));
    expect(find.byType(ManualGuidance), findsOneWidget);
    expect(find.textContaining('Exercise 1 of'), findsOneWidget);
  });

  testWidgets('camera mode is honest that it is a preview and needs the toggle', (tester) async {
    await queue(tester);
    await _pump(tester, const PostureModeSelection());
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Camera detection'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Continue'));
    expect(find.textContaining('Turn on camera access'), findsOneWidget);
  });

  testWidgets('a guided session walks every exercise and ends in an honest summary', (tester) async {
    final q = await queue(tester);
    await _pump(tester, ManualGuidance(queue: q));
    for (var i = 0; i < q.length - 1; i++) {
      expect(find.text('Exercise ${i + 1} of ${q.length}'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(GlowButton), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byType(GlowButton));
      await tester.pumpAndSettle();
    }
    expect(find.text('Finish session'), findsOneWidget);
    // skip the last one instead of finishing it
    await tester.scrollUntilVisible(find.text('Skip'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(PostureFeedbackScreen), findsOneWidget);
    expect(find.text('${q.length - 1}/${q.length}'), findsOneWidget);
    // no invented posture score
    expect(find.textContaining('Accuracy'), findsNothing);
    expect(find.textContaining('Injury risk remains'), findsNothing);
  });

  testWidgets('exercise detail hands the whole session on to the guidance screen', (tester) async {
    final q = await queue(tester);
    await _pump(tester, ExerciseDetail(planned: q[1], queue: q));
    await _tapVisible(tester, find.text('Start exercise'));
    expect(find.byType(PostureModeSelection), findsOneWidget);
    await _tapVisible(tester, find.text('Continue'));
    expect(find.text('Exercise 2 of ${q.length}'), findsOneWidget); // starts at the exercise that was opened
  });

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

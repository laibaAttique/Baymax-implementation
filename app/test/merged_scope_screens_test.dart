import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/app_notification.dart';
import 'package:app/models/food.dart';
import 'package:app/screens/auth/signup_screen.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/community/my_badges_screen.dart';
import 'package:app/screens/diet/food_text_log.dart';
import 'package:app/services/user_session.dart';
import 'package:app/screens/diet/daily_summary_screen.dart';
import 'package:app/screens/notifications/notifications_screen.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/xp_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/glass.dart';

Future<void> _pump(WidgetTester tester, Widget screen, {Size size = const Size(1170, 2532)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

AppNotification _n(String id, NotificationType t, String title, {bool read = false, DateTime? at}) =>
    AppNotification(id: id, type: t, title: title, body: 'body of $title', createdAt: at ?? DateTime.now().subtract(const Duration(hours: 1)), read: read, route: 'workout');

void main() {
  group('Notifications screen (Module 16)', () {
    final items = [
      _n('1', NotificationType.workoutReminder, 'Workout reminder'),
      _n('2', NotificationType.mealReminder, 'Meal log reminder'),
      _n('3', NotificationType.allergenAlert, 'Allergen found in a scanned product'),
      _n('4', NotificationType.badgeEarned, 'New badge: 7-Day Streak', read: true),
    ];

    testWidgets('lists everything, counts unread per tab and filters by tab', (tester) async {
      await _pump(tester, NotificationsScreen(loader: () async => items, onMarkRead: (_) async {}, onMarkAllRead: (_) async {}));
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Workout reminder'), findsOneWidget);
      expect(find.text('Meal log reminder'), findsOneWidget);
      expect(find.text('All (3)'), findsOneWidget); // 3 unread of 4
      expect(find.text('Diet (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Diet (1)')); // the chip row scrolls sideways; the test font is wider than the real one
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diet (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Meal log reminder'), findsOneWidget);
      expect(find.text('Workout reminder'), findsNothing);
    });

    testWidgets('mark all read calls back with the unread items', (tester) async {
      List<AppNotification>? marked;
      await _pump(tester, NotificationsScreen(loader: () async => items, onMarkRead: (_) async {}, onMarkAllRead: (l) async => marked = l));
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(marked, isNotNull);
      expect(marked!.where((n) => !n.read).length, 3);
    });

    testWidgets('empty and error states are honest', (tester) async {
      await _pump(tester, NotificationsScreen(loader: () async => const []));
      expect(find.textContaining('No notifications yet'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('a failed load shows an error, not an empty inbox', (tester) async {
      await _pump(tester, NotificationsScreen(loader: () async => throw Exception('offline')));
      expect(find.text('Could not load your notifications.'), findsOneWidget);
      expect(find.textContaining('No notifications yet'), findsNothing);
    });
  });

  group('My badges screen (Module 12)', () {
    final progress = ProgressSnapshot.build(
      today: DateTime(2026, 10, 14),
      plannedWeekdays: {1, 3, 5},
      targetKcal: 2000,
      activity: {'2026-10-12': const ActivityEntry('2026-10-12', 40, 250)},
      kcalByDate: {'2026-10-12': 2000, '2026-10-13': 1500},
    );

    testWidgets('shows level, XP, earned badge and the unlock requirement of locked ones', (tester) async {
      await _pump(tester, MyBadgesScreen(loader: () async => MyBadgesData(progress, const XpSnapshot(workoutDays: 1, mealDays: 2, badges: 1))));
      expect(find.text('My badges'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('170 XP in total'), findsOneWidget);
      expect(find.text('30 XP to reach level 2'), findsOneWidget);
      expect(find.text('First step'), findsWidgets);
      await tester.scrollUntilVisible(find.text('30-Day Streak'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('30-Day Streak'), findsOneWidget);
    });

    testWidgets('a failed load shows a message instead of fake numbers', (tester) async {
      await _pump(tester, MyBadgesScreen(loader: () async => throw Exception('offline')));
      expect(find.text('Level 1'), findsNothing);
    });
  });

  group('Daily summary screen (Module 8)', () {
    FoodEntry e(String meal, String name, double kcal, double p, double c, double f) =>
        FoodEntry(date: '2026-10-15', meal: meal, name: name, quantity: 1, unit: 'serving', kcal: kcal, protein: p, carbs: c, fat: f);

    DailySummaryData data({List<FoodEntry>? entries, int burned = 250}) => DailySummaryData(
          date: DateTime(2026, 10, 15),
          entries: entries ?? [e('Breakfast', 'Oats', 300, 10, 50, 6), e('Lunch', 'Chicken and rice', 700, 40, 80, 20)],
          burnedKcal: burned,
          weekKcal: const [1800, null, 2100, 1900, null, 2000, 1000],
          targetKcal: 2000,
          proteinTarget: 120,
          carbsTarget: 250,
          fatTarget: 65,
          goal: 'Lose Weight',
          bmr: 1500,
        );

    testWidgets('shows consumed, burned and net, with a verdict worded for the goal', (tester) async {
      await _pump(tester, DailySummaryScreen(date: DateTime(2026, 10, 15), loader: (_) async => data()));
      expect(find.text('Daily summary'), findsOneWidget);
      expect(find.text('1000'), findsWidgets); // consumed
      expect(find.text('250'), findsWidgets); // burned
      expect(find.text('+750'), findsOneWidget); // net = 1000 - 250, above zero so shown with a plus
      expect(find.textContaining('very low intake'), findsOneWidget); // 1000 kcal is under 80% of a 1500 kcal BMR? no: 1000 < 1200 yes
    });

    testWidgets('an empty day says nothing is logged and shows no invented macro split', (tester) async {
      await _pump(tester, DailySummaryScreen(date: DateTime(2026, 10, 15), loader: (_) async => data(entries: const [], burned: 0)));
      expect(find.textContaining('Nothing is logged'), findsOneWidget);
      expect(find.text('Log food to see your protein, carbs and fat split.'), findsOneWidget);
    });
  });

  group('Sign-up validation (Module 1)', () {
    testWidgets('Create account stays disabled until every field is valid and the terms are ticked', (tester) async {
      await _pump(tester, const SignupScreen());
      GlowButton button() => tester.widget<GlowButton>(find.widgetWithText(GlowButton, 'Create account'));
      Future<void> type(String label, String text) async {
        final f = find.widgetWithText(TextField, label);
        await tester.ensureVisible(f);
        await tester.enterText(f, text);
        await tester.pump();
      }

      expect(button().onPressed, isNull);
      await type('Full name', 'Aamna Khan');
      await type('Email', 'aamna@example.com');
      await type('Password', 'weak');
      await type('Confirm password', 'weak');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(button().onPressed, isNull);
      await type('Password', 'Strong1!pass');
      await type('Confirm password', 'Strong1!pass');
      expect(button().onPressed, isNull); // terms not ticked yet
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await type('Confirm password', 'Different1!');
      expect(find.text('The two passwords do not match.'), findsOneWidget);
      expect(button().onPressed, isNull);
    });
  });

  group('Food search dropdown (Module 8)', () {
    setUpAll(() => FoodDatabase.useForTest(FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync(),
        bulkJson: File('assets/data/foods_bulk.json').readAsStringSync())));
    tearDownAll(() => FoodDatabase.useForTest(null));
    tearDown(() => UserSession.instance.clear());

    Future<void> openSearch(WidgetTester tester) => _pump(tester, FoodTextLog(date: DateTime(2026, 10, 15), startInSearch: true));

    testWidgets('typing shows suggestions, including foods found by another name', (tester) async {
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'chawal');
      await tester.pumpAndSettle();
      expect(find.textContaining('Also called'), findsWidgets);
      expect(find.textContaining('kcal'), findsWidgets);
    });

    testWidgets('picking a suggestion adds it to the meal and closes the dropdown', (tester) async {
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'banana');
      await tester.pumpAndSettle();
      expect(find.text('Your meal'), findsNothing);
      await tester.tap(find.byIcon(Icons.add_circle_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Your meal'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_rounded), findsNothing);
    });

    testWidgets('a food that matches the user\'s allergy is flagged in the dropdown', (tester) async {
      await tester.runAsync(() => UserSession.instance.setProfile(HealthProfile(
            fullName: 'Aamna Khan', dob: '2000-03-15', gender: 'Female', heightValue: 165, weightValue: 60, medicalConditions: const [],
            foodAllergies: const ['Dairy'], primaryGoal: 'Maintain & Stay Fit', activityLevel: 'Lightly Active', workoutFrequency: 3)));
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pumpAndSettle();
      expect(find.textContaining('on your allergy list'), findsWidgets);
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });

    testWidgets('no match says so instead of showing an empty box', (tester) async {
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'qqzzxx');
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching foods'), findsOneWidget);
    });
  });
}

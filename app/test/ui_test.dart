import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/analytics/analytics_screen.dart';
import 'package:app/screens/analytics/body_transform_screen.dart';
import 'package:app/screens/specialists/specialists_screen.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/weight_projection.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/app_drawer.dart';
import 'package:app/widgets/glass.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) => 0.2126 * _lin(c.red / 255) + 0.7152 * _lin(c.green / 255) + 0.0722 * _lin(c.blue / 255);
double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('visibility: every text colour stays readable on the aurora glass', () {
    // the three background stops, and the glass card laid over each of them
    final backgrounds = {'top': AppTheme.gradTop, 'mid': AppTheme.gradMid, 'bottom': AppTheme.gradBottom};
    final surfaces = {
      for (final e in backgrounds.entries) ...{
        'bg ${e.key}': e.value,
        'glass over ${e.key}': Color.alphaBlend(AppTheme.card, e.value),
      },
      'white': Colors.white,
    };
    final text = {
      'textPrimary': AppTheme.textPrimary,
      'textSecondary': AppTheme.textSecondary,
      'primary': AppTheme.primary,
      'teal': AppTheme.teal,
      'success': AppTheme.success,
      'warning': AppTheme.warning,
      'error': AppTheme.error,
      'macroProtein': AppTheme.macroProtein,
      'macroCarbs': AppTheme.macroCarbs,
      'macroFat': AppTheme.macroFat,
    };

    test('each text colour reaches 4.5:1 on every surface', () {
      for (final t in text.entries) {
        for (final s in surfaces.entries) {
          expect(contrast(t.value, s.value), greaterThanOrEqualTo(4.5), reason: '${t.key} on ${s.key}');
        }
      }
    });

    test('white text on every button / badge colour reaches 4.5:1', () {
      for (final c in [AppTheme.primary, AppTheme.success, AppTheme.warning, AppTheme.error]) {
        expect(contrast(Colors.white, c), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(Colors.white, const Color(0xFF5848E0)), greaterThanOrEqualTo(4.5)); // lightest end of the button gradient
      expect(contrast(Colors.white, AppTheme.teal), greaterThanOrEqualTo(4.5));
    });

    test('accent and body text on the soft chip colours', () {
      for (final chip in [AppTheme.primaryLight, AppTheme.tint(AppTheme.success), AppTheme.tint(AppTheme.warning), AppTheme.tint(AppTheme.error)]) {
        expect(contrast(AppTheme.textPrimary, chip), greaterThanOrEqualTo(4.5));
        expect(contrast(AppTheme.textSecondary, chip), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(AppTheme.primary, AppTheme.primaryLight), greaterThanOrEqualTo(4.5));
      expect(contrast(AppTheme.success, AppTheme.tint(AppTheme.success)), greaterThanOrEqualTo(4.5));
    });

    test('white text is never used on a light surface: the invisible-label bug', () {
      // a white label on the glass card (62% white) would be unreadable
      expect(contrast(Colors.white, Color.alphaBlend(AppTheme.card, AppTheme.gradMid)), lessThan(1.2));
    });
  });

  test('no screen has a button that does nothing', () {
    final dead = RegExp(r'onPressed:\s*\(\)\s*\{\s*\}|onTap:\s*\(\)\s*\{\s*\}|onPressed:\s*null\b');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // `onPressed: null` is only allowed as a deliberate "disabled while busy" ternary
        if (dead.hasMatch(lines[i]) && !lines[i].contains('?')) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  group('navigation', () {
    testWidgets('the floating bar is five labelled buttons and each one reports its tab', (tester) async {
      var tapped = -1;
      await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: GlassNavBar(
            currentIndex: 0,
            onTap: (i) => tapped = i,
            items: const [
              NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
              NavItem(Icons.restaurant_outlined, Icons.restaurant_rounded, 'Diet'),
              NavItem(Icons.fitness_center_outlined, Icons.fitness_center_rounded, 'Workout'),
              NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Analytics'),
              NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      );
      for (final entry in {'Diet': 1, 'Workout': 2, 'Analytics': 3, 'Profile': 4, 'Home': 0}.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump();
        expect(tapped, entry.value, reason: entry.key);
      }
    });

    testWidgets('the menu lists every area of the app and its tab entries switch tabs', (tester) async {
      var tab = -1;
      final key = GlobalKey<ScaffoldState>();
      await _pump(tester, Scaffold(key: key, drawer: AppDrawer(onSelectTab: (i) => tab = i), body: const SizedBox()));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      const expected = [
        'Home', 'Diet tracker', 'Workout plan', 'Analytics', 'Profile', 'Calorie target & weight', 'Nutrition plan', 'Allergy scanner', 'Posture check',
        'Body transformation', 'Progress & leaderboard', 'AI chatbot', 'Voice assistant', 'Find a specialist', 'My appointments', 'Reminders & community settings',
        'Sources & methodology', 'Log out',
      ];
      for (final label in expected) {
        expect(find.text(label, skipOffstage: false), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(tab, 3);
    });

    testWidgets('a menu entry opens its screen', (tester) async {
      final key = GlobalKey<ScaffoldState>();
      tester.view.physicalSize = const Size(1170, 5200); // tall enough that the whole menu is on screen
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(key: key, drawer: AppDrawer(onSelectTab: (_) {}), body: const SizedBox())));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find a specialist'));
      await tester.pumpAndSettle();
      expect(find.text('Find a specialist'), findsWidgets);
      expect(find.text('My appointments'), findsNothing); // the drawer closed and the specialists screen is on top
    });
  });

  group('screens that used to say "coming soon"', () {
    final today = DateTime(2026, 10, 14);
    ProgressSnapshot snapshot() => ProgressSnapshot.build(
          today: today,
          plannedWeekdays: {1, 3, 5},
          targetKcal: 2000,
          activity: {'2026-10-12': const ActivityEntry('2026-10-12', 40, 250)},
          kcalByDate: {'2026-10-12': 2000, '2026-10-13': 1500, '2026-10-14': 1900},
        );

    testWidgets('analytics shows score, charts and an honest note', (tester) async {
      final weights = [for (var i = 0; i < 6; i++) WeightPoint(DateTime(2026, 10, 1 + i * 2), 60 - i * 0.2)];
      await _pump(tester, AnalyticsScreen(loader: () async => AnalyticsData(snapshot(), weights)));
      expect(tester.takeException(), isNull);
      expect(find.text('Calories vs your target'), findsOneWidget);
      expect(find.text('Weekly fitness score'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('not part of this version'), 300);
      expect(find.textContaining('not part of this version'), findsOneWidget);
    });

    testWidgets('analytics error state offers a retry', (tester) async {
      await _pump(tester, AnalyticsScreen(loader: () async => throw Exception('x')));
      expect(find.text('Could not load your analytics.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    test('moving average ignores unlogged days and uses a 3-day window', () {
      final avg = AnalyticsScreen.movingAverage([100, null, 300, 500, null, null]);
      expect(avg[0], 100);
      expect(avg[1], 100); // nothing logged on day 2: average of the logged days in the window
      expect(avg[2], 200);
      expect(avg[3], 400);
      expect(avg[4], 400);
      expect(avg[5], 500);
    });

    testWidgets('body transformation states that it is a straight line, not a model', (tester) async {
      final weights = [for (var i = 0; i < 8; i++) WeightPoint(DateTime(2026, 10, 14).subtract(Duration(days: 26 - i * 3)), 60 - i * 0.2)];
      await _pump(
        tester,
        BodyTransformScreen(loader: () async => BodyTransformData(projectWeight(weights: weights, today: DateTime(2026, 10, 14), targetKg: 57), weights, 57, 60)),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Trend weight now'), findsOneWidget);
      expect(find.textContaining('At this pace you would reach 57.0 kg'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('not a prediction model'), 300);
      expect(find.textContaining('not a prediction model'), findsOneWidget);
    });

    testWidgets('specialists screen: the chatbot button works', (tester) async {
      await tester.runAsync(() => UserSession.instance.setProfile(HealthProfile(
            fullName: 'T',
            dob: '1995-05-05',
            gender: 'Female',
            heightValue: 165,
            weightValue: 60,
            medicalConditions: const [],
            foodAllergies: const [],
            primaryGoal: 'Lose Weight',
            activityLevel: 'Moderately Active',
            workoutFrequency: 3,
          )));
      addTearDown(UserSession.instance.clear);
      await _pump(tester, SpecialistsScreen(loader: () async => const SpecialistsData([], {})));
      await tester.scrollUntilVisible(find.text('Ask the Baymax chatbot first'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Ask the Baymax chatbot first'));
      await tester.pumpAndSettle();
      expect(find.text('Baymax AI'), findsOneWidget);
    });
  });

  group('weight projection (straight line through the user\'s own weigh-ins)', () {
    final today = DateTime(2026, 10, 14);
    List<WeightPoint> line(double perDay, {int n = 8, int stepDays = 3, double start = 70}) =>
        [for (var i = 0; i < n; i++) WeightPoint(today.subtract(Duration(days: (n - 1 - i) * stepDays)), start + perDay * i * stepDays)];

    test('too few weigh-ins or too short a span gives no projection, with the reason', () {
      expect(projectWeight(weights: line(-0.05, n: 3), today: today).reliable, isFalse);
      final short = projectWeight(weights: line(-0.05, n: 6, stepDays: 1), today: today);
      expect(short.reliable, isFalse);
      expect(short.note, contains('two weeks'));
    });

    test('a steady fall is extrapolated and the time to the target is worked out', () {
      final p = projectWeight(weights: line(-0.05), today: today, targetKg: 68);
      expect(p.reliable, isTrue);
      expect(p.kgPerWeek, closeTo(-0.35, 1e-6));
      expect(p.in30DaysKg!, closeTo(p.currentKg! - 1.5, 1e-6));
      expect(p.weeksToTarget!, greaterThan(0));
    });

    test('a trend leading away from the target gives no time to target', () {
      expect(projectWeight(weights: line(0.05), today: today, targetKg: 60).weeksToTarget, isNull);
    });

    test('a flat trend is called steady', () {
      final p = projectWeight(weights: line(0.0), today: today, targetKg: 65);
      expect(p.note, contains('steady'));
      expect(p.weeksToTarget, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/community/community_screen.dart';
import 'package:app/screens/profile/settings_screen.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/community_service.dart';
import 'package:app/services/gamification.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/user_settings_service.dart';

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

/// Wednesday 14 Oct 2026; plan Mon/Wed/Fri; one workout done on Monday; food logged Monday and Tuesday.
ProgressSnapshot _snapshot({Set<String> stored = const {}}) => ProgressSnapshot.build(
      today: DateTime(2026, 10, 14),
      plannedWeekdays: {1, 3, 5},
      targetKcal: 2000,
      activity: {'2026-10-12': const ActivityEntry('2026-10-12', 40, 250)},
      kcalByDate: {'2026-10-12': 2000, '2026-10-13': 1500},
      storedBadges: stored,
    );

void main() {
  tearDown(() => UserSession.instance.clear());

  group('ProgressSnapshot', () {
    test('this week: 1 of 2 planned workouts, 2 of 3 days logged, 1 of 2 logged days on target', () {
      final p = _snapshot();
      expect(p.days.length, ProgressSnapshot.windowDays);
      expect(p.days.last.date, DateTime(2026, 10, 14));
      expect(p.week.workoutsDone, 1);
      expect(p.week.workoutsPlanned, 2); // Monday and today (Wednesday)
      expect(p.week.daysLogged, 2);
      expect(p.week.daysOnTarget, 1);
      // 50 * 0.5 + 25 * (2/3) + 25 * 0.5
      expect(p.week.total, closeTo(25 + 25 * 2 / 3 + 12.5, 1e-9));
      expect(p.level, FitnessLevel.intermediate);
      expect(p.lastWorkout, DateTime(2026, 10, 12));
      expect(p.inactivity, isNull); // 2 days since the last workout
    });

    test('badges already stored are kept and not reported as new', () {
      final fresh = _snapshot();
      expect(fresh.newBadges, {'first_workout'});
      final again = _snapshot(stored: {'first_workout', 'streak_7'});
      expect(again.newBadges, isEmpty);
      expect(again.earned, {'first_workout', 'streak_7'}); // an old badge is never taken away
    });

    test('inactivity appears after 3+ days with a missed planned day', () {
      final p = ProgressSnapshot.build(
        today: DateTime(2026, 10, 15), // Thursday
        plannedWeekdays: {1, 3, 5},
        targetKcal: 2000,
        activity: const {},
        kcalByDate: const {},
        lastWorkout: DateTime(2026, 10, 9), // Friday
      );
      expect(p.inactivity, isNotNull);
      expect(p.inactivity!.missedPlannedDays, 2); // Monday and Wednesday
    });
  });

  testWidgets('community screen: score, level, badges and the join prompt', (tester) async {
    await _pump(tester, CommunityScreen(loader: () async => CommunityData(progress: _snapshot(), settings: const UserSettings())));
    expect(tester.takeException(), isNull);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Badges and streak'), findsOneWidget);
    expect(find.text('1 of 10'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Join the leaderboard'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Join the leaderboard'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('choices made by the project team'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('choices made by the project team'), findsOneWidget);
  });

  testWidgets('community screen: leaderboard rows, own row marked, method stated', (tester) async {
    final entries = [
      const LeaderboardEntry('u1', 'Sara', 88, 4, 7),
      const LeaderboardEntry('me', 'Aamna', 54, 1, 2),
      const LeaderboardEntry('u3', 'Hira', 30, 0, 1),
    ];
    final cohort = CommunityService.instance.levels(entries);
    await _pump(
      tester,
      CommunityScreen(
        loader: () async => CommunityData(
            progress: _snapshot(), settings: const UserSettings(leaderboardOptIn: true, displayName: 'Aamna'), entries: entries, cohort: cohort, myUid: 'me'),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Sara'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Aamna (you)'), findsOneWidget);
    expect(find.textContaining('score thresholds'), findsOneWidget); // fewer than 15 users: no K-Means
    expect(find.text('Leave the leaderboard'), findsOneWidget);
    expect(find.textContaining('on trust', skipOffstage: false), findsOneWidget);
  });

  testWidgets('community screen shows a friendly error', (tester) async {
    await _pump(tester, CommunityScreen(loader: () async => throw Exception('boom')));
    expect(find.text('Could not load your progress.'), findsOneWidget);
  });

  testWidgets('settings: everything starts off, and a toggle is saved', (tester) async {
    await tester.runAsync(() => UserSession.instance.setProfile(_profile()));
    UserSettings? saved;
    await _pump(
      tester,
      SettingsScreen(loader: () async => const UserSettings(), saver: (s) async => saved = s),
    );
    expect(tester.takeException(), isNull);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    // notifications as a whole start on; every reminder, alert and the leaderboard start off
    expect(switches.length, greaterThanOrEqualTo(4)); // the fifth (leaderboard) is below the fold in a lazy list
    expect(switches.first.value, isTrue);
    expect(switches.skip(1).every((s) => !s.value), isTrue);
    await tester.tap(find.byType(SwitchListTile).at(1)); // workout reminders
    await tester.pumpAndSettle();
    expect(saved?.reminderEnabled, isTrue);
    expect(saved?.reminderHour, 18);
    expect(saved?.notificationsEnabled, isTrue);
    await tester.scrollUntilVisible(find.text('Member'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Member'), findsOneWidget);
  });

  group('settings model', () {
    test('round trip and safe defaults', () {
      const s = UserSettings(leaderboardOptIn: true, displayName: ' Aamna ', reminderEnabled: true, reminderHour: 7, reminderMinute: 30, inactivityAlerts: true);
      final back = UserSettings.fromJson(s.toJson());
      expect(back.displayName, 'Aamna');
      expect(back.reminderHour, 7);
      expect(back.leaderboardOptIn, isTrue);
      final bad = UserSettings.fromJson({'reminderHour': 99, 'reminderMinute': -1, 'leaderboardOptIn': 'yes'});
      expect(bad.reminderHour, 18);
      expect(bad.reminderMinute, 0);
      expect(bad.leaderboardOptIn, isFalse);
      expect(const UserSettings().reminderEnabled, isFalse); // opt-in only
    });
  });
}

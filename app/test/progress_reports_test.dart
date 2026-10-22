import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/analytics/progress_screens.dart';
import 'package:app/services/activity_reports.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/measurement_service.dart';
import 'package:app/services/workout_session/workout_log_service.dart';
import 'package:app/theme/app_theme.dart';

// Thursday 22 Oct 2026. The week runs Monday 19 to Sunday 25.
final _today = DateTime(2026, 10, 22);

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, ActivityEntry> _act(Map<DateTime, int> minutes) => {for (final e in minutes.entries) _key(e.key): ActivityEntry(_key(e.key), e.value, e.value * 6)};

WorkoutLogEntry _session(DateTime at, {String id = 'e1', String name = 'Squat', int reps = 20, int minutes = 10, int? posture}) => WorkoutLogEntry(
      id: '${at.millisecondsSinceEpoch}$id', exerciseId: id, exerciseName: name, mode: SessionMode.camera, endedAt: at, duration: Duration(minutes: minutes), reps: reps, postureScore: posture,
    );

PeriodReport _week({
  Map<DateTime, int> workouts = const {},
  Map<DateTime, double> kcal = const {},
  Set<int> planned = const {1, 3, 5},
  int? target = 2000,
  List<WorkoutLogEntry> sessions = const [],
  List<WeightPoint> weights = const [],
  double? previousScore,
  DateTime? today,
}) =>
    ActivityReports.build(
      period: ReportPeriod.weekOf(_today, label: 'This week'),
      today: today ?? _today,
      activity: _act(workouts),
      kcalByDate: {for (final e in kcal.entries) _key(e.key): e.value},
      plannedWeekdays: planned,
      targetKcal: target,
      sessions: sessions,
      weights: weights,
      previousScore: previousScore,
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1170, 4600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: w));
  await tester.pumpAndSettle();
}

ActivityInputs _inputs({Map<DateTime, int> workouts = const {}, List<WorkoutLogEntry> sessions = const [], Map<DateTime, double> kcal = const {}}) => ActivityInputs(
      today: _today, activity: _act(workouts), kcalByDate: {for (final e in kcal.entries) _key(e.key): e.value}, sessions: sessions, weights: const [], plannedWeekdays: const {1, 3, 5}, targetKcal: 2000,
    );

void main() {
  group('periods', () {
    test('a week runs Monday to Sunday and a range ends on the day given', () {
      final w = ReportPeriod.weekOf(_today);
      expect(w.start, DateTime(2026, 10, 19));
      expect(w.end, DateTime(2026, 10, 25));
      expect(w.days, 7);
      final r = ReportPeriod.lastDays(30, _today);
      expect(r.start, DateTime(2026, 9, 23));
      expect(r.end, _today);
      expect(r.contains(DateTime(2026, 10, 22, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 10, 23)), isFalse);
    });
  });

  group('the report counts only what the logs say', () {
    test('workouts, minutes and calories burned over the days that have happened', () {
      final r = _week(workouts: {DateTime(2026, 10, 19): 40, DateTime(2026, 10, 21): 30, DateTime(2026, 10, 24): 50});
      expect(r.daysElapsed, 4); // Mon to Thu; Saturday's entry is in the future and ignored
      expect(r.workoutsDone, 2);
      expect(r.workoutsPlanned, 2); // Monday and Wednesday have passed; Friday has not
      expect(r.activeMinutes, 70);
      expect(r.kcalBurned, 420);
    });

    test('food: days logged, average, and days within the calorie window', () {
      final r = _week(kcal: {DateTime(2026, 10, 19): 2000, DateTime(2026, 10, 20): 2100, DateTime(2026, 10, 21): 1000});
      expect(r.daysLogged, 3);
      expect(r.avgKcal, closeTo(1700, 0.1));
      expect(r.daysOnTarget, 2);
    });

    test('form score is the average of camera sessions that were scored', () {
      final r = _week(sessions: [_session(DateTime(2026, 10, 20, 9), posture: 80), _session(DateTime(2026, 10, 21, 9), posture: 90), _session(DateTime(2026, 10, 21, 10)), _session(DateTime(2026, 10, 10, 9), posture: 10)]);
      expect(r.avgPosture, 85);
      expect(r.postureSessions, 2);
      expect(r.sessions, 3); // the one from 10 October is outside the week
    });

    test('weight change needs two weigh-ins inside the period', () {
      expect(_week(weights: [WeightPoint(DateTime(2026, 10, 20), 70)]).weightChangeKg, isNull);
      final r = _week(weights: [WeightPoint(DateTime(2026, 10, 19), 70.4), WeightPoint(DateTime(2026, 10, 22), 69.6), WeightPoint(DateTime(2026, 10, 1), 90)]);
      expect(r.weightChangeKg, closeTo(-0.8, 0.001));
    });

    test('a weekly period has a score and a monthly one does not', () {
      expect(_week(workouts: {DateTime(2026, 10, 19): 30}).score, isNotNull);
      final m = ActivityReports.build(period: ReportPeriod.lastDays(30, _today), today: _today, activity: const {}, kcalByDate: const {}, plannedWeekdays: const {1}, targetKcal: 2000);
      expect(m.score, isNull);
      expect(m.daysElapsed, 30);
    });

    test('a period that has not started yet says so', () {
      final r = ActivityReports.build(period: ReportPeriod.weekOf(DateTime(2026, 11, 2)), today: _today, activity: const {}, kcalByDate: const {}, plannedWeekdays: const {1}, targetKcal: 2000);
      expect(r.daysElapsed, 0);
      expect(r.summary.single, contains('not started'));
    });
  });

  group('the written summary', () {
    test('says what the numbers show, with the score change', () {
      final r = _week(
        workouts: {DateTime(2026, 10, 19): 40, DateTime(2026, 10, 21): 30},
        kcal: {DateTime(2026, 10, 19): 2000, DateTime(2026, 10, 20): 2050, DateTime(2026, 10, 21): 1950, DateTime(2026, 10, 22): 2000},
        previousScore: 40,
      );
      final text = r.summary.join(' ');
      expect(text, contains('completed 2 of 2 planned workouts'));
      expect(text, contains('70 active minutes'));
      expect(text, contains('logged meals on 4 of 4 days'));
      expect(text, contains('close to your target of 2000'));
      expect(text, contains('up '));
      expect(r.focus, contains('keep the same rhythm'));
    });

    test('a week with nothing logged is described as it is, with a first step', () {
      final r = _week();
      final text = r.summary.join(' ');
      expect(text, contains('not logged a workout'));
      expect(text, contains('did not log any meals'));
      expect(r.focus, contains('planned workouts'));
    });

    test('eating far below the target is never praised', () {
      final r = _week(workouts: {DateTime(2026, 10, 19): 40, DateTime(2026, 10, 21): 40}, kcal: {for (var i = 19; i <= 22; i++) DateTime(2026, 10, i): 900});
      final text = r.summary.join(' ');
      expect(text, contains('well below'));
      expect(text, contains('not a safe way'));
      expect(text, isNot(contains('great')));
    });

    test('the focus follows the weakest part', () {
      expect(_week(workouts: {DateTime(2026, 10, 19): 30, DateTime(2026, 10, 21): 30}, kcal: {DateTime(2026, 10, 19): 2000}).focus, contains('log your meals'));
      final low = _week(workouts: {DateTime(2026, 10, 19): 30, DateTime(2026, 10, 21): 30}, kcal: {for (var i = 19; i <= 22; i++) DateTime(2026, 10, i): 2000}, sessions: [_session(DateTime(2026, 10, 20, 9), posture: 50)]);
      expect(low.focus, contains('form'));
    });
  });

  group('the workout heatmap', () {
    test('shade levels follow the minutes', () {
      expect(ActivityReports.intensityFor(0, done: false), 0);
      expect(ActivityReports.intensityFor(0, done: true), 1); // done but no minutes recorded
      expect(ActivityReports.intensityFor(19, done: true), 1);
      expect(ActivityReports.intensityFor(20, done: true), 2);
      expect(ActivityReports.intensityFor(40, done: true), 3);
      expect(ActivityReports.intensityFor(60, done: true), 4);
    });

    test('12 weeks of 7 days, Monday first, ending with this week, future days marked', () {
      final h = ActivityReports.heatmap(today: _today, activity: _act({DateTime(2026, 10, 19): 45, DateTime(2026, 10, 21): 15}));
      expect(h.length, 12);
      expect(h.every((w) => w.length == 7), isTrue);
      expect(h.first.first.date, DateTime(2026, 8, 3));
      expect(h.every((w) => w.first.date.weekday == DateTime.monday), isTrue);
      final thisWeek = h.last;
      expect(thisWeek[0].level, 3);
      expect(thisWeek[2].level, 1);
      expect(thisWeek[1].level, 0);
      expect(thisWeek[3].future, isFalse); // today
      expect(thisWeek[4].future, isTrue);
    });
  });

  group('the history list', () {
    test('groups sessions by day, newest first, and keeps days with no detail', () {
      final h = ActivityReports.history(
        from: DateTime(2026, 10, 1),
        to: _today,
        activity: _act({DateTime(2026, 10, 20): 30, DateTime(2026, 10, 15): 20, DateTime(2026, 9, 1): 99}),
        sessions: [_session(DateTime(2026, 10, 20, 8), id: 'a', name: 'Squat', posture: 80), _session(DateTime(2026, 10, 20, 9), id: 'b', name: 'Plank', posture: 60), _session(DateTime(2026, 10, 18, 7), id: 'c', name: 'Lunge', minutes: 12)],
      );
      expect(h.map((d) => d.date), [DateTime(2026, 10, 20), DateTime(2026, 10, 18), DateTime(2026, 10, 15)]);
      expect(h[0].entries.map((e) => e.exerciseName), ['Squat', 'Plank']);
      expect(h[0].minutes, 30);
      expect(h[0].avgPosture, 70);
      expect(h[1].minutes, 12); // no activity record: the session length is used
      expect(h[2].entries, isEmpty);
      final (days, minutes) = ActivityReports.totals(h);
      expect((days, minutes), (3, 62));
    });
  });

  group('body measurements', () {
    test('entries are checked in centimetres', () {
      expect(MeasurementService.problem('', 'Waist'), isNull);
      expect(MeasurementService.problem('82,5', 'Waist'), isNull);
      expect(MeasurementService.problem('abc', 'Waist'), contains('number'));
      expect(MeasurementService.problem('5', 'Waist'), contains('between'));
      expect(MeasurementService.problem('301', 'Waist'), contains('between'));
      expect(MeasurementService.parse('82,5'), 82.5);
      expect(MeasurementService.parse(' '), isNull);
    });

    test('change runs from the first to the last entry that has the site', () {
      final e = [BodyMeasurement(DateTime(2026, 8, 1), waistCm: 90, armCm: 30), BodyMeasurement(DateTime(2026, 9, 1), waistCm: 88), BodyMeasurement(DateTime(2026, 10, 1), waistCm: 85.5)];
      expect(MeasurementService.change(e, 'Waist'), -4.5);
      expect(MeasurementService.change(e, 'Arm'), isNull); // one entry only
      expect(MeasurementService.change(e, 'Hips'), isNull);
      expect(BodyMeasurement(DateTime(2026, 1, 1)).isEmpty, isTrue);
    });
  });

  group('the screens', () {
    testWidgets('weekly report shows the figures and the summary, and switches to the last 30 days', (tester) async {
      await _pump(tester, WeeklyReportScreen(loader: () async => _inputs(workouts: {DateTime(2026, 10, 19): 40, DateTime(2026, 10, 21): 30, DateTime(2026, 9, 25): 45}, kcal: {DateTime(2026, 10, 20): 2000})));
      expect(find.text('Workouts done'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.textContaining('completed 2 of 2 planned workouts'), findsOneWidget);
      expect(find.textContaining('not by an AI model'), findsOneWidget);
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last 30 days: summary'), findsOneWidget);
    });

    testWidgets('workout history shows the heatmap and cards, and a tapped day shows only that day', (tester) async {
      final inputs = _inputs(workouts: {DateTime(2026, 10, 20): 45, DateTime(2026, 10, 15): 20}, sessions: [_session(DateTime(2026, 10, 20, 8), name: 'Goblet squat', posture: 82), _session(DateTime(2026, 10, 15, 8), id: 'p', name: 'Push-up')]);
      await _pump(tester, WorkoutHistoryScreen(loader: () async => inputs));
      expect(find.textContaining('2 workout days, 65 active minutes'), findsOneWidget);
      expect(find.text('Goblet squat'), findsOneWidget);
      expect(find.text('Push-up'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('Tue 20 Oct: 45 minutes')));
      await tester.pumpAndSettle();
      expect(find.text('Goblet squat'), findsOneWidget);
      expect(find.text('Push-up'), findsNothing);
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('Push-up'), findsOneWidget);
    });

    testWidgets('workout history with nothing says what to do', (tester) async {
      await _pump(tester, WorkoutHistoryScreen(loader: () async => _inputs()));
      expect(find.textContaining('No workouts in the last 12 weeks'), findsOneWidget);
    });

    testWidgets('progress tracker checks the entries and saves valid ones', (tester) async {
      final saved = <BodyMeasurement>[];
      await _pump(
        tester,
        ProgressTrackerScreen(
          loader: () async => ProgressTrackerData(const [], [BodyMeasurement(DateTime(2026, 9, 1), waistCm: 90), BodyMeasurement(DateTime(2026, 10, 1), waistCm: 86)], null),
          onSave: (m) async => saved.add(m),
        ),
      );
      expect(find.text('-4.0 cm'), findsOneWidget);
      expect(find.textContaining('Progress photos are not part of this version'), findsOneWidget);
      await tester.tap(find.text('Add measurements'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Waist (cm), optional'), 'abc');
      await tester.enterText(find.widgetWithText(TextField, 'Chest (cm), optional'), '500');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('must be a number'), findsOneWidget);
      expect(find.textContaining('between 10 and 300'), findsOneWidget);
      expect(saved, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Waist (cm), optional'), '84,5');
      await tester.enterText(find.widgetWithText(TextField, 'Chest (cm), optional'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.single.waistCm, 84.5);
      expect(saved.single.chestCm, isNull);
    });

    testWidgets('saving with every box empty asks for a measurement', (tester) async {
      var calls = 0;
      await _pump(tester, ProgressTrackerScreen(loader: () async => const ProgressTrackerData([], [], null), onSave: (m) async => calls++));
      await tester.tap(find.text('Add measurements'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter at least one measurement.'), findsOneWidget);
      expect(calls, 0);
    });
  });
}

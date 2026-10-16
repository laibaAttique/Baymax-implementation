import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/specialist_plan.dart';
import 'package:app/screens/diet/daily_summary_screen.dart';
import 'package:app/services/specialist_plan_apply.dart';
import 'package:app/services/user_session.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/specialist_plan_banner.dart';

const _by = {'name': 'Sara Khan', 'role': 'nutritionist'};
const _trainer = {'name': 'Ali Raza', 'role': 'trainer'};
final _at = DateTime(2026, 10, 19).millisecondsSinceEpoch;

Exercise _ex(String id, {String group = 'legs', bool timed = false}) => Exercise(
      id: id,
      name: id,
      icon: '',
      group: group,
      muscles: const [],
      impact: 'low',
      level: 1,
      met: 4,
      steps: const [],
      timed: timed,
      baseReps: 12,
      baseSeconds: 30,
    );

final _library = {for (final e in [_ex('warmup', group: 'mobility', timed: true), _ex('cooldown', group: 'mobility', timed: true), _ex('squat'), _ex('walk', group: 'cardio', timed: true), _ex('pushup', group: 'push')]) e.id: e};

NutritionPlan _nutrition() => const NutritionPlan(
      goalLabel: 'Lose weight',
      targetKcal: 2000,
      proteinG: 110,
      carbsG: 230,
      fatG: 65,
      waterLitres: 2.5,
      meals: {},
      avoid: ['Sugary drinks'],
      tips: ['Walk after meals'],
      tipPool: ['x'],
      calorieNote: 'Baymax estimate',
    );

PersonalizedPlan _base() => PersonalizedPlan(
      category: 'Normal',
      intensity: 'Moderate',
      variant: 0,
      week: [
        WorkoutDay(name: 'Baymax day', focus: 'Full body', exercises: [PlannedExercise(exercise: _library['squat']!, sets: 3, reps: 10, seconds: 0, restSeconds: 45)]),
        null,
        null,
        null,
        null,
        null,
        null,
      ],
      restrictionNotes: const ['Low impact only'],
      nutrition: _nutrition(),
    );

PersonalizedPlan _apply(PersonalizedPlan base, SpecialistPlans plans, {PlanChoices choices = PlanChoices.defaults}) => applySpecialistPlans(
      base,
      plans,
      choices,
      exercise: (id) => _library[id],
      warmUp: _library['warmup']!,
      coolDown: _library['cooldown']!,
    );

Map<String, Object?> _dietJson({String status = 'modified', Map<String, Object?> more = const {}}) =>
    {'status': status, 'note': 'Follow for 4 weeks', 'by': _by, 'at': _at, 'avoid': <String>[], 'tips': <String>[], ...more};

Map<String, Object?> _day(int d, [List<Map<String, Object?>>? items]) => {'day': d, 'rest': items == null, 'items': items ?? <Object>[]};

Map<String, Object?> _workoutJson({List<Map<String, Object?>>? schedule, String status = 'modified'}) => {
      'status': status,
      'note': 'Build slowly',
      'by': _trainer,
      'at': _at,
      'schedule': schedule ??
          [
            _day(1, [{'exerciseId': 'walk', 'sets': 1, 'seconds': 900}]),
            _day(2),
            _day(3, [{'exerciseId': 'squat', 'sets': 3, 'reps': 15, 'note': 'Slow down'}, {'exerciseId': 'unknown_move', 'sets': 2, 'reps': 5}]),
            _day(4),
            _day(5, [{'exerciseId': 'pushup', 'sets': 2, 'reps': 8}]),
            _day(6),
            _day(7),
          ],
    };

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: SingleChildScrollView(child: w))));
  await tester.pumpAndSettle();
}

void main() {
  group('reading plans from the database', () {
    test('a diet plan keeps what was set and ignores impossible numbers', () {
      final p = SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 1900, 'proteinG': 120, 'carbsG': 210, 'fatG': 60, 'avoid': ['Fried foods', ' '], 'tips': ['Drink water']}))!;
      expect(p.approvedAsIs, isFalse);
      expect(p.targetKcal, 1900);
      expect(p.hasMacros, isTrue);
      expect(p.avoid, ['Fried foods']);
      expect(p.by.label, 'Sara Khan, Nutritionist');
      expect(SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 100}))!.targetKcal, isNull); // below the safe floor
      expect(SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 9000}))!.targetKcal, isNull);
      // a partial set of macros is not half applied
      final partial = SpecialistDietPlan.fromJson(_dietJson(more: {'proteinG': 100, 'carbsG': 200}))!;
      expect(partial.hasMacros, isFalse);
      expect(partial.proteinG, isNull);
    });

    test('records without an author or with an unknown status are ignored', () {
      expect(SpecialistDietPlan.fromJson({'status': 'modified', 'at': 1}), isNull);
      expect(SpecialistDietPlan.fromJson({..._dietJson(), 'status': 'weird'}), isNull);
      expect(SpecialistDietPlan.fromJson('nope'), isNull);
      expect(SpecialistWorkoutPlan.fromJson({..._workoutJson(), 'by': null}), isNull);
    });

    test('a workout plan needs all seven days and at least one training day, or it is ignored', () {
      expect(SpecialistWorkoutPlan.fromJson(_workoutJson()), isNotNull);
      expect(SpecialistWorkoutPlan.fromJson(_workoutJson(schedule: [_day(1)])), isNull);
      expect(SpecialistWorkoutPlan.fromJson(_workoutJson(schedule: [for (var d = 1; d <= 7; d++) _day(d)])), isNull);
      final approved = SpecialistWorkoutPlan.fromJson(_workoutJson(status: 'approved', schedule: const []))!;
      expect(approved.approvedAsIs, isTrue);
      expect(approved.schedule, isEmpty);
    });

    test('choices default to following the specialist, and respect an explicit "baymax"', () {
      expect(PlanChoices.fromJson(null).specialistDiet, isTrue);
      final c = PlanChoices.fromJson({'diet': 'baymax', 'workout': 'specialist'});
      expect(c.specialistDiet, isFalse);
      expect(c.specialistWorkout, isTrue);
    });

    test('a food log verdict is read with its reviewer and note', () {
      final r = DietReview.fromJson('2026-10-18', {'status': 'flagged', 'note': 'Too much fried food', 'by': {'name': 'Sara Khan'}, 'at': _at})!;
      expect(r.approved, isFalse);
      expect(r.reviewer, 'Sara Khan');
      expect(DietReview.fromJson('2026-10-18', {'status': 'maybe'}), isNull);
    });
  });

  group('putting a specialist\'s plan over the Baymax plan', () {
    final diet = SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 1800, 'proteinG': 120, 'carbsG': 200, 'fatG': 55, 'avoid': ['Fried foods'], 'tips': ['Drink water before meals']}))!;

    test('the specialist\'s calorie target and macros replace Baymax\'s, and their advice comes first', () {
      final out = _apply(_base(), SpecialistPlans(diet: diet));
      final n = out.nutrition;
      expect(n.targetKcal, 1800);
      expect([n.proteinG, n.carbsG, n.fatG], [120, 200, 55]);
      expect(n.avoid, ['Fried foods', 'Sugary drinks']);
      expect(n.tips.first, 'Sara Khan: Follow for 4 weeks');
      expect(n.tips[1], 'Sara Khan: Drink water before meals');
      expect(n.tips.last, 'Walk after meals'); // Baymax's own advice is kept
      expect(n.calorieNote, contains('Sara Khan, Nutritionist'));
      expect(n.calorieNote, contains('2000 kcal'));
      expect(out.week[0]!.name, 'Baymax day'); // the workout is untouched by a diet plan
      expect(out.restrictionNotes, ['Low impact only']);
    });

    test('only the numbers a specialist set are replaced', () {
      final onlyTips = SpecialistDietPlan.fromJson(_dietJson(more: {'tips': ['Eat slowly']}))!;
      final n = _apply(_base(), SpecialistPlans(diet: onlyTips)).nutrition;
      expect(n.targetKcal, 2000);
      expect(n.proteinG, 110);
      expect(n.calorieNote, 'Baymax estimate');
    });

    test('"approved as is" changes nothing in the plan', () {
      final approved = SpecialistDietPlan.fromJson(_dietJson(status: 'approved'))!;
      final base = _base();
      expect(identical(_apply(base, SpecialistPlans(diet: approved)), base), isTrue);
    });

    test('the member\'s choice to use Baymax\'s plan is respected', () {
      final base = _base();
      expect(identical(_apply(base, SpecialistPlans(diet: diet), choices: const PlanChoices(specialistDiet: false)), base), isTrue);
      final w = SpecialistWorkoutPlan.fromJson(_workoutJson())!;
      final out = _apply(base, SpecialistPlans(diet: diet, workout: w), choices: const PlanChoices(specialistDiet: false));
      expect(out.nutrition.targetKcal, 2000); // diet follows Baymax
      expect(out.week[2], isNotNull); // workout follows the specialist
    });

    test('a specialist\'s weekly schedule replaces the week, with warm-up and cool-down, rest days empty and unknown exercises skipped', () {
      final w = SpecialistWorkoutPlan.fromJson(_workoutJson())!;
      final out = _apply(_base(), SpecialistPlans(workout: w));
      expect(out.week.map((d) => d != null).toList(), [true, false, true, false, true, false, false]);
      final monday = out.week[0]!;
      expect(monday.exercises.first.exercise.id, 'warmup');
      expect(monday.exercises.last.exercise.id, 'cooldown');
      expect(monday.kind, 'Cardio'); // all cardio
      final walk = monday.exercises[1];
      expect(walk.seconds, 900);
      expect(walk.sets, 1);
      expect(walk.reasons.first, 'Set by Ali Raza, Trainer');
      final wednesday = out.week[2]!;
      expect(wednesday.exercises.length, 3); // warm-up, squat, cool-down: the unknown move was skipped, not guessed
      final squat = wednesday.exercises[1];
      expect(squat.reps, 15);
      expect(squat.sets, 3);
      expect(squat.reasons, ['Set by Ali Raza, Trainer', 'Slow down']);
      expect(wednesday.focus, 'Build slowly');
      expect(wednesday.kind, 'Strength');
      expect(out.nutrition.targetKcal, 2000); // a workout plan leaves the diet alone
      expect(out.workoutDays, 3);
    });

    test('a schedule whose exercises are all unknown leaves the Baymax week in place', () {
      final w = SpecialistWorkoutPlan.fromJson(_workoutJson(schedule: [
        _day(1, [{'exerciseId': 'ghost', 'sets': 1, 'reps': 5}]),
        for (var d = 2; d <= 7; d++) _day(d),
      ]))!;
      final base = _base();
      expect(identical(_apply(base, SpecialistPlans(workout: w)), base), isTrue);
    });

    test('with no specialist plans the plan is returned as it is', () {
      final base = _base();
      expect(identical(_apply(base, SpecialistPlans.none), base), isTrue);
    });
  });

  group('screens', () {
    tearDown(() {
      UserSession.instance.specialistPlans = SpecialistPlans.none;
      UserSession.instance.planChoices = PlanChoices.defaults;
    });

    testWidgets('the banner is absent when no specialist set a plan', (tester) async {
      await _pump(tester, const SpecialistPlanBanner(diet: true));
      expect(find.textContaining('by Sara'), findsNothing);
    });

    testWidgets('a diet banner names the specialist, shows their note and offers a way back to Baymax\'s plan', (tester) async {
      UserSession.instance.specialistPlans = SpecialistPlans(diet: SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 1800}))!);
      await _pump(tester, const SpecialistPlanBanner(diet: true));
      expect(find.text('Adjusted by Sara Khan, Nutritionist'), findsOneWidget);
      expect(find.textContaining('Follow for 4 weeks'), findsOneWidget);
      expect(find.textContaining('you are following their nutrition plan'), findsOneWidget);
      expect(find.text('Use Baymax\'s plan instead'), findsOneWidget);
      // a workout banner stays hidden: there is no workout plan
      await _pump(tester, const SpecialistPlanBanner(diet: false));
      expect(find.textContaining('Adjusted by'), findsNothing);
    });

    testWidgets('an approved plan says so and has no switch, since nothing was changed', (tester) async {
      UserSession.instance.specialistPlans = SpecialistPlans(workout: SpecialistWorkoutPlan.fromJson(_workoutJson(status: 'approved', schedule: const []))!);
      await _pump(tester, const SpecialistPlanBanner(diet: false));
      expect(find.text('Reviewed by Ali Raza, Trainer'), findsOneWidget);
      expect(find.textContaining('approved it as it is'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('switching back shows an error rather than pretending, when the choice cannot be saved', (tester) async {
      UserSession.instance.specialistPlans = SpecialistPlans(diet: SpecialistDietPlan.fromJson(_dietJson(more: {'targetKcal': 1800}))!);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: SpecialistPlanBanner(diet: true))));
      await tester.tap(find.text('Use Baymax\'s plan instead'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget); // Firebase is not available in tests, so saving fails and says so
      expect(UserSession.instance.planChoices.specialistDiet, isTrue); // and nothing changed
    });

    testWidgets('a food log verdict card shows approved and flagged days', (tester) async {
      await _pump(tester, DietReviewCard(review: DietReview(date: '2026-10-18', approved: false, note: 'Too much fried food', reviewer: 'Sara Khan', at: DateTime(2026, 10, 18))));
      expect(find.text('Flagged by Sara Khan'), findsOneWidget);
      expect(find.text('Too much fried food'), findsOneWidget);
      await _pump(tester, DietReviewCard(review: DietReview(date: '2026-10-19', approved: true, reviewer: 'Sara Khan', at: DateTime(2026, 10, 19))));
      expect(find.text('Approved by Sara Khan'), findsOneWidget);
    });

    testWidgets('the daily summary shows the nutritionist\'s verdict for that day', (tester) async {
      final data = DailySummaryData(
        date: DateTime(2026, 10, 19),
        entries: const [],
        burnedKcal: 0,
        weekKcal: List<double?>.filled(7, null),
        targetKcal: 2000,
        proteinTarget: 100,
        carbsTarget: 200,
        fatTarget: 60,
        goal: 'Maintain Weight',
        bmr: 1500,
        review: DietReview(date: '2026-10-19', approved: false, note: 'Add vegetables', reviewer: 'Sara Khan', at: DateTime(2026, 10, 19)),
      );
      tester.view.physicalSize = const Size(1170, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: DailySummaryScreen(date: DateTime(2026, 10, 19), loader: (_) async => data)));
      await tester.pumpAndSettle();
      expect(find.text('Flagged by Sara Khan'), findsOneWidget);
      expect(find.text('Add vegetables'), findsOneWidget);
    });
  });
}

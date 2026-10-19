import 'dart:io';
import 'dart:math';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/specialist_plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/screens/posture_detection/manual_guidance.dart';
import 'package:app/screens/posture_detection/posture_mode.dart';
import 'package:app/screens/workout_and_exercise/workout_plan.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/specialist_plan_apply.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Module 4, classification profiles (ledger phases K2–K7).

HealthProfile _person({
  List<String> conditions = const [],
  double weight = 70,
  double height = 170,
  String dob = '1995-06-01',
  String goal = 'Gain Muscle',
  String activity = 'Moderately Active',
  int freq = 4,
}) =>
    HealthProfile(
      fullName: 'Synthetic Person',
      dob: dob,
      gender: 'Female',
      heightValue: height,
      weightValue: weight,
      medicalConditions: conditions,
      primaryGoal: goal,
      activityLevel: activity,
      workoutFrequency: freq,
    );

ClassificationResult _cls(String category, {String risk = 'Moderate', List<String> factors = const []}) => ClassificationResult(
      category: category,
      riskLevel: risk,
      bmiCategory: 'Normal',
      bmi: 24,
      riskFactors: factors,
      rationale: '',
      method: 'test',
    );

Exercise _ex(String id, double met, {String group = 'legs', String compendium = '02022'}) =>
    Exercise(id: id, name: id, icon: '', group: group, muscles: const ['Quadriceps'], impact: 'low', level: 1, met: met, compendium: compendium, steps: const ['x']);

void main() {
  late FoodDatabase foods;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  PersonalizedPlan plan(HealthProfile p, {WorkoutReadiness? readiness, ClassificationResult? cls}) =>
      PlanGenerator(foods).generate(p, cls ?? const RuleBasedClassifier().classify(p), readiness: readiness);

  Iterable<PlannedExercise> scheduled(PersonalizedPlan p) => p.week.whereType<WorkoutDay>().expand((d) => d.exercises);

  group('K2 intensity bands', () {
    test('band boundaries follow WHO 2020 (light < 3, moderate 3–5.9, vigorous ≥ 6)', () {
      expect(IntensityBand.ofMet(2.99), IntensityBand.light);
      expect(IntensityBand.ofMet(3.0), IntensityBand.moderate);
      expect(IntensityBand.ofMet(5.99), IntensityBand.moderate);
      expect(IntensityBand.ofMet(6.0), IntensityBand.vigorous);
      expect(_ex('none', 0, compendium: '').intensityBand, isNull, reason: 'no MET, no band');
    });

    test('catalogue band counts match the dataset analysis (plan §1.4)', () {
      final counts = <IntensityBand?, int>{};
      for (final e in ExerciseCatalog.all) {
        counts[e.intensityBand] = (counts[e.intensityBand] ?? 0) + 1;
      }
      expect(counts[IntensityBand.light], 134);
      expect(counts[IntensityBand.moderate], 528);
      expect(counts[IntensityBand.vigorous], 125);
      expect(counts[null], 84);
      expect(ExerciseLibrary.all.every((e) => e.intensityBand != null), isTrue, reason: 'every curated exercise has a MET value');
    });
  });

  group('K3 profile repository', () {
    test('one profile per Module 2 category, cited, pending review; unknown categories get the conservative fallback', () {
      const categories = ['Healthy', 'Overweight', 'Obese', 'At-Risk', 'Diabetic', 'Cardiac'];
      for (final c in categories) {
        expect(ClassificationProfiles.all.where((p) => p.category == c), hasLength(1), reason: c);
      }
      expect(ClassificationProfiles.all, hasLength(categories.length));
      expect(ClassificationProfiles.forCategory('Something new').category, 'At-Risk');
      final ids = <String>{};
      for (final p in ClassificationProfiles.all) {
        expect(ids.add(p.id), isTrue);
        expect(p.reviewStatus, 'pending');
        expect(p.evidence, isNotEmpty);
        for (final k in p.evidence) {
          expect(SafetyRuleRepository.evidence.containsKey(k), isTrue, reason: '${p.id} cites $k');
        }
        expect(p.aerobicMin, 150, reason: 'WHO 2020 adult minimum');
        expect(p.strengthDays, greaterThanOrEqualTo(2));
      }
      for (final n in ClassificationProfiles.notes) {
        expect(ids.add(n.id), isTrue);
        expect(n.reviewStatus, 'pending');
        for (final k in n.evidence) {
          expect(SafetyRuleRepository.evidence.containsKey(k), isTrue, reason: '${n.id} cites $k');
        }
      }
      expect(ClassificationProfiles.forCategory('Cardiac').maxBand, IntensityBand.moderate);
      expect(ClassificationProfiles.forCategory('Healthy').maxBand, IntensityBand.vigorous);
      expect(ClassificationProfiles.forCategory('Diabetic').maxRestDaysInRow, 2);
    });

    test('risk level and statistical risk reach the facts', () {
      final f = HealthFacts.from(_person(), _cls('At-Risk', factors: const ['Statistical risk of diabetes (30% vs 11% average)']), 'Low');
      expect(f.statisticalRisk, isTrue);
      expect(f.test(const Pred(Fact.riskLevel, Op.eq, 'Moderate')), isTrue);
      expect(HealthFacts.from(_person(), _cls('Healthy'), 'Moderate').statisticalRisk, isFalse);
    });
  });

  group('K4 profile filter', () {
    final facts = HealthFacts.from(_person(), _cls('Cardiac'), 'Low');

    test('the cap excludes above-band work, keeps the rest, and unknown intensity is not treated as safe', () {
      final a = SafetyRuleRepository.engine.assess(facts, profile: ClassificationProfiles.forCategory('Obese'));
      final hard = a.decide(_ex('hard', 6.5));
      expect(hard.outcome, ExerciseOutcome.excluded);
      expect(hard.ruleIds, ['PRF-OBESE']);
      expect(a.decide(_ex('ok', 5.0)).schedulable, isTrue);
      expect(a.decide(_ex('easy', 2.0)).schedulable, isTrue);
      final unknown = a.decide(_ex('unknown', 0, compendium: ''));
      expect(unknown.outcome, ExerciseOutcome.requiresInformation);
      expect(unknown.schedulable, isFalse);
    });

    test('an uncapped profile changes nothing, and without a profile the assessment is the rule repository alone', () {
      final healthy = SafetyRuleRepository.engine.assess(HealthFacts.from(_person(), _cls('Healthy'), 'Moderate'),
          profile: ClassificationProfiles.forCategory('Healthy'));
      expect(healthy.decide(_ex('hard', 8.0)).outcome, ExerciseOutcome.eligible);
      final plain = SafetyRuleRepository.engine.assess(facts);
      expect(plain.maxBand, isNull);
      expect(plain.rulesVersion, SafetyRuleRepository.version);
    });

    test('a profile never relaxes a rule: 3,000 random people, every scheduled exercise passes the rules and the band cap', () {
      final rnd = Random(11);
      const conds = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity', 'PCOS'];
      const kit = ['dumbbell', 'kettlebell', 'bands', 'barbell', 'medicine_ball', 'exercise_ball', 'cable', 'machine'];
      const joints = ['knee', 'lowerBack', 'shoulder', 'wrist', 'ankle'];
      var vigorousSeen = false;
      for (var i = 0; i < 3000; i++) {
        final person = _person(
          conditions: [for (final c in conds) if (rnd.nextDouble() < 0.12) c],
          weight: 42 + rnd.nextDouble() * 90,
          height: 150 + rnd.nextDouble() * 40,
          dob: '${1940 + rnd.nextInt(66)}-03-03',
          goal: const ['Lose Weight', 'Gain Muscle', 'Maintain & Stay Fit'][rnd.nextInt(3)],
          activity: const ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active', 'Athlete'][rnd.nextInt(5)],
          freq: 2 + rnd.nextInt(5),
        );
        final readiness = WorkoutReadiness(
          clearance: rnd.nextDouble() < 0.8,
          equipment: {for (final k in kit) if (rnd.nextDouble() < 0.3) k},
          injuries: {for (final j in joints) if (rnd.nextDouble() < 0.1) j},
        );
        final cls = const RuleBasedClassifier().classify(person);
        final p = plan(person, readiness: readiness, cls: cls);
        if (!p.workoutAvailable) {
          expect(p.profile, isNull, reason: 'no week, no profile summary');
          continue;
        }
        final profile = ClassificationProfiles.forCategory(cls.category);
        final rulesOnly = SafetyRuleRepository.engine.assess(HealthFacts.from(person, cls, p.intensity, readiness: readiness));
        expect(p.profile!.profileId, profile.id);
        for (final e in scheduled(p)) {
          expect(rulesOnly.decide(e.exercise).schedulable, isTrue, reason: 'person $i: ${e.exercise.id} breaks a rule');
          final band = e.exercise.intensityBand;
          expect(band, isNotNull, reason: '${e.exercise.id} has no MET value');
          expect(band!.index, lessThanOrEqualTo(profile.maxBand.index), reason: 'person $i (${cls.category}): ${e.exercise.id} is ${band.name}');
          if (band == IntensityBand.vigorous) vigorousSeen = true;
        }
        if (profile.maxRestDaysInRow != null && rulesOnly.maxDays >= 3) {
          final days = [for (final d in p.week) d != null];
          expect(ClassificationProfiles.longestRest(days), lessThanOrEqualTo(profile.maxRestDaysInRow!), reason: 'person $i');
        }
      }
      expect(vigorousSeen, isTrue, reason: 'uncapped profiles still get vigorous work');
    });
  });

  group('K5 weekly structure', () {
    test('diabetes: two chosen days become three so no more than two rest days fall in a row; others keep their choice', () {
      final diabetic = plan(_person(conditions: ['Diabetes'], freq: 2), readiness: const WorkoutReadiness());
      expect(diabetic.workoutDays, 3);
      expect(ClassificationProfiles.longestRest([for (final d in diabetic.week) d != null]), lessThanOrEqualTo(2));
      expect(diabetic.profile!.notes.join(' '), contains('3 workout days instead of 2'));
      final healthy = plan(_person(freq: 2), readiness: const WorkoutReadiness());
      expect(healthy.workoutDays, 2);
    });

    test('longest rest counts across the end of the week', () {
      expect(ClassificationProfiles.longestRest([true, false, false, true, false, false, false]), 3);
      expect(ClassificationProfiles.longestRest([true, false, true, false, true, false, false]), 2);
      expect(ClassificationProfiles.longestRest(List.filled(7, false)), 7);
    });

    test('aerobic minutes are moderate-equivalent and a shortfall gives a concrete suggestion', () {
      final walk = ExerciseLibrary.byId('brisk_walk')!; // 3.8 MET, moderate
      final jacks = ExerciseLibrary.byId('jumping_jacks')!; // 7.5 MET, vigorous
      final week = List<WorkoutDay?>.filled(7, null);
      week[0] = WorkoutDay(name: 'A', focus: '', exercises: [
        PlannedExercise(exercise: walk, sets: 1, reps: 0, seconds: 600, restSeconds: 0),
        PlannedExercise(exercise: jacks, sets: 3, reps: 0, seconds: 60, restSeconds: 30),
      ]);
      final s = ClassificationProfiles.summarize(ClassificationProfiles.forCategory('Healthy'), week, null);
      expect(s.aerobicMinutes, 10 + 2 * 3);
      expect(s.aerobicMet, isFalse);
      expect(s.notes.single, contains('about 25 minutes on each day without a workout')); // (150 - 16) / 6 rest days = 22.3, rounded up to 5-minute steps
    });

    test('statistical-risk, PCOS and high-risk explanations appear only for those people', () {
      final stat = plan(_person(), readiness: const WorkoutReadiness(),
          cls: _cls('At-Risk', factors: const ['Statistical risk of heart disease (9% vs 4% average)']));
      expect(stat.profile!.notes.join(' '), contains('PN-STAT-RISK'));
      expect(stat.profile!.profileId, 'PRF-AT-RISK');
      final pcos = plan(_person(conditions: ['PCOS']), readiness: const WorkoutReadiness());
      expect(pcos.profile!.notes.join(' '), contains('PN-PCOS'));
      final healthy = plan(_person(), readiness: const WorkoutReadiness());
      expect(healthy.profile!.notes.join(' '), isNot(contains('PN-')));
      final diabetic = plan(_person(conditions: ['Diabetes']), readiness: const WorkoutReadiness());
      expect(diabetic.profile!.notes.join(' '), contains('PN-RISK-HIGH'));
    });

    test('same inputs give the same plan and summary', () {
      final a = plan(_person(conditions: ['Hypertension'], goal: 'Lose Weight'), readiness: const WorkoutReadiness(equipment: {'dumbbell'}));
      final b = plan(_person(conditions: ['Hypertension'], goal: 'Lose Weight'), readiness: const WorkoutReadiness(equipment: {'dumbbell'}));
      expect(scheduled(a).map((e) => '${e.exercise.id}:${e.sets}x${e.reps}/${e.seconds}').toList(),
          scheduled(b).map((e) => '${e.exercise.id}:${e.sets}x${e.reps}/${e.seconds}').toList());
      expect(a.profile!.aerobicMinutes, b.profile!.aerobicMinutes);
      expect(a.profile!.notes, b.profile!.notes);
    });
  });

  group('K7 versions and specialist plans', () {
    test('the plan records both the rule and the profile versions', () {
      final p = plan(_person(), readiness: const WorkoutReadiness());
      expect(p.rulesVersion, '${SafetyRuleRepository.version}+${ClassificationProfiles.version}');
    });

    test('a specialist week is measured against the same profile', () {
      final base = plan(_person(conditions: ['Hypertension']), readiness: const WorkoutReadiness());
      final squat = ExerciseLibrary.byId('squat')!;
      final applied = applySpecialistPlans(
        base,
        SpecialistPlans(
          workout: SpecialistWorkoutPlan(
            approvedAsIs: false,
            by: const PlanAuthor('Test Trainer', 'trainer'),
            at: DateTime(2026, 10, 17),
            schedule: [SpecialistWorkoutDay(day: 1, rest: false, items: [SpecialistExercise(exerciseId: squat.id, sets: 3, reps: 10)])],
          ),
        ),
        const PlanChoices(),
        exercise: ExerciseLibrary.byId,
        warmUp: ExerciseLibrary.warmUp,
        coolDown: ExerciseLibrary.coolDown,
      );
      expect(applied.profile!.profileId, base.profile!.profileId);
      expect(applied.profile!.strengthDays, 1);
      expect(applied.profile!.notes.first, contains('set by your specialist'));
    });
  });

  group('Module 4 → Module 5 hand-off', () {
    test('the safety adaptations travel with the exercise and with the exercises up next', () {
      final p = plan(_person(conditions: ['Hypertension']), readiness: const WorkoutReadiness(injuries: {'knee'}));
      final day = p.week.whereType<WorkoutDay>().first;
      final adapted = day.exercises.firstWhere((e) => e.ruleNotes.isNotEmpty);
      final i = day.exercises.indexOf(adapted);
      final req = WorkoutSessionRequest.fromPlanned(day.exercises.first, upNext: day.exercises.sublist(1));
      expect(SessionExercise.fromPlanned(adapted).safetyNotes, adapted.ruleNotes);
      if (i > 0) expect(req.upNext[i - 1].safetyNotes, adapted.ruleNotes);
      expect(SessionExercise.fromExercise(adapted.exercise).safetyNotes, isEmpty, reason: 'outside a plan nothing is claimed');
    });

    test('no profile cap removes an exercise that camera detection supports', () {
      for (final id in ['squat', 'chair_squat', 'pushup', 'knee_pushup']) {
        expect(ExerciseFormRules.supports(id), isTrue, reason: id);
        final e = ExerciseLibrary.byId(id)!;
        for (final p in ClassificationProfiles.all) {
          final a = SafetyRuleRepository.engine.assess(HealthFacts.from(_person(), _cls(p.category), 'Low'), profile: p);
          expect(a.decide(e).schedulable, isTrue, reason: '$id under ${p.id}');
        }
      }
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
      await tester.pumpAndSettle();
    }

    const adapted = SessionExercise(
      id: 'squat',
      name: 'Squat',
      sets: 2,
      reps: 10,
      steps: ['Stand tall'],
      safetyNotes: ['Loads your knee: use a smaller, pain-free range and stop if it hurts (INJ-KNEE)'],
    );

    testWidgets('mode selection and manual guidance show the adaptations', (tester) async {
      await pump(tester, const PostureModeSelection(request: WorkoutSessionRequest(exercise: adapted)));
      expect(find.text('Adapted for you'), findsOneWidget);
      expect(find.textContaining('INJ-KNEE'), findsOneWidget);
      // The guided session runs a clock, so it never settles: pump a fixed time instead.
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const ManualGuidance(request: WorkoutSessionRequest(exercise: adapted))));
      await tester.pump(const Duration(milliseconds: 500));
      final notes = find.byKey(const ValueKey('safety-notes'));
      await tester.scrollUntilVisible(notes, 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('INJ-KNEE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // dispose the session and its timer
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing extra is shown when nothing was adapted', (tester) async {
      await pump(tester, const PostureModeSelection(request: WorkoutSessionRequest(exercise: SessionExercise(id: 'squat', name: 'Squat'))));
      expect(find.text('Adapted for you'), findsNothing);
    });
  });

  group('K6 workout tab', () {
    tearDown(() => UserSession.instance.clear());

    testWidgets('the training profile card shows the classification, intensity cap and weekly targets', (tester) async {
      UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
      await tester.runAsync(() => UserSession.instance.setProfile(_person(conditions: ['Heart Disease'], goal: 'Lose Weight')));
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const WorkoutPlan()));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('training-profile'));
      await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Your training profile: Cardiac'), findsOneWidget);
      expect(find.textContaining('Highest intensity scheduled: Moderate'), findsOneWidget);
      expect(find.textContaining('Aerobic'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

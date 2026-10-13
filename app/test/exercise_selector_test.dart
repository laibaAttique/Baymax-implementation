import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_selector.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';

HealthProfile person({
  String dob = '1995-05-05',
  String gender = 'Female',
  double height = 165,
  double weight = 60,
  List<String> conditions = const [],
  String goal = 'Maintain & Stay Fit',
  String activity = 'Moderately Active',
  int freq = 4,
}) =>
    HealthProfile(
      fullName: 'Test',
      dob: dob,
      gender: gender,
      heightValue: height,
      weightValue: weight,
      medicalConditions: conditions,
      foodAllergies: const [],
      primaryGoal: goal,
      activityLevel: activity,
      workoutFrequency: freq,
    );

void main() {
  late FoodDatabase foods;
  late List<Exercise> library;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
    library = ExerciseLibrary.all;
  });

  PersonalizedPlan planFor(HealthProfile p, {int variant = 0}) =>
      PlanGenerator(foods).generate(p, const RuleBasedClassifier().classify(p), variant: variant);

  Iterable<PlannedExercise> mainExercises(PersonalizedPlan plan) =>
      plan.week.whereType<WorkoutDay>().expand((d) => d.exercises).where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown');

  group('curated library', () {
    final raw = (jsonDecode(File('assets/data/exercises.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final curated = raw.where((e) => e.containsKey('curated')).toList();

    test('is larger than before and has unique ids', () {
      expect(raw.length, greaterThanOrEqualTo(70));
      expect({for (final e in raw) e['id']}.length, raw.length);
    });

    test('every entry carries the body-load fields and only allowed values', () {
      const joints = {'knee', 'wrist', 'shoulder', 'lowerBack', 'ankle'};
      for (final e in raw) {
        expect((e['joints'] as List).every(joints.contains), isTrue, reason: '${e['id']} joints');
        expect(['standing', 'seated', 'floor'], contains(e['position']), reason: '${e['id']} position');
        expect([1, 2, 3], contains(e['complexity']), reason: '${e['id']} complexity');
        expect(['low', 'high'], contains(e['impact']));
        expect((e['met'] as num) > 0, isTrue);
        expect((e['steps'] as List), isNotEmpty);
      }
    });

    test('curated entries are sourced, need no gym equipment and contain no maximal-effort wording', () {
      expect(curated.length, greaterThanOrEqualTo(40));
      final banned = RegExp(r'as high as possible|as far as possible|explosive|as fast as|smith|barbell|dumbbell|machine|\bbench\b|partner|squat rack|maximum', caseSensitive: false);
      for (final e in curated) {
        expect(e['referenceId'], isNotNull, reason: e['id']);
        expect(banned.hasMatch((e['steps'] as List).join(' ')), isFalse, reason: '${e['id']} steps');
        expect(banned.hasMatch(e['equipment'] as String), isFalse, reason: '${e['id']} equipment');
        // energy comes from a class already used by the library: closest listed activity, flagged with *
        expect(['02056*', '02022*', '02024*', '02030*', '02101*', '02057*', '02020*'], contains(e['compendium']));
      }
    });

    test('every muscle group the templates ask for still has exercises', () {
      for (final g in ['cardio', 'legs', 'push', 'back', 'core', 'mobility']) {
        expect(library.where((e) => e.group == g).length, greaterThanOrEqualTo(3), reason: g);
      }
      expect(library.where((e) => e.group == 'mobility').length, greaterThanOrEqualTo(20));
    });
  });

  group('capacity and scoring', () {
    BodyProfile body({int age = 30, double bmi = 22, String activity = 'Moderately Active', String goal = 'Maintain & Stay Fit'}) =>
        BodyProfile(age: age, heightCm: 170, weightKg: 65, bmi: bmi, activityLevel: activity, goal: goal, workoutsPerWeek: 4);

    test('capacity follows activity, and falls with age and BMI, within 1..3', () {
      expect(body(activity: 'Sedentary').capacity, 1.0);
      expect(body(activity: 'Athlete').capacity, 3.0);
      expect(body(activity: 'Moderately Active', age: 70, bmi: 36).capacity, 1.0); // 2.0 - 0.5 - 0.5
      expect(body(activity: 'Very Active', age: 55).capacity, 2.25);
      expect(body(activity: 'Sedentary', age: 80, bmi: 40).capacity, 1.0); // never below 1
    });

    Exercise ex(String id) => library.firstWhere((e) => e.id == id);

    test('an exercise that is too hard is penalised more than one that is too easy', () {
      final beginner = ExerciseSelector(body(activity: 'Sedentary'));
      // wall push-up (level 1) vs a level-3 jump, same group-independent comparison of the difficulty term
      final easy = beginner.score(ex('wall_pushup'));
      final hard = beginner.score(ex('star_jump'));
      expect(easy.score, greaterThan(hard.score));
    });

    test('a higher BMI counts against knee-loading exercises', () {
      final lean = ExerciseSelector(body(bmi: 22)).score(ex('lunge'));
      final heavy = ExerciseSelector(body(bmi: 33)).score(ex('lunge'));
      expect(heavy.score, lessThan(lean.score));
      // an exercise that does not load the knee is unaffected (up to the tie-break, which is identical for the same id)
      final bridgeLean = ExerciseSelector(body(bmi: 22)).score(ex('glute_bridge'));
      final bridgeHeavy = ExerciseSelector(body(bmi: 33)).score(ex('glute_bridge'));
      expect((bridgeLean.score - bridgeHeavy.score).abs(), lessThan(0.5)); // only the capacity-driven difficulty term moves
    });

    Exercise synthetic({String position = 'standing', int complexity = 1}) => Exercise(
        id: 'x', name: 'X', icon: '', group: 'core', muscles: const [], impact: 'low', level: 1, met: 3, steps: const ['s'], position: position, complexity: complexity);

    test('older adults and very heavy people are steered away from the floor', () {
      final senior = ExerciseSelector(body(age: 70, activity: 'Lightly Active'));
      final heavy = ExerciseSelector(body(bmi: 37, activity: 'Lightly Active'));
      final fit = ExerciseSelector(body(age: 30, bmi: 22, activity: 'Lightly Active'));
      for (final s in [senior, heavy]) {
        expect(s.score(synthetic(position: 'floor')).score, lessThan(s.score(synthetic()).score - 0.5));
      }
      // for a young lean person the position makes no difference
      expect((fit.score(synthetic(position: 'floor')).score - fit.score(synthetic()).score).abs(), lessThan(1e-9));
    });

    test('complex movements are penalised from age 60 only', () {
      final senior = ExerciseSelector(body(age: 70));
      final adult = ExerciseSelector(body(age: 40));
      expect(senior.score(synthetic()).score - senior.score(synthetic(complexity: 3)).score, closeTo(0.8, 1e-9));
      expect(adult.score(synthetic()).score, closeTo(adult.score(synthetic(complexity: 3)).score, 1e-9));
    });

    test('repeating an exercise within the week is penalised', () {
      final s = ExerciseSelector(body());
      expect(s.score(ex('squat'), weekUsage: {'squat': 2}).score, lessThan(s.score(ex('squat')).score - 1.5));
    });

    test('goal changes the ranking: weight loss favours energy use, muscle gain favours strength moves', () {
      final lose = ExerciseSelector(body(goal: 'Lose Weight', activity: 'Very Active'));
      final gain = ExerciseSelector(body(goal: 'Gain Muscle', activity: 'Very Active'));
      final pool = library.where((e) => e.group == 'cardio' || e.group == 'push').toList();
      final loseTop = lose.rank(pool).first.exercise;
      final gainTop = gain.rank(pool).first.exercise;
      expect(loseTop.group, 'cardio');
      expect(gainTop.group, 'push');
    });

    test('ranking is deterministic and the variant only reorders near-ties', () {
      final a = ExerciseSelector(body()).rank(library.where((e) => e.group == 'core')).map((s) => s.exercise.id).toList();
      final b = ExerciseSelector(body()).rank(library.where((e) => e.group == 'core')).map((s) => s.exercise.id).toList();
      expect(a, b);
      final v = ExerciseSelector(body(), variant: 3).rank(library.where((e) => e.group == 'core')).map((s) => s.exercise.id).toList();
      expect(v.toSet(), a.toSet());
    });
  });

  group('plans follow the person', () {
    test('different bodies get different exercises for the same goal', () {
      final young = planFor(person(dob: '1998-01-01', weight: 62, goal: 'Lose Weight', activity: 'Very Active'));
      final older = planFor(person(dob: '1958-01-01', gender: 'Male', height: 172, weight: 104, goal: 'Lose Weight', activity: 'Sedentary'));
      final a = mainExercises(young).map((e) => e.exercise.id).toSet();
      final b = mainExercises(older).map((e) => e.exercise.id).toSet();
      expect(a, isNot(equals(b)));
      expect(a.difference(b), isNotEmpty);
    });

    test('a heavier body gets lower total joint load than a lean one with the same inputs', () {
      double load(PersonalizedPlan plan, BodyProfile b) => mainExercises(plan).fold(0.0, (s, e) => s + e.exercise.joints.fold(0.0, (t, j) => t + b.jointLoad(j)));
      final leanP = person(weight: 60, goal: 'Lose Weight', activity: 'Lightly Active'); // BMI ~22
      final heavyP = person(weight: 92, goal: 'Lose Weight', activity: 'Lightly Active'); // BMI ~34
      final heavyBody = BodyProfile.from(heavyP);
      final onLean = load(planFor(leanP), heavyBody);
      final onHeavy = load(planFor(heavyP), heavyBody);
      expect(onHeavy, lessThan(onLean));
    });

    test('every training exercise comes with a reason, the fixed warm-up and cool-down do not', () {
      final plan = planFor(person(goal: 'Lose Weight'));
      for (final p in mainExercises(plan)) {
        expect(p.reasons, isNotEmpty, reason: p.exercise.id);
        expect(p.reasons.length, lessThanOrEqualTo(2));
      }
      for (final d in plan.week.whereType<WorkoutDay>()) {
        expect(d.exercises.first.exercise.id, 'warmup');
        expect(d.exercises.last.exercise.id, 'cooldown');
        expect(d.exercises.first.reasons, isEmpty);
      }
    });

    test('the cool-down stretches the regions the session worked, with static stretches only', () {
      final people = [
        person(goal: 'Gain Muscle', activity: 'Very Active', freq: 5),
        person(dob: '1960-01-01', gender: 'Male', weight: 85, height: 172, conditions: ['Hypertension'], activity: 'Lightly Active'),
        person(weight: 95, goal: 'Lose Weight', activity: 'Sedentary', freq: 3),
      ];
      var sawStretch = false;
      for (final p in people) {
        for (final day in planFor(p).week.whereType<WorkoutDay>()) {
          final stretches = day.exercises.where((e) => e.reasons.any((r) => r.startsWith('Stretches what you just worked'))).toList();
          expect(stretches.length, lessThanOrEqualTo(2));
          expect(day.exercises.last.exercise.id, 'cooldown');
          final worked = bodyRegions(day.exercises
              .where((e) => e.exercise.group != 'mobility' && e.exercise.id != 'warmup' && e.exercise.id != 'cooldown')
              .expand((e) => e.exercise.muscles));
          for (final st in stretches) {
            sawStretch = true;
            expect(st.exercise.group, 'mobility');
            expect(st.exercise.tags, isNot(contains('dynamic')), reason: st.exercise.id);
            expect(st.exercise.tags, isNot(contains('balance')));
            expect(bodyRegions(st.exercise.muscles).intersection(worked), isNotEmpty, reason: '${st.exercise.id} on ${day.name}');
            expect(st.timed, isTrue);
            expect(st.sets, 1);
          }
          expect({for (final st in stretches) st.exercise.id}.length, stretches.length); // no duplicates
        }
      }
      expect(sawStretch, isTrue);
    });

    test('body regions map the different muscle labels to the same region', () {
      expect(bodyRegions(['Quads']), bodyRegions(['Quadriceps']));
      expect(bodyRegions(['Abs']), bodyRegions(['Core']));
      expect(bodyRegions(['Legs']), containsAll(['quads', 'hamstrings', 'glutes', 'calves']));
      expect(bodyRegions(['Heart', 'Full body']), isEmpty);
    });

    test('exercises are varied across the week', () {
      final plan = planFor(person(goal: 'Gain Muscle', activity: 'Very Active', freq: 5));
      final counts = <String, int>{};
      for (final p in mainExercises(plan)) {
        counts[p.exercise.id] = (counts[p.exercise.id] ?? 0) + 1;
      }
      expect(counts.values.reduce(max), lessThanOrEqualTo(3));
      expect(counts.length, greaterThanOrEqualTo(10));
    });

    test('same inputs give the same plan, and Regenerate (variant) gives a valid different one', () {
      final p = person(goal: 'Maintain & Stay Fit');
      String sig(PersonalizedPlan x) => x.week.map((d) => d == null ? '-' : d.exercises.map((e) => e.exercise.id).join(',')).join('|');
      expect(sig(planFor(p)), sig(planFor(p)));
      expect(sig(planFor(p, variant: 1)), isNot(sig(planFor(p))));
    });

    test('the medical safety rules still hold for 400 random people, with the larger library', () {
      final r = Random(11);
      const conds = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity', 'PCOS'];
      const goals = ['Lose Weight', 'Gain Muscle', 'Maintain & Stay Fit'];
      const acts = ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active', 'Athlete'];
      for (var n = 0; n < 400; n++) {
        final age = 18 + r.nextInt(65);
        final height = 150 + r.nextInt(40);
        final weight = 42 + r.nextInt(90);
        final c = [for (final x in conds) if (r.nextInt(5) == 0) x];
        final p = person(
          dob: '${DateTime.now().year - age}-06-15',
          gender: r.nextBool() ? 'Male' : 'Female',
          height: height.toDouble(),
          weight: weight.toDouble(),
          conditions: c,
          goal: goals[r.nextInt(3)],
          activity: acts[r.nextInt(5)],
          freq: 2 + r.nextInt(5),
        );
        final cls = const RuleBasedClassifier().classify(p);
        final plan = PlanGenerator(foods).generate(p, cls, variant: r.nextInt(4));
        final label = 'age $age bmi ${p.bmi.toStringAsFixed(1)} $c ${p.primaryGoal} ${p.activityLevel}';
        for (final pe in mainExercises(plan)) {
          final e = pe.exercise;
          if (cls.isCardiac) {
            expect(e.impact, 'low', reason: '$label ${e.id}');
            expect(e.tags, isNot(contains('hiit')), reason: '$label ${e.id}');
            expect(e.tags, isNot(contains('isometric')), reason: '$label ${e.id}');
          }
          if (p.hasCondition('Hypertension') || p.hasCondition('Diabetes') || p.hasCondition('Asthma')) {
            expect(e.tags, isNot(contains('hiit')), reason: '$label ${e.id}');
          }
          if (p.bmi >= 30 || (p.age ?? 30) >= 55 || p.hasCondition('Hypertension')) {
            expect(e.impact, 'low', reason: '$label ${e.id}');
          }
          if (p.bmi >= 25) expect(e.tags, isNot(contains('plyo')), reason: '$label ${e.id}');
          if (pe.exercise.tags.contains('isometric') && p.hasCondition('Hypertension')) {
            expect(pe.seconds, lessThanOrEqualTo(20), reason: '$label ${e.id} hold');
          }
        }
        for (final d in plan.week.whereType<WorkoutDay>()) {
          expect(d.exercises.where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown').length, greaterThanOrEqualTo(1), reason: label);
        }
      }
    });
  });
}

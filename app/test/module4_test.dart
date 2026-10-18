import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app/models/health_profile.dart';
import 'package:app/models/movement_pattern.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/met_calculator.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/workout_readiness_service.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late FoodDatabase foods;
  late Map<String, dynamic> catalogJson;
  late Map<String, dynamic> compendium;
  late Map<String, dynamic> datasetById;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    final text = File('assets/data/exercise_catalog.json').readAsStringSync();
    ExerciseCatalog.loadFromJsonString(text);
    catalogJson = jsonDecode(text) as Map<String, dynamic>;
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
    compendium = jsonDecode(File('ml/exercise_catalog/compendium_2024_subset.json').readAsStringSync()) as Map<String, dynamic>;
    final cache = File('ml/exercise_catalog/cache/exercises-${catalogJson['meta']['commit']}.json');
    datasetById = cache.existsSync()
        ? {for (final e in jsonDecode(cache.readAsStringSync()) as List) (e as Map)['id'] as String: e}
        : const {};
  });

  List<PlannedExercise> scheduled(PersonalizedPlan p) => [
        for (final d in p.week.whereType<WorkoutDay>())
          for (final e in d.exercises) e,
      ];

  PersonalizedPlan plan(HealthProfile p, {WorkoutReadiness? readiness, int variant = 0}) =>
      PlanGenerator(foods).generate(p, const RuleBasedClassifier().classify(p), variant: variant, readiness: readiness);

  group('Dataset import (free-exercise-db)', () {
    test('records, ids and provenance', () {
      final meta = catalogJson['meta'] as Map<String, dynamic>;
      expect(meta['dataset'], 'free-exercise-db');
      expect(meta['license'], contains('Unlicense'));
      expect(meta['commit'], hasLength(40));
      expect(meta['records'], 876);
      expect(meta['imported'], 871);
      expect((meta['dropped'] as List).length, 5, reason: 'records with no instructions are not imported');
      expect(ExerciseCatalog.all.length, 871);
      final ids = <String>{};
      for (final e in catalogJson['exercises'] as List) {
        final m = e as Map<String, dynamic>;
        expect(ids.add(m['id'] as String), isTrue, reason: 'duplicate ${m['id']}');
        expect((m['dataset'] as Map)['id'], m['id'], reason: 'original dataset id is preserved');
      }
    });

    test('dataset fields are kept exactly as published', () {
      if (datasetById.isEmpty) {
        markTestSkipped('dataset cache not present; run ml/exercise_catalog/build_catalog.py');
        return;
      }
      for (final e in catalogJson['exercises'] as List) {
        final m = e as Map<String, dynamic>;
        final original = datasetById[m['id']] as Map;
        final kept = m['dataset'] as Map;
        for (final f in ['name', 'force', 'level', 'mechanic', 'equipment', 'category', 'primaryMuscles', 'secondaryMuscles', 'instructions']) {
          expect(jsonEncode(kept[f]), jsonEncode(original[f]), reason: '${m['id']}.$f');
        }
      }
    });

    test('missing optional fields are tolerated, not invented', () {
      final noMechanic = ExerciseCatalog.all.where((e) => e.mechanic.isEmpty).toList();
      expect(noMechanic, isNotEmpty, reason: 'the dataset has records without a mechanic');
      final raw = (catalogJson['exercises'] as List).cast<Map<String, dynamic>>().firstWhere((m) => (m['dataset'] as Map)['mechanic'] == null);
      expect((raw['dataset'] as Map)['mechanic'], isNull, reason: 'kept as null, not filled in');
      expect(ExerciseCatalog.all.where((e) => e.position.isNotEmpty), isEmpty, reason: 'position is not in the dataset');
    });

    test('image references are validated and pinned to the imported commit', () {
      final commit = catalogJson['meta']['commit'];
      expect(catalogJson['meta']['invalidImageReferences'], 0);
      var withImages = 0;
      for (final e in ExerciseCatalog.all) {
        for (final u in e.imageUrls) {
          expect(u, startsWith('https://raw.githubusercontent.com/yuhonas/free-exercise-db/$commit/exercises/'));
        }
        if (e.imageUrls.isNotEmpty) withImages++;
      }
      // A few dataset records list no images at all; nothing is invented for them.
      final listed = (catalogJson['exercises'] as List).where((m) => ((m as Map)['dataset']['images'] as List? ?? const []).isNotEmpty).length;
      expect(withImages, listed);
      expect(withImages, greaterThan(860));
    });

    test('curated exercises link to their dataset entry without duplicating it', () {
      expect(ExerciseCatalog.curatedIdsFor('Bodyweight_Squat'), contains('squat'));
      expect(ExerciseCatalog.uncurated.any((e) => e.id == 'Bodyweight_Squat'), isFalse);
      final squat = ExerciseLibrary.byId('squat')!;
      expect(ExerciseCatalog.imagesFor(squat), isNotEmpty, reason: 'exact match shows the dataset photos');
      final lunge = ExerciseLibrary.byId('lunge')!;
      expect(lunge.referenceMatch, 'related');
      expect(ExerciseCatalog.imagesFor(lunge), isEmpty, reason: 'a related match does not borrow photos');
    });

    test('hand-supported and forearm exercises are marked as loading the wrist, so the wrist injury rule reaches them', () {
      for (final id in ['Pushups', 'Bench_Dips', 'Plank', 'Mountain_Climbers', 'Palms-Up_Dumbbell_Wrist_Curl_Over_A_Bench']) {
        expect(ExerciseCatalog.byId(id)!.joints, contains('wrist'), reason: id);
      }
      for (final id in ['Jerk_Dip_Squat', 'Bodyweight_Squat', 'Dumbbell_Bicep_Curl']) {
        expect(ExerciseCatalog.byId(id)!.joints, isNot(contains('wrist')), reason: id);
      }
    });

    test('queries filter by equipment, group, muscle and level', () {
      final db = ExerciseCatalog.query(equipment: {'dumbbell'}, group: 'push', maxLevel: 1);
      expect(db, isNotEmpty);
      expect(db.every((e) => e.equipmentKey == 'dumbbell' && e.group == 'push' && e.level <= 1), isTrue);
      expect(ExerciseCatalog.query(muscle: 'biceps').every((e) => e.muscles.map((m) => m.toLowerCase()).contains('biceps')), isTrue);
    });
  });

  group('MET mapping (2024 Adult Compendium)', () {
    Map<String, dynamic> act(String code) =>
        (compendium['activities'] as List).cast<Map<String, dynamic>>().firstWhere((a) => a['code'] == code);

    test('every assigned value is the published Compendium value for its code', () {
      for (final e in ExerciseCatalog.all.where((e) => e.hasMet)) {
        final code = e.compendium.replaceAll('*', '');
        expect(e.met, (act(code)['met'] as num).toDouble(), reason: e.id);
        expect(e.metDescription, act(code)['description'], reason: e.id);
      }
      for (final e in ExerciseLibrary.all.where((e) => e.compendium.isNotEmpty)) {
        expect(e.met, (act(e.compendium.replaceAll('*', ''))['met'] as num).toDouble(), reason: 'curated ${e.id}');
      }
    });

    test('exact, approximate and unmatched examples', () {
      final push = ExerciseCatalog.byId('Pushups')!;
      expect([push.metMatch, push.compendium, push.met], ['exact', '02022', 3.8]);
      final bench = ExerciseCatalog.byId('Dumbbell_Bench_Press')!;
      expect([bench.metMatch, bench.compendium, bench.met], ['approximate', '02054*', 3.5]);
      final strongman = ExerciseCatalog.all.firstWhere((e) => e.category == 'strongman');
      expect(strongman.metMatch, 'unmatched');
      expect(strongman.hasMet, isFalse);
      expect(strongman.met, 0, reason: 'no invented value');
    });

    test('counts match the build report and nothing is marked validated', () {
      final counts = {'exact': 0, 'approximate': 0, 'unmatched': 0};
      for (final e in ExerciseCatalog.all) {
        counts[e.metMatch] = counts[e.metMatch]! + 1;
        expect(e.reviewStatus, 'pending');
      }
      expect(counts, ExerciseCatalog.metCounts);
      expect(counts['exact']! + counts['approximate']! + counts['unmatched']!, 871);
    });

    test('the mapping rules only use Compendium codes that exist', () {
      final rules = jsonDecode(File('ml/exercise_catalog/met_mapping_rules.json').readAsStringSync())['rules'] as List;
      final codes = {for (final a in compendium['activities'] as List) (a as Map)['code']};
      for (final r in rules.cast<Map>()) {
        if (r['code'] != null) expect(codes, contains(r['code']), reason: r['id']);
        expect(r.containsKey('category'), isTrue, reason: '${r['id']}: rules never match on the name alone');
      }
    });

    test('calorie formulas', () {
      const hour = Duration(hours: 1);
      expect(MetCalculator.kcalCompendium(met: 3.8, weightKg: 70, active: hour), closeTo(266, 1e-9));
      expect(MetCalculator.kcalOxygen(met: 3.8, weightKg: 70, active: hour), closeTo(279.3, 1e-9), reason: '5% higher');
      expect(MetCalculator.kcalCompendium(met: null, weightKg: 70, active: hour), isNull, reason: 'unmatched: no estimate');
      expect(MetCalculator.kcalCompendium(met: 3.8, weightKg: 0, active: hour), isNull);
      final squat = ExerciseLibrary.byId('squat')!;
      const p = PlannedExercise(exercise: Exercise(id: 'x', name: 'x', icon: '', group: 'legs', muscles: [], impact: 'low', level: 1, met: 3.0, steps: []), sets: 3, reps: 10, seconds: 0, restSeconds: 60);
      expect(p.kcal(80), closeTo(MetCalculator.kcalCompendium(met: 3.0, weightKg: 80, active: Duration(seconds: p.activeSeconds))!, 1e-9),
          reason: 'the plan uses the same formula, active time only (rest excluded)');
      expect(p.totalSeconds, greaterThan(p.activeSeconds));
      expect(squat.hasMet, isTrue);
    });
  });

  group('Module 2 → Module 4', () {
    test('the plan carries the classification and reacts when it changes', () {
      final healthy = _person();
      final heavy = _person(weight: 105);
      final a = plan(healthy, readiness: const WorkoutReadiness());
      final b = plan(heavy, readiness: const WorkoutReadiness());
      expect(a.category, const RuleBasedClassifier().classify(healthy).category);
      expect(b.category, 'Obese');
      expect(scheduled(b).every((p) => p.exercise.impact != 'high'), isTrue);
      expect(b.restrictionNotes.join(' '), contains('BMI'));
    });

    test('several conditions at once are all applied', () {
      final p = plan(_person(conditions: ['Hypertension', 'Diabetes', 'Asthma']), readiness: const WorkoutReadiness());
      final notes = p.restrictionNotes.join(' ');
      expect(notes, allOf(contains('Hypertension'), contains('Diabetes'), contains('Asthma')));
      for (final e in scheduled(p)) {
        expect(e.exercise.tags.contains('hiit'), isFalse);
        expect(e.exercise.impact, isNot('high'));
        if (e.exercise.tags.contains('isometric')) expect(e.seconds, lessThanOrEqualTo(20));
      }
    });

    test('no medical history: no medical rules, but the program rules still apply', () {
      final p = plan(_person(conditions: const []), readiness: const WorkoutReadiness());
      expect(p.restrictionNotes.single, contains('No medical restrictions detected'));
      expect(scheduled(p).any((e) => e.exercise.tags.contains('maximal')), isFalse);
    });
  });

  group('Safety in generated plans', () {
    test('warning symptoms: no plan at all, and the reason is given', () {
      final p = plan(_person(), readiness: const WorkoutReadiness(symptoms: {'chestPain'}));
      expect(p.workoutAvailable, isFalse);
      expect(p.week.every((d) => d == null), isTrue);
      expect(p.gate!.status, WorkoutGateStatus.needsClearance);
      expect(p.restrictionNotes.single, contains('see a doctor'));
    });

    test('heart condition without clearance blocks; with clearance the cardiac rules still hold', () {
      final heart = _person(conditions: ['Heart Disease']);
      expect(plan(heart, readiness: const WorkoutReadiness()).workoutAvailable, isFalse);
      final cleared = plan(heart, readiness: const WorkoutReadiness(clearance: true, equipment: {'dumbbell', 'kettlebell'}));
      expect(cleared.workoutAvailable, isTrue);
      for (final e in scheduled(cleared)) {
        expect(e.exercise.impact, isNot('high'));
        expect(e.exercise.tags, isNot(anyOf(contains('hiit'), contains('isometric'), contains('plyo'))));
        if (e.exercise.tags.contains('externalLoad')) expect(e.ruleNotes.join(' '), contains('never hold your breath'));
      }
    });

    test('scores never override restrictions: every scheduled exercise passes the rules (400 random people)', () {
      final rnd = Random(7);
      const conds = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity'];
      const kit = ['dumbbell', 'kettlebell', 'bands', 'barbell', 'medicine_ball', 'exercise_ball', 'cable', 'machine'];
      const joints = ['knee', 'lowerBack', 'shoulder', 'wrist', 'ankle'];
      for (var i = 0; i < 400; i++) {
        final person = _person(
          conditions: [for (final c in conds) if (rnd.nextDouble() < 0.15) c],
          weight: 45 + rnd.nextDouble() * 80,
          dob: '${1945 + rnd.nextInt(60)}-05-05',
          goal: const ['Lose Weight', 'Gain Muscle', 'Maintain & Stay Fit'][rnd.nextInt(3)],
          activity: const ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active'][rnd.nextInt(4)],
          freq: 2 + rnd.nextInt(5),
        );
        final readiness = WorkoutReadiness(
          clearance: rnd.nextBool(),
          equipment: {for (final k in kit) if (rnd.nextDouble() < 0.4) k},
          injuries: {for (final j in joints) if (rnd.nextDouble() < 0.15) j},
        );
        final cls = const RuleBasedClassifier().classify(person);
        final p = PlanGenerator(foods).generate(person, cls, readiness: readiness);
        if (!p.workoutAvailable) {
          expect(cls.isCardiac || person.medicalConditions.contains('Heart Disease'), isTrue, reason: 'only heart conditions without clearance block here');
          continue;
        }
        final assessment = SafetyRuleRepository.engine.assess(HealthFacts.from(person, cls, p.intensity, readiness: readiness));
        expect(p.workoutDays, lessThanOrEqualTo(assessment.maxDays));
        for (final day in p.week.whereType<WorkoutDay>()) {
          final ids = day.exercises.map((e) => e.exercise.id).toList();
          expect(ids.toSet().length, ids.length, reason: 'no exercise twice in one session');
          for (final e in day.exercises) {
            final d = assessment.decide(e.exercise);
            expect(d.schedulable, isTrue, reason: 'person $i: ${e.exercise.id} ${d.outcome} ${d.ruleIds}');
            final key = e.exercise.equipmentKey;
            expect(key == 'none' || readiness.equipment.contains(key), isTrue, reason: '${e.exercise.id} needs $key');
            for (final j in e.exercise.joints.where(readiness.injuries.contains)) {
              expect(e.exercise.impact, isNot('high'), reason: 'high impact on injured $j');
              expect(e.ruleNotes.join(' '), contains('pain-free'), reason: '${e.exercise.id} loads injured $j');
            }
          }
          expect(day.exercises.every((e) => e.exercise.hasMet || e.exercise.group == 'mobility'), isTrue,
              reason: 'scheduled exercises have an energy value');
        }
      }
    });

    test('owning equipment brings in equipment exercises, with their reason and dataset instructions', () {
      var used = 0;
      for (final goal in ['Gain Muscle', 'Maintain & Stay Fit', 'Lose Weight']) {
        for (var v = 0; v < 3; v++) {
          final p = plan(_person(goal: goal, freq: 5), readiness: const WorkoutReadiness(equipment: {'dumbbell', 'kettlebell', 'bands'}), variant: v);
          for (final e in scheduled(p).where((e) => e.exercise.source == 'free-exercise-db')) {
            used++;
            expect(e.reasons.join(' '), contains('Uses equipment you have'));
            expect(e.exercise.steps, isNotEmpty);
          }
        }
      }
      expect(used, greaterThan(0));
      final bodyOnly = plan(_person(), readiness: const WorkoutReadiness());
      expect(scheduled(bodyOnly).every((e) => e.exercise.source == 'baymax'), isTrue, reason: 'no equipment: curated library only');
    });

    test('identical inputs give an identical plan', () {
      List<String> ids(PersonalizedPlan p) => [for (final d in p.week) d == null ? '-' : d.exercises.map((e) => '${e.exercise.id}:${e.sets}x${e.reps}/${e.seconds}').join(',')];
      const r = WorkoutReadiness(equipment: {'dumbbell'}, injuries: {'knee'});
      expect(ids(plan(_person(), readiness: r)), ids(plan(_person(), readiness: r)));
    });

    test('regeneration after a profile change produces a different, still valid plan', () {
      const r = WorkoutReadiness(equipment: {'dumbbell'});
      final before = plan(_person(goal: 'Gain Muscle'), readiness: r);
      final after = plan(_person(goal: 'Lose Weight'), readiness: r);
      expect(before.week.whereType<WorkoutDay>().map((d) => d.name).toList(), isNot(after.week.whereType<WorkoutDay>().map((d) => d.name).toList()));
    });

    test('sets, reps and rest come from the prescription rules, not from MET', () {
      for (final e in scheduled(plan(_person(), readiness: const WorkoutReadiness(equipment: {'dumbbell'})))) {
        if (e.exercise.group == 'mobility') continue;
        expect(e.sets, inInclusiveRange(1, 4));
        if (!e.timed) expect(e.reps, inInclusiveRange(6, 20));
        expect(e.restSeconds, inInclusiveRange(0, 90));
      }
    });
  });

  group('Module 4 → Module 5 and storage', () {
    test('the hand-off carries the movement pattern: full form for tested exercises, basic tracking for dataset ones', () {
      final squat = PlannedExercise(exercise: ExerciseLibrary.byId('squat')!, sets: 3, reps: 10, seconds: 0, restSeconds: 60);
      expect(ExerciseFormRules.supports(SessionExercise.fromPlanned(squat).id), isTrue);
      expect(MovementPatterns.forSession(SessionExercise.fromPlanned(squat)).level, CameraSupportLevel.validatedForm);
      final db = PlannedExercise(exercise: ExerciseCatalog.byId('Dumbbell_Bench_Press')!, sets: 3, reps: 10, seconds: 0, restSeconds: 60);
      final session = SessionExercise.fromPlanned(db);
      expect(ExerciseFormRules.supports(session.id), isFalse, reason: 'no tested form rules for this one');
      expect(session.movement, MovementPattern.benchPress);
      expect(MovementPatterns.forSession(session).level, CameraSupportLevel.experimentalForm, reason: 'bench press: hips-on-bench check');
    });

    test('plan snapshot is versioned and its fingerprint is stable', () {
      final p = plan(_person(), readiness: const WorkoutReadiness());
      Map<String, Object?> snap(PersonalizedPlan p) =>
          WorkoutPlanSnapshot.build(plan: p, goal: 'Gain Muscle', catalogCommit: ExerciseCatalog.datasetCommit, profileUpdatedAt: 0, weightKg: 70);
      final a = snap(p);
      expect(a['rulesVersion'], '${SafetyRuleRepository.version}+${ClassificationProfiles.version}');
      expect(a['engineVersion'], WorkoutPlanSnapshot.engineVersion);
      expect(a['fingerprint'], snap(plan(_person(), readiness: const WorkoutReadiness()))['fingerprint']);
      expect(a['fingerprint'], isNot(snap(plan(_person(), readiness: const WorkoutReadiness(), variant: 1))['fingerprint']));
    });

    test('stored readiness and plan fields are exactly the ones database.rules.json accepts', () {
      final rules = jsonDecode(File('database.rules.json').readAsStringSync())['rules']['users'][r'$uid'] as Map<String, dynamic>;
      Set<String> allowed(Map<String, dynamic> node) => {for (final k in node.keys) if (!k.startsWith('.') && !k.startsWith(r'$')) k};
      final readinessRules = rules['workoutReadiness'] as Map<String, dynamic>;
      const r = WorkoutReadiness(equipment: {'dumbbell'}, injuries: {'knee'}, symptoms: {'dizziness'}, clearance: false);
      expect(allowed(readinessRules).containsAll({...r.toJson().keys, 'updatedAt'}), isTrue);
      final keyRule = RegExp(r'\^\[A-Za-z_\]\{1,30\}\$');
      expect(keyRule.hasMatch(readinessRules['equipment'][r'$k']['.validate'] as String), isTrue);
      for (final k in [...WorkoutReadiness.equipmentOptions.keys, ...WorkoutReadiness.injuryOptions.keys, ...WorkoutReadiness.symptomOptions.keys]) {
        expect(RegExp(r'^[A-Za-z_]{1,30}$').hasMatch(k), isTrue, reason: k);
      }
      final planRules = rules['workoutPlan'] as Map<String, dynamic>;
      final snapshot = WorkoutPlanSnapshot.build(
          plan: plan(_person(), readiness: const WorkoutReadiness()), goal: 'Gain Muscle', catalogCommit: 'abc', profileUpdatedAt: 0, weightKg: 70);
      expect(allowed(planRules).containsAll({...snapshot.keys, 'savedAt'}), isTrue, reason: '${snapshot.keys.toSet().difference(allowed(planRules))}');
      final dayRules = planRules['days'][r'$day'] as Map<String, dynamic>;
      final exRules = dayRules['exercises'][r'$i'] as Map<String, dynamic>;
      for (final d in (snapshot['days'] as Map).values) {
        expect(allowed(dayRules).containsAll((d as Map).keys), isTrue);
        for (final e in (d['exercises'] as Map).values) {
          expect(allowed(exRules).containsAll((e as Map).keys), isTrue);
          expect(((e['id'] as String).length), lessThanOrEqualTo(80));
        }
      }
      expect((snapshot['fingerprint'] as String).length, lessThanOrEqualTo(16));
    });

    test('readiness answers round-trip and unknown keys are ignored', () {
      const r = WorkoutReadiness(equipment: {'dumbbell'}, injuries: {'knee'}, symptoms: {'dizziness'}, clearance: true);
      final back = WorkoutReadiness.fromJson({...r.toJson(), 'equipment': {'dumbbell': true, 'rocketPack': true}});
      expect(back.equipment, {'dumbbell'});
      expect(back.injuries, {'knee'});
      expect(back.symptoms, {'dizziness'});
      expect(back.clearance, isTrue);
      expect(back.answered, isTrue);
      expect(WorkoutReadiness.unanswered.answered, isFalse);
    });
  });
}

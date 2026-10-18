// Automated UNIT test cases for Modules 4, 5 and 6 (report section 5.1). IDs: ATC-M4-U07.., ATC-M5-U01.., ATC-M6-U01..
// Run: flutter test test/atc/atc_m456_unit_test.dart   (set ATC_LOG=<file> to record the results for the report)
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/movement_pattern.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_repository.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/met_calculator.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/form_checks.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/pose_landmark.dart';
import 'package:app/services/posture/pose_math.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/posture/rep_counter.dart';
import 'package:app/services/voice/coach_responder.dart';
import 'package:app/services/voice/intent_service.dart';
import 'package:app/services/voice/speech_recognizer.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter_test/flutter_test.dart' hide same;

import '../support/pattern_fixtures.dart';
import '../support/pose_fixtures.dart';
import '../support/voice_fakes.dart';
import 'atc_helper.dart';

HealthProfile _p({List<String> conditions = const [], double weight = 70, int freq = 4, String goal = 'Maintain & Stay Fit'}) => HealthProfile(
    fullName: 'Test User', dob: '${DateTime.now().year - 30}-01-01', gender: 'Female', heightValue: 170, weightValue: weight,
    medicalConditions: conditions, primaryGoal: goal, activityLevel: 'Moderately Active', workoutFrequency: freq);

const _rules = RuleBasedClassifier();

Exercise _ex(String id, {String impact = 'low', List<String> tags = const [], int level = 1, String source = 'baymax', double met = 4}) => Exercise(
    id: id, name: id, icon: '', group: 'legs', muscles: const ['Quadriceps'], impact: impact, level: level, met: met, compendium: '02022',
    steps: const ['x'], tags: tags, source: source);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FoodDatabase foods;
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  PersonalizedPlan plan(HealthProfile p, {WorkoutReadiness? readiness = const WorkoutReadiness(clearance: true), int variant = 0}) =>
      PlanGenerator(foods).generate(p, _rules.classify(p), readiness: readiness, variant: variant);
  Iterable<PlannedExercise> all(PersonalizedPlan p) => p.week.whereType<WorkoutDay>().expand((d) => d.exercises);
  SafetyAssessment assess(HealthProfile p, {WorkoutReadiness? readiness}) {
    final cls = _rules.classify(p);
    return SafetyRuleRepository.engine.assess(HealthFacts.from(p, cls, 'Moderate', readiness: readiness),
        profile: ClassificationProfiles.forCategory(cls.category));
  }

  // ================================================================ Module 4
  group('Unit Testing: Module 4 knowledge base and plan generator', () {
    atc('ATC-M4-U07', req: 'M4-SFR1', objective: 'The free-exercise-db dataset is imported with every usable record',
        input: 'exercise_catalog.json (pinned commit f00c92c)', expected: '876 records, 871 imported, 5 without instructions dropped',
        run: () {
          final m = ExerciseCatalog.meta;
          return check(m['records'] == 876 && m['imported'] == 871 && ExerciseCatalog.all.length == 871 && (m['dropped'] as List).length == 5,
              'Records ${m['records']}; imported ${m['imported']}; loaded ${ExerciseCatalog.all.length}; dropped ${(m['dropped'] as List).length}');
        });
    atc('ATC-M4-U08', req: 'M4-SFR1', objective: 'Exercise IDs are unique and a dataset duplicate of a curated exercise is not offered twice',
        input: 'unified catalogue (curated + dataset)', expected: 'No duplicate ID; "Bodyweight_Squat" hidden behind curated "squat"',
        run: () {
          final ids = ExerciseRepository.all.map((e) => e.id).toList();
          final dup = ids.length - ids.toSet().length;
          return check(dup == 0 && !ids.contains('Bodyweight_Squat') && ids.contains('squat'),
              '${ids.length} exercises; duplicates $dup; Bodyweight_Squat listed: ${ids.contains('Bodyweight_Squat')}');
        });
    atc('ATC-M4-U09', req: 'M4-SFR1', objective: 'A missing optional field is tolerated, not invented', input: 'dataset record "Bicycling" (mechanic not stated)',
        expected: 'Loaded with an empty mechanic', run: () {
          final e = ExerciseCatalog.byId('Bicycling');
          return check(e != null && e.mechanic.isEmpty, 'Loaded: ${e != null}; mechanic "${e?.mechanic}"');
        });
    atc('ATC-M4-U10', req: 'M4-SFR3', objective: 'Equipment exercises are offered only for equipment the user owns',
        input: 'owned equipment {dumbbell}; then none', expected: 'Every offered exercise needs a dumbbell; none offered without equipment',
        run: () {
          final d = ExerciseCatalog.plannableWith({'dumbbell'});
          final none = ExerciseCatalog.plannableWith({});
          return check(d.isNotEmpty && d.every((e) => e.equipmentKey == 'dumbbell') && none.isEmpty,
              '${d.length} offered with a dumbbell, all dumbbell: ${d.every((e) => e.equipmentKey == 'dumbbell')}; without equipment: ${none.length}');
        });
    atc('ATC-M4-U11', req: 'M4-FR1', objective: 'Expert-level dataset exercises are never scheduled (program rule)', input: 'healthy user; dataset exercise at level 3',
        expected: 'Excluded by PRG-NO-MAXIMAL', run: () {
          final d = assess(_p()).decide(_ex('x', level: 3, source: 'free-exercise-db'));
          return check(d.outcome == ExerciseOutcome.excluded && d.ruleIds.contains('PRG-NO-MAXIMAL'), 'Outcome ${d.outcome.name}; rules ${d.ruleIds}');
        });
    atc('ATC-M4-U12', req: 'M4-FR2', objective: 'Each health category maps to its training profile', input: 'categories Healthy, Cardiac, Obese, an unknown category',
        expected: 'Healthy vigorous; Cardiac and Obese moderate; unknown falls back to At-Risk', run: () {
          final h = ClassificationProfiles.forCategory('Healthy').maxBand, c = ClassificationProfiles.forCategory('Cardiac').maxBand;
          final o = ClassificationProfiles.forCategory('Obese').maxBand, u = ClassificationProfiles.forCategory('Something').category;
          return check(h == IntensityBand.vigorous && c == IntensityBand.moderate && o == IntensityBand.moderate && u == 'At-Risk',
              'Healthy ${h.name}; Cardiac ${c.name}; Obese ${o.name}; unknown → $u');
        });
    atc('ATC-M4-U13', req: 'M4-FR1', objective: 'Hypertension excludes high-intensity intervals and names the rule', input: 'condition "Hypertension"; HIIT exercise',
        expected: 'Excluded; rule MED-HTN', run: () {
          final d = assess(_p(conditions: ['Hypertension'])).decide(_ex('hiit', tags: ['hiit']));
          return check(d.outcome == ExerciseOutcome.excluded && d.ruleIds.contains('MED-HTN'), 'Outcome ${d.outcome.name}; rules ${d.ruleIds}');
        });
    atc('ATC-M4-U14', req: 'M4-FR1', objective: 'Several conditions merge to the most restrictive limits', input: 'Hypertension + Diabetes; Hypertension alone',
        expected: 'Both conditions apply; days capped at the smallest maximum', run: () {
          final both = assess(_p(conditions: ['Hypertension', 'Diabetes'])), htn = assess(_p(conditions: ['Hypertension']));
          final ids = both.hits.map((h) => h.rule.id).toSet();
          return check(ids.containsAll({'MED-HTN', 'MED-DIABETES'}) && both.maxDays <= htn.maxDays,
              'Rules applied: ${ids.where((i) => i.startsWith('MED')).join(', ')}; max days ${both.maxDays} (Hypertension alone ${htn.maxDays})');
        });
    atc('ATC-M4-U15', req: 'M4-FR5', objective: 'Owned equipment brings dataset exercises in, with the reason shown', input: 'Gain Muscle; owns dumbbells',
        expected: 'At least one dataset exercise whose first reason starts "Uses equipment you have"', run: () {
          final ds = all(plan(_p(goal: 'Gain Muscle'), readiness: const WorkoutReadiness(clearance: true, equipment: {'dumbbell'})))
              .where((p) => p.exercise.source == 'free-exercise-db')
              .toList();
          return check(ds.isNotEmpty && ds.first.reasons.first.startsWith('Uses equipment you have'),
              '${ds.length} dataset exercises; first reason "${ds.isEmpty ? '-' : ds.first.reasons.first}"');
        });
    atc('ATC-M4-U16', req: 'M4-FR5', objective: 'The week has the chosen number of training days; the rest are rest days',
        input: 'healthy user, 4 days a week', expected: '7 days: 4 workouts, 3 rest days', run: () {
          final w = plan(_p(freq: 4)).week;
          final work = w.whereType<WorkoutDay>().length;
          return check(w.length == 7 && work == 4, '${w.length} days; $work workouts; ${w.length - work} rest days');
        });
    atc('ATC-M4-U17', req: 'M4-FR5', objective: 'The same inputs always give the same plan (deterministic)', input: 'same profile and variant, generated twice',
        expected: 'Identical exercise lists', run: () {
          String sig(PersonalizedPlan p) => all(p).map((e) => '${e.exercise.id}:${e.sets}x${e.reps}/${e.seconds}').join(',');
          final a = sig(plan(_p())), b = sig(plan(_p()));
          return check(a == b, 'Identical: ${a == b} (${a.split(',').length} entries)');
        });
    atc('ATC-M4-U18', req: 'M4-SFR2', objective: 'MET values are matched to the 2024 Compendium with a recorded match type',
        input: 'all 871 dataset exercises', expected: '181 exact, 606 approximate, 84 unmatched', run: () {
          final c = ExerciseCatalog.metCounts;
          return check(c['exact'] == 181 && c['approximate'] == 606 && c['unmatched'] == 84, 'Exact ${c['exact']}; approximate ${c['approximate']}; unmatched ${c['unmatched']}');
        });
    atc('ATC-M4-U19', req: 'M4-SFR2', objective: 'An exercise without a MET value is never offered for planning', input: 'every equipment type owned',
        expected: 'All offered exercises have a MET value', run: () {
          final offered = ExerciseCatalog.plannableWith(WorkoutReadiness.equipmentOptions.keys.toSet());
          final missing = offered.where((e) => !e.hasMet).length;
          return check(missing == 0 && offered.isNotEmpty, '${offered.length} offered; $missing without MET');
        });
    atc('ATC-M4-U20', req: 'M4-SFR2', objective: 'Calories = MET × body weight × active hours', input: 'MET 3.8, 70 kg, 30 min active',
        expected: '133 kcal', run: () {
          final k = MetCalculator.kcalCompendium(met: 3.8, weightKg: 70, active: const Duration(minutes: 30));
          return check(k != null && (k - 133).abs() < 0.01, 'kcal = ${k?.toStringAsFixed(2)}');
        });
    atc('ATC-M4-U21', req: 'M4-SFR2', objective: 'Intensity bands follow the WHO MET bands at the boundaries', input: 'MET 2.99, 3.0, 5.99, 6.0',
        expected: 'light, moderate, moderate, vigorous', run: () {
          final b = [2.99, 3.0, 5.99, 6.0].map((m) => IntensityBand.ofMet(m).name).toList();
          return same(b.join(', '), 'light, moderate, moderate, vigorous', say: 'Bands: ${b.join(', ')}');
        });
    atc('ATC-M4-U22', req: 'M4-FR2', objective: 'Diabetes: no more than two rest days in a row', input: 'condition "Diabetes", 2 days a week chosen',
        expected: '3 workout days; longest rest run 2 days', run: () {
          final w = plan(_p(conditions: ['Diabetes'], freq: 2)).week;
          final longest = ClassificationProfiles.longestRest([for (final d in w) d != null]);
          return check(w.whereType<WorkoutDay>().length == 3 && longest <= 2, '${w.whereType<WorkoutDay>().length} workout days; longest rest $longest days');
        });
    atc('ATC-M4-U23', req: 'M4-SFR3', objective: 'Warning symptoms stop plan generation and give the reason', input: 'readiness: chest pain reported',
        expected: 'No workout days; gate needsClearance (SCR-SYMPTOMS)', run: () {
          final p = plan(_p(), readiness: const WorkoutReadiness(symptoms: {'chest_pain'}));
          return check(!p.workoutAvailable && p.workoutDays == 0 && p.gate!.ruleIds.contains('SCR-SYMPTOMS'),
              'Workout days ${p.workoutDays}; gate ${p.gate!.status.name}; rules ${p.gate!.ruleIds}');
        });
    atc('ATC-M4-U24', req: 'M4-SFR4', objective: 'A planned exercise counts as completed only when its target is reached', input: 'manual session: 2 of 2 sets; then skipped',
        expected: 'Completed true; skipped false', run: () {
          final c = WorkoutSessionController();
          final ex = SessionExercise.fromExercise(ExerciseLibrary.byId('squat')!, sets: 2);
          c.start(WorkoutSessionRequest(exercise: ex), SessionMode.manual);
          c.recordManualSet(ex.reps);
          c.recordManualSet(ex.reps);
          final done = c.finish().completedTarget;
          c.start(WorkoutSessionRequest(exercise: ex), SessionMode.manual);
          c.recordManualSet(ex.reps);
          c.recordManualSet(ex.reps);
          final skipped = c.finish(skipped: true).completedTarget;
          return check(done && !skipped, 'Completed: $done; when skipped: $skipped');
        });
  });

  // ================================================================ Module 5
  group('Unit Testing: Module 5 posture engine', () {
    final squat = ExerciseFormRules.forExercise('squat')!;
    atc('ATC-M5-U01', req: 'M5-FR16.1', objective: 'Joint angle at the middle landmark is computed correctly', input: 'points (1,0), (0,0), (0,1)',
        expected: '90°', run: () {
          final a = PoseMath.jointAngle(const Vec3(1, 0), const Vec3(0, 0), const Vec3(0, 1));
          return check(a != null && (a - 90).abs() < 1e-6, 'Angle = ${a?.toStringAsFixed(2)}°');
        });
    atc('ATC-M5-U02', req: 'M5-FR16.4', objective: 'Landmarks below the visibility threshold are not used', input: 'squat frame with visibility 0.3 (threshold 0.5)',
        expected: 'No measurement', run: () => check(PoseAnalyzer.measure(squatFrame(120, 0, visibility: 0.3), squat) == null, 'Measurement: none'));
    atc('ATC-M5-U03', req: 'M5-FR16.2', objective: 'Missing landmarks are named in the guidance', input: 'squat (dataset) with knees and ankles hidden',
        expected: 'Feedback starts "Can\'t see your knees and ankles"', run: () {
          final c = MovementPatterns.resolve('Barbell_Squat', MovementPattern.squat).form!;
          final f = PostureEngine(c)
              .process(jointFrame(c, 170, 33, hidden: {PoseIndex.leftKnee, PoseIndex.rightKnee, PoseIndex.leftAnkle, PoseIndex.rightAnkle}))
              .feedback
              .message;
          return check(f.startsWith("Can't see your knees and ankles"), 'Feedback: "$f"');
        });
    atc('ATC-M5-U04', req: 'M5-FR16.3', objective: 'The movement phases follow top → descending → bottom → ascending → top', input: 'one squat to 88°',
        expected: 'Phases seen in that order', run: () {
          final counter = RepCounter(squat);
          final seen = <RepPhase>[];
          for (final f in (Motion().hold(400).squat()).frames) {
            counter.update(PoseAnalyzer.measure(f, squat)!.primaryAngle, f.timestampMs);
            if (seen.isEmpty || seen.last != counter.phase) seen.add(counter.phase);
          }
          final want = [RepPhase.unknown, RepPhase.top, RepPhase.descending, RepPhase.bottom, RepPhase.ascending, RepPhase.top];
          return check(seen.toString() == want.toString(), 'Phases: ${seen.map((p) => p.name).join(' → ')}');
        });
    atc('ATC-M5-U05', req: 'M5-FR16.3', objective: 'Three full squats count three reps', input: '3 squats to 88°', expected: '3 reps, 0 partial',
        run: () {
          final e = PostureEngine(squat);
          for (final f in (Motion().hold(400).squat().squat().squat()).frames) {
            e.process(f);
          }
          return check(e.reps == 3 && e.partialReps == 0, 'Reps ${e.reps}; partial ${e.partialReps}');
        });
    atc('ATC-M5-U06', req: 'M5-FR16.3', objective: 'A half repetition is not counted', input: '1 squat that turns back at 125°', expected: '0 reps, 1 partial attempt',
        run: () {
          final e = PostureEngine(squat);
          for (final f in (Motion().hold(400).squat(depth: 125)).frames) {
            e.process(f);
          }
          return check(e.reps == 0 && e.partialReps == 1, 'Reps ${e.reps}; partial ${e.partialReps}');
        });
    atc('ATC-M5-U07', req: 'M5-FR16.3', objective: 'A movement faster than the minimum rep time is rejected as noise', input: 'squat down and up in 300 ms (minimum 600 ms)',
        expected: '0 reps', run: () {
          final e = PostureEngine(squat);
          for (final f in (Motion().hold(400).squat(downMs: 150, upMs: 150)).frames) {
            e.process(f);
          }
          return check(e.reps == 0, 'Reps ${e.reps}');
        });
    atc('ATC-M5-U08', req: 'M5-FR16.3', objective: 'The angle is smoothed (exponential average)', input: 'samples 170° then 130°',
        expected: 'Smoothed angle 150°', run: () {
          final c = RepCounter(squat)
            ..update(170, 0)
            ..update(130, 33);
          return check((c.smoothedAngle! - 150).abs() < 1e-6, 'Smoothed = ${c.smoothedAngle}');
        });
    atc('ATC-M5-U09', req: 'M5-SFR2', objective: 'A plank hold is timed only while in position', input: '5 s straight plank, then 3 s sagging',
        expected: 'About 5 s held', run: () {
          final c = MovementPatterns.resolve('plank', MovementPattern.plankHold).form!;
          final e = PostureEngine(c);
          var t = 0;
          for (var i = 0; i < 150; i++) {
            e.process(jointFrame(c, 176, t += 33, baseDeg: 90));
          }
          for (var i = 0; i < 90; i++) {
            e.process(jointFrame(c, 140, t += 33, baseDeg: 90));
          }
          return check(e.holdSeconds! >= 4 && e.holdSeconds! <= 5, 'Held ${e.holdSeconds} s');
        });
    atc('ATC-M5-U10', req: 'M5-FR16.2', objective: 'The back-alignment rule passes upright and fails a deep forward lean', input: 'torso lean 30° and 70° (limit 60°)',
        expected: 'Pass at 30°, fail at 70°', run: () {
          const r = TorsoLeanCheck(60);
          final a = r.evaluate(const PoseMeasurements(primaryAngle: 120, torsoLean: 30)), b = r.evaluate(const PoseMeasurements(primaryAngle: 120, torsoLean: 70));
          return check(a == CheckOutcome.pass && b == CheckOutcome.fail, '30°: ${a.name}; 70°: ${b.name}');
        });
    atc('ATC-M5-U11', req: 'M5-FR16.2', objective: 'The hip rule gives the right correction for sagging and piking', input: 'hip offset -0.12 and +0.20',
        expected: '"Raise your hips…" and "Lower your hips…"', run: () {
          const h = HipLineCheck();
          final sag = h.cueFor(const PoseMeasurements(primaryAngle: 170, hipOffset: -0.12)), pike = h.cueFor(const PoseMeasurements(primaryAngle: 170, hipOffset: 0.2));
          return check(sag.startsWith('Raise your hips') && pike.startsWith('Lower your hips'), 'Sag: "$sag"; pike: "$pike"');
        });
    atc('ATC-M5-U12', req: 'M5-FR18.1', objective: 'Posture score = acceptable reps ÷ attempted reps', input: '2 good squats and 1 shallow attempt',
        expected: 'Score 67%', run: () {
          final e = PostureEngine(squat);
          for (final f in (Motion().hold(400).squat().squat().squat(depth: 125)).frames) {
            e.process(f);
          }
          return same(e.postureScore, 67, say: 'Score ${e.postureScore}% (${e.reps} reps, ${e.partialReps} partial)');
        });
    atc('ATC-M5-U13', req: 'M5-FR16.2', objective: 'A correction is shown only after the fault persists for 3 frames', input: 'forward lean of 75° held during the descent',
        expected: '"Keep your back straight" appears, never on the first faulty frame', run: () {
          final e = PostureEngine(squat);
          final msgs = [for (final f in (Motion().hold(400).moveTo(95, 900, torsoLean: 75)).frames) e.process(f).feedback.message];
          final first = msgs.indexWhere((m) => m.startsWith('Keep your back straight'));
          return check(first > 0, 'First correction at frame $first of ${msgs.length}');
        });
    atc('ATC-M5-U14', req: 'M5-SFR1', objective: 'Exercises map to a movement pattern by movement, not muscle', input: 'Barbell_Squat, Leg_Extensions, Dumbbell_Bicep_Curl',
        expected: 'squat, legExtension, curl', run: () {
          final got = ['Barbell_Squat', 'Leg_Extensions', 'Dumbbell_Bicep_Curl'].map((i) => ExerciseCatalog.byId(i)!.movement.name).join(', ');
          return same(got, 'squat, legExtension, curl', say: 'Patterns: $got');
        });
    atc('ATC-M5-U15', req: 'M5-FR15.1', objective: 'An exercise the camera cannot follow is unsupported with a reason', input: 'Standing_Calf_Raises',
        expected: 'Not supported; reason mentions a movement too small to measure', run: () {
          final e = ExerciseCatalog.byId('Standing_Calf_Raises')!;
          final c = ExerciseRepository.postureFor(e);
          return check(c.level == CameraSupportLevel.notSupported && c.unsupportedReason!.contains('too small'), 'Level ${c.level.name}; reason "${c.unsupportedReason}"');
        });
    atc('ATC-M5-U16', req: 'M5-FR15.1', objective: 'Camera capability of every schedulable exercise (current code)', input: 'curated library + dataset exercises for any equipment, program rule applied',
        expected: 'Counts reported from the registry; only the 4 tuned exercises are validated', run: () {
          final list = [
            ...ExerciseLibrary.all,
            ...ExerciseCatalog.plannableWith(WorkoutReadiness.equipmentOptions.keys.toSet()).where((e) => e.level <= 2 && !e.tags.contains('maximal')),
          ];
          final levels = <CameraSupportLevel, int>{};
          for (final e in list) {
            final l = ExerciseRepository.postureFor(e).level;
            levels[l] = (levels[l] ?? 0) + 1;
          }
          final v = levels[CameraSupportLevel.validatedForm] ?? 0;
          return check(v == 4,
              '${list.length} schedulable: validated $v; experimental ${levels[CameraSupportLevel.experimentalForm] ?? 0}; basic ${levels[CameraSupportLevel.basicTracking] ?? 0}; unsupported ${levels[CameraSupportLevel.notSupported] ?? 0}');
        });
    atc('ATC-M5-U17', req: 'M5-SFR1', objective: 'Number of movement patterns with a tracker', input: 'MovementPattern enum',
        expected: 'Every pattern except "none" builds a tracker', run: () {
          final tracked = MovementPattern.values.where((p) => p != MovementPattern.none).toList();
          final built = tracked.where((p) => MovementPatterns.resolve('x', p).form != null).length;
          final holds = tracked.where((p) => MovementPatterns.resolve('x', p).form?.kind == TrackingKind.hold).length;
          return check(built == tracked.length, '${tracked.length} patterns, $built with a tracker ($holds hold, ${built - holds} repetition)');
        });
    atc('ATC-M5-U18', req: 'M5-FR16.3', objective: 'An opening movement (overhead press) is counted on the mirrored angle', input: '3 presses 110° → 150°; one-arm hanging arm ignored',
        expected: '3 reps', run: () {
          final c = MovementPatterns.resolve('Dumbbell_Shoulder_Press', MovementPattern.overheadPress).form!;
          final e = PostureEngine(c);
          final m = JointMotion(c, startAngle: 110, baseDeg: -100).hold(300);
          for (var i = 0; i < 3; i++) {
            m.moveTo(150, 700).hold(150).moveTo(110, 700).hold(250);
          }
          for (final f in m.frames) {
            e.process(f);
          }
          return same(e.reps, 3, say: 'Reps ${e.reps}');
        });
  });

  // ================================================================ Module 6
  group('Unit Testing: Module 6 voice assistant', () {
    final intents = RuleBasedIntentService();
    Future<String> intentOf(String t) async => (await intents.detect(t)).intent.name;
    void intentCase(String id, String text, CoachIntent want, String objective) => atc(id,
        req: 'M6-SFR1', objective: objective, input: '"$text"', expected: 'Intent ${want.name}',
        run: () async => same(await intentOf(text), want.name, say: 'Intent = ${await intentOf(text)}'));
    intentCase('ATC-M6-U01', 'How many reps have I done?', CoachIntent.repCount, 'A rep question is recognised');
    intentCase('ATC-M6-U02', "How's my form?", CoachIntent.postureFeedback, 'A form question is recognised');
    intentCase('ATC-M6-U03', 'Pause workout', CoachIntent.pauseSession, 'A pause command is recognised');
    intentCase('ATC-M6-U04', 'what is the capital of France', CoachIntent.unknown, 'An unrelated question falls back to unknown');
    intentCase('ATC-M6-U05', '   ', CoachIntent.unknown, 'Empty speech input is not treated as a command');
    intentCase('ATC-M6-U06', 'My knee hurts', CoachIntent.painOrSymptom, 'A pain report is recognised as a safety intent');

    atc('ATC-M6-U07', req: 'M6-FR19.3', objective: 'The reply uses the live rep counter, never an invented number', input: 'camera session with 2 counted squats; "how many reps"',
        expected: 'Reply "You\'ve completed 2 reps…"', run: () async {
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final e = PostureEngine(ExerciseFormRules.forExercise('squat')!);
          for (final f in (Motion().hold(400).squat().squat()).frames) {
            s.updatePosture(e.process(f), angleLabel: 'Knee');
          }
          final r = CoachResponder(session: s, schedule: const FakeSchedule()).respond(await intents.detect('how many reps'));
          return check(r.text.contains("You've completed 2 reps"), 'Reply: "${r.text}"');
        });
    atc('ATC-M6-U08', req: 'M6-FR19.3', objective: 'With no session the assistant says so instead of inventing numbers', input: 'no active session; "How many reps?"',
        expected: 'Reply mentions no active workout session', run: () async {
          final r = CoachResponder(session: WorkoutSessionController(), schedule: const FakeSchedule()).respond(await intents.detect('How many reps?'));
          return check(r.text.contains('no active workout session'), 'Reply: "${r.text}"');
        });
    atc('ATC-M6-U09', req: 'M6-FR19.5', objective: 'Quick-action chips are contextual and at most three', input: '"what is the capital of France"',
        expected: '1–3 chips', run: () async {
          final r = CoachResponder(session: WorkoutSessionController(), schedule: const FakeSchedule()).respond(await intents.detect('what is the capital of France'));
          return check(r.chips.isNotEmpty && r.chips.length <= 3, '${r.chips.length} chips: ${r.chips.join(', ')}');
        });

    Future<(VoiceAssistantController, FakeSpeechRecognizer, FakeSpeechOutput, FakePermissions)> make() async {
      final rec = FakeSpeechRecognizer(), out = FakeSpeechOutput(), perm = FakePermissions();
      AppPermissions.instance = perm;
      final a = VoiceAssistantController(recognizer: rec, output: out, intents: RuleBasedIntentService(), session: WorkoutSessionController(), schedule: const FakeSchedule());
      return (a, rec, out, perm);
    }

    atc('ATC-M6-U10', req: 'M6-FR19.2', objective: 'Microphone denied: the assistant never listens', input: 'microphone permission denied', expected: 'State unavailable; 0 listen calls',
        run: () async {
          final (a, rec, _, perm) = await make();
          perm.microphone = PermissionOutcome.denied;
          await a.startListening();
          final ok = a.state == VoiceState.unavailable && rec.listenCalls == 0;
          final msg = 'State ${a.state.name}; listen calls ${rec.listenCalls}; message "${a.errorMessage}"';
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, msg);
        });
    atc('ATC-M6-U11', req: 'M6-FR19.2', objective: 'Microphone permanently denied: the settings link is offered', input: 'microphone permanently denied',
        expected: 'settingsNeeded true; no listening', run: () async {
          final (a, rec, _, perm) = await make();
          perm.microphone = PermissionOutcome.permanentlyDenied;
          await a.startListening();
          final ok = a.settingsNeeded && rec.listenCalls == 0;
          final msg = 'Settings needed ${a.settingsNeeded}; listen calls ${rec.listenCalls}';
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, msg);
        });
    atc('ATC-M6-U12', req: 'M6-FR19.1', objective: 'Recognition errors give a clear message and nothing is spoken', input: 'no-match error; then timeout error',
        expected: '"didn\'t catch that"; "didn\'t hear anything"; no speech output', run: () async {
          final (a, rec, out, _) = await make();
          await a.startListening();
          rec.fail(SpeechErrorKind.noMatch);
          final m1 = a.errorMessage ?? '';
          await a.startListening();
          rec.fail(SpeechErrorKind.timeout);
          final m2 = a.errorMessage ?? '';
          final ok = m1.contains("didn't catch that") && m2.contains("didn't hear anything") && out.spoken.isEmpty;
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, 'No match: "$m1"; timeout: "$m2"; spoken ${out.spoken.length}');
        });
    atc('ATC-M6-U13', req: 'M6-FR19.3', objective: 'A speech-synthesis failure still shows the reply', input: 'text-to-speech fails; "hello"',
        expected: 'Reply shown; speechOutputFailed true; state idle', run: () async {
          final (a, _, out, _) = await make();
          out.works = false;
          await a.submitText('hello');
          final ok = a.response != null && a.speechOutputFailed && a.state == VoiceState.idle;
          final msg = 'Reply present ${a.response != null}; output failed ${a.speechOutputFailed}; state ${a.state.name}';
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, msg);
        });
    atc('ATC-M6-U14', req: 'M6-FR19.4', objective: 'Closing releases the microphone and ignores a pending command', input: 'listening; close; late "pause workout"',
        expected: 'Recognizer cancelled once; session still active', run: () async {
          final rec = FakeSpeechRecognizer(), perm = FakePermissions();
          AppPermissions.instance = perm;
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final a = VoiceAssistantController(recognizer: rec, output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
          await a.startListening();
          await a.close();
          rec.hear('pause workout', isFinal: true);
          await _settle();
          AppPermissions.instance = const AppPermissions();
          return check(rec.cancelCalls == 1 && s.status == SessionStatus.active, 'Cancel calls ${rec.cancelCalls}; session ${s.status.name}');
        });
    atc('ATC-M6-U15', req: 'M6-FR19.3', objective: 'Replies never overlap; replay speaks the same reply once more', input: '"hello", then replay',
        expected: '2 identical utterances; at most 1 at a time', run: () async {
          final (a, _, out, _) = await make();
          await a.submitText('hello');
          await a.replay();
          final ok = out.spoken.length == 2 && out.spoken[0] == out.spoken[1] && out.maxConcurrent == 1;
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, 'Spoken ${out.spoken.length}; same ${out.spoken.length == 2 && out.spoken[0] == out.spoken[1]}; max concurrent ${out.maxConcurrent}');
        });
  });
}

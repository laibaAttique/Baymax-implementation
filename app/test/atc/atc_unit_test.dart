// Automated UNIT test cases (report section 5.1). Each case calls one function (or one small class) with stated inputs and compares
// the result with the expected one. IDs: ATC-M<module>-U<nn>. Run: flutter test test/atc/atc_unit_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart' hide same;
import 'package:app/models/consultation.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/specialist_plan.dart';
import 'package:app/screens/analytics/analytics_screen.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/diet_summary.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/food_parser.dart';
import 'package:app/services/gamification.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/login_guard.dart';
import 'package:app/services/mood_service.dart';
import 'package:app/services/ml/health_risk_model.dart';
import 'package:app/services/payment_gateway.dart';
import 'package:app/services/payment_rules.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/specialist_plan_apply.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/weight_projection.dart';
import 'package:app/services/xp_service.dart';
import 'package:app/models/payment.dart';
import 'package:app/models/food.dart';
import 'package:app/utils/health_calc.dart';
import 'package:app/utils/validators.dart';
import 'atc_helper.dart';

HealthProfile profile({
  String gender = 'Male',
  double height = 175,
  double weight = 70,
  int age = 30,
  List<String> conditions = const [],
  List<String> allergies = const [],
  String goal = 'Maintain & Stay Fit',
  String activity = 'Moderately Active',
  int freq = 4,
}) {
  final dob = DateTime(DateTime.now().year - age, 1, 1).toIso8601String().substring(0, 10);
  return HealthProfile(
    fullName: 'Test User', dob: dob, gender: gender, heightValue: height, weightValue: weight, medicalConditions: conditions,
    foodAllergies: allergies, primaryGoal: goal, activityLevel: activity, workoutFrequency: freq,
  );
}

String msg(String? m) => m == null ? 'Accepted (no error message)' : 'Rejected with the message "$m"';

DayRecord day(DateTime d, {bool planned = false, bool done = false, bool logged = false, double? kcal, int target = 2000}) =>
    DayRecord(date: d, planned: planned, workoutDone: done, foodLogged: logged, kcal: logged ? (kcal ?? 2000) : null, targetKcal: target);

void main() {
  late FoodDatabase db;
  const rules = RuleBasedClassifier();
  late HybridHealthClassifier hybrid;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
    hybrid = HybridHealthClassifier(rules, HealthRiskModel.fromJsonString(File('assets/models/health_classifier.json').readAsStringSync()));
  });

  // ---------------------------------------------------------------- Module 1: User Authentication & Onboarding
  group('Module 1 validators and login guard', () {
    atc('ATC-M1-U01', req: 'M1-FR5', objective: 'Email validator accepts a well-formed address', input: '"name@example.com"',
        expected: 'Accepted (no error message)', run: () { final r = Validators.email('name@example.com'); return check(r == null, msg(r)); });
    atc('ATC-M1-U02', req: 'M1-FR5', objective: 'Email validator rejects an address without a domain dot', input: '"a@b"',
        expected: 'Rejected with an error message', run: () { final r = Validators.email('a@b'); return check(r != null, msg(r)); });
    atc('ATC-M1-U03', req: 'M1-FR5', objective: 'Email validator rejects an empty value', input: '"" (empty string)',
        expected: 'Rejected with an error message', run: () { final r = Validators.email(''); return check(r != null, msg(r)); });
    atc('ATC-M1-U04', req: 'M1-FR5', objective: 'Password with 8+ characters, uppercase, number and symbol is accepted', input: '"Abcdef1!"',
        expected: 'Accepted (no error message)', run: () { final r = Validators.password('Abcdef1!'); return check(r == null, msg(r)); });
    atc('ATC-M1-U05', req: 'M1-FR5', objective: 'Password without an uppercase letter is rejected', input: '"abcdefg1!"',
        expected: 'Rejected with an error message', run: () { final r = Validators.password('abcdefg1!'); return check(r != null, msg(r)); });
    atc('ATC-M1-U06', req: 'M1-FR5', objective: 'Password without a symbol is rejected', input: '"Abcdefg1"',
        expected: 'Rejected with an error message', run: () { final r = Validators.password('Abcdefg1'); return check(r != null, msg(r)); });
    atc('ATC-M1-U07', req: 'M1-FR5', objective: 'Password shorter than 8 characters is rejected (boundary)', input: '"Ab1!" (4 characters)',
        expected: 'Rejected with an error message', run: () { final r = Validators.password('Ab1!'); return check(r != null, msg(r)); });
    atc('ATC-M1-U08', req: 'M1-FR5', objective: 'Confirm-password must match the password', input: 'password "Abcdef1!", confirmation "Abcdef1?"',
        expected: 'Rejected with an error message', run: () { final r = Validators.confirmPassword('Abcdef1!', 'Abcdef1?'); return check(r != null, msg(r)); });
    atc('ATC-M1-U09', req: 'M1-FR5', objective: 'A user who turns 13 tomorrow is too young (boundary)', input: 'date of birth 2013-10-16, today 2026-10-15',
        expected: 'Rejected with an error message', run: () { final r = Validators.dateOfBirth(DateTime(2013, 10, 16), now: DateTime(2026, 10, 15)); return check(r != null, msg(r)); });
    atc('ATC-M1-U10', req: 'M1-FR5', objective: 'A user who turns 13 today is accepted (boundary)', input: 'date of birth 2013-10-15, today 2026-10-15',
        expected: 'Accepted (no error message)', run: () { final r = Validators.dateOfBirth(DateTime(2013, 10, 15), now: DateTime(2026, 10, 15)); return check(r == null, msg(r)); });
    atc('ATC-M1-U11', req: 'M1-FR5', objective: 'Height below 50 cm is rejected (boundary)', input: '"49" cm',
        expected: 'Rejected with an error message', run: () { final r = Validators.height('49', 'cm'); return check(r != null, msg(r)); });
    atc('ATC-M1-U12', req: 'M1-FR5', objective: 'Height of 170 cm is accepted', input: '"170" cm',
        expected: 'Accepted (no error message)', run: () { final r = Validators.height('170', 'cm'); return check(r == null, msg(r)); });
    atc('ATC-M1-U13', req: 'M1-FR5', objective: 'Weight below 20 kg is rejected (boundary)', input: '"19" kg',
        expected: 'Rejected with an error message', run: () { final r = Validators.weight('19', 'kg'); return check(r != null, msg(r)); });
    atc('ATC-M1-U14', req: 'M1-FR5', objective: 'The weight range applies in pounds too', input: '"30" lbs (13.6 kg)',
        expected: 'Rejected with an error message', run: () { final r = Validators.weight('30', 'lbs'); return check(r != null, msg(r)); });
    atc('ATC-M1-U15', req: 'M1-FR2', objective: 'Five failed logins lock the account', input: 'five wrong passwords for a@x.com',
        expected: 'Account locked after the 5th failure', run: () {
          final g = LoginGuard(now: () => DateTime(2026, 10, 15, 9));
          for (var i = 0; i < 4; i++) { g.recordFailure('a@x.com'); }
          final before = g.lockedFor('a@x.com');
          g.recordFailure('a@x.com');
          final after = g.lockedFor('a@x.com');
          return check(before == null && after != null, 'Not locked after 4 failures; locked for ${after?.inMinutes} minutes after the 5th');
        });
    atc('ATC-M1-U16', req: 'M1-FR2', objective: 'The lock ends after 15 minutes', input: 'locked account, 14 min 59 s then 15 min 1 s later',
        expected: 'Still locked at 14:59, unlocked at 15:01', run: () {
          var now = DateTime(2026, 10, 15, 9);
          final g = LoginGuard(now: () => now);
          for (var i = 0; i < 5; i++) { g.recordFailure('a@x.com'); }
          now = now.add(const Duration(minutes: 14, seconds: 59));
          final still = g.lockedFor('a@x.com') != null;
          now = now.add(const Duration(seconds: 2));
          final freed = g.lockedFor('a@x.com') == null;
          return check(still && freed, 'At 14:59 locked = $still; at 15:01 unlocked = $freed');
        });
    atc('ATC-M1-U17', req: 'M1-FR2', objective: 'A successful login clears the failure count', input: '4 failures, then a successful login, then 1 failure',
        expected: 'Counter restarts (4 attempts left)', run: () {
          final g = LoginGuard(now: () => DateTime(2026, 10, 15));
          for (var i = 0; i < 4; i++) { g.recordFailure('a@x.com'); }
          g.recordSuccess('a@x.com');
          final left = g.recordFailure('a@x.com');
          return same(left, 4, say: 'Attempts left after the next failure: $left');
        });
  });

  // ---------------------------------------------------------------- Module 2: AI Health Classification Engine
  group('Module 2 health calculations and classification', () {
    atc('ATC-M2-U01', req: 'M2-FR2', objective: 'BMI is calculated from height and weight', input: 'weight 70 kg, height 175 cm',
        expected: 'BMI 22.86', run: () { final b = HealthCalc.bmi(70, 175); return check((b - 22.86).abs() < 0.01, 'BMI = ${b.toStringAsFixed(2)}'); });
    atc('ATC-M2-U02', req: 'M2-FR2', objective: 'BMI 27 is categorised as Overweight (WHO)', input: 'BMI 27',
        expected: '"Overweight"', run: () { final c = HealthCalc.whoCategory(27); return same(c, 'Overweight', say: 'Category = "$c"'); });
    atc('ATC-M2-U03', req: 'M2-FR5', objective: 'BMR (Mifflin-St Jeor) for a man', input: 'male, 70 kg, 175 cm, age 30',
        expected: '1648.75 kcal/day', run: () { final b = HealthCalc.bmr(gender: 'Male', weightKg: 70, heightCm: 175, age: 30); return check((b - 1648.75).abs() < 0.01, 'BMR = ${b.toStringAsFixed(2)} kcal/day'); });
    atc('ATC-M2-U04', req: 'M2-FR5', objective: 'BMR (Mifflin-St Jeor) for a woman', input: 'female, 60 kg, 165 cm, age 25',
        expected: '1345.25 kcal/day', run: () { final b = HealthCalc.bmr(gender: 'Female', weightKg: 60, heightCm: 165, age: 25); return check((b - 1345.25).abs() < 0.01, 'BMR = ${b.toStringAsFixed(2)} kcal/day'); });
    atc('ATC-M2-U05', req: 'M2-FR2', objective: 'Feet and pounds are converted before BMI is calculated', input: 'height 5.75 ft, weight 154 lbs',
        expected: 'BMI about 22.7', run: () {
          final p = profile(height: 5.75, weight: 154)..heightUnit = 'ft'..weightUnit = 'lbs';
          return check((p.bmi - 22.7).abs() < 0.1, '${p.heightCm.toStringAsFixed(1)} cm, ${p.weightKg.toStringAsFixed(1)} kg, BMI = ${p.bmi.toStringAsFixed(1)}');
        });
    atc('ATC-M2-U06', req: 'M2-FR1', objective: 'Age is calculated from the date of birth (day before the birthday)', input: 'born 2000-06-15, today 2026-06-14',
        expected: '25', run: () { final a = HealthCalc.ageFromDob('2000-06-15', now: DateTime(2026, 6, 14)); return same(a, 25, say: 'Age = $a'); });
    atc('ATC-M2-U07', req: 'M2-FR10', objective: 'Normal BMI and no conditions classify as Healthy', input: 'male 30, 175 cm, 70 kg, no conditions',
        expected: '"Healthy"', run: () { final c = rules.classify(profile()).category; return same(c, 'Healthy', say: 'Category = "$c"'); });
    atc('ATC-M2-U08', req: 'M2-FR10', objective: 'BMI 27.8 classifies as Overweight', input: '175 cm, 85 kg, no conditions',
        expected: '"Overweight"', run: () { final c = rules.classify(profile(weight: 85)).category; return same(c, 'Overweight', say: 'Category = "$c"'); });
    atc('ATC-M2-U09', req: 'M2-FR10', objective: 'BMI 32.7 classifies as Obese', input: '175 cm, 100 kg, no conditions',
        expected: '"Obese"', run: () { final c = rules.classify(profile(weight: 100)).category; return same(c, 'Obese', say: 'Category = "$c"'); });
    atc('ATC-M2-U10', req: 'M2-FR10', objective: 'Reported heart disease overrides BMI (Cardiac)', input: '100 kg, condition "Heart Disease"',
        expected: '"Cardiac"', run: () { final c = rules.classify(profile(weight: 100, conditions: ['Heart Disease'])).category; return same(c, 'Cardiac', say: 'Category = "$c"'); });
    atc('ATC-M2-U11', req: 'M2-FR10', objective: 'Reported diabetes classifies as Diabetic', input: '100 kg, condition "Diabetes"',
        expected: '"Diabetic"', run: () { final c = rules.classify(profile(weight: 100, conditions: ['Diabetes'])).category; return same(c, 'Diabetic', say: 'Category = "$c"'); });
    atc('ATC-M2-U12', req: 'M2-FR10', objective: 'Heart disease and diabetes together give the more cautious class', input: 'conditions "Heart Disease" and "Diabetes"',
        expected: '"Cardiac"', run: () { final c = rules.classify(profile(conditions: ['Heart Disease', 'Diabetes'])).category; return same(c, 'Cardiac', say: 'Category = "$c"'); });
    atc('ATC-M2-U13', req: 'M2-FR10', objective: 'Hypertension classifies as At-Risk', input: 'condition "Hypertension"',
        expected: '"At-Risk"', run: () { final c = rules.classify(profile(conditions: ['Hypertension'])).category; return same(c, 'At-Risk', say: 'Category = "$c"'); });
    atc('ATC-M2-U14', req: 'M2-FR10', objective: 'Underweight BMI (16.3) classifies as At-Risk', input: '175 cm, 50 kg',
        expected: '"At-Risk"', run: () { final c = rules.classify(profile(weight: 50)).category; return same(c, 'At-Risk', say: 'Category = "$c"'); });
    atc('ATC-M2-U15', req: 'M2-FR11', objective: 'Risk level and risk factors are listed', input: '100 kg, Hypertension, Dairy allergy',
        expected: 'Risk level High; factors include Hypertension and Dairy allergy', run: () {
          final r = rules.classify(profile(weight: 100, conditions: ['Hypertension'], allergies: ['Dairy']));
          return check(r.riskLevel == 'High' && r.riskFactors.contains('Hypertension') && r.riskFactors.contains('Dairy allergy'), 'Risk level ${r.riskLevel}; factors: ${r.riskFactors.join(', ')}');
        });
    atc('ATC-M2-U16', req: 'M2-FR9', objective: 'The Logistic Regression model never overrides a reported condition', input: 'conditions "Heart Disease"; then "Diabetes"',
        expected: '"Cardiac"; "Diabetic"', run: () {
          final a = hybrid.classify(profile(conditions: ['Heart Disease'])).category;
          final b = hybrid.classify(profile(conditions: ['Diabetes'])).category;
          return check(a == 'Cardiac' && b == 'Diabetic', 'Results: "$a"; "$b"');
        });
    atc('ATC-M2-U17', req: 'M2-FR9', objective: 'The model flags an obese 58-year-old that the rules alone would not', input: 'age 58, 175 cm, 117 kg, lightly active, nothing reported',
        expected: 'Rules alone: "Obese"; with the model: "At-Risk"', run: () {
          final p = profile(age: 58, weight: 117, activity: 'Lightly Active');
          final r1 = rules.classify(p).category;
          final r2 = hybrid.classify(p).category;
          return check(r1 == 'Obese' && r2 == 'At-Risk', 'Rules alone: "$r1"; with the model: "$r2"');
        });
    atc('ATC-M2-U18', req: 'M2-FR9', objective: 'The hybrid is never less cautious than the rules alone', input: 'ages 25/45/65 x weights 55/80/110 kg (9 people)',
        expected: 'No person gets a lower caution rank', run: () {
          const rank = {'Healthy': 0, 'Overweight': 1, 'Obese': 2, 'At-Risk': 3, 'Diabetic': 4, 'Cardiac': 5};
          var worse = 0;
          for (final age in [25, 45, 65]) {
            for (final w in [55.0, 80.0, 110.0]) {
              final p = profile(age: age, weight: w);
              if (rank[hybrid.classify(p).category]! < rank[rules.classify(p).category]!) worse++;
            }
          }
          return check(worse == 0, '$worse of 9 people were classified less cautiously');
        });
  });


  // ---------------------------------------------------------------- Module 3: Home Dashboard
  group('Module 3 mood and workout card', () {
    atc('ATC-M3-U01', req: 'M3-FR4', objective: 'The five moods have the report\'s labels in order', input: 'Mood.values', expected: 'Happy, Neutral, Sad, Angry, Stressed',
        run: () { final l = Mood.values.map((m) => m.label).join(', '); return same(l, 'Happy, Neutral, Sad, Angry, Stressed', say: 'Labels: $l'); });
    atc('ATC-M3-U02', req: 'M3-FR4', objective: 'Every mood has a suggestion and low moods are never pushed to train hard', input: 'The suggestion for each mood',
        expected: 'All non-empty; Sad is gentle, Stressed is low intensity, Angry is not maximal', run: () {
          final s = {for (final m in Mood.values) m: m.suggestion};
          final ok = s.values.every((v) => v.isNotEmpty) && s[Mood.sad]!.contains('gentle') && s[Mood.stressed]!.contains('low-intensity') && s[Mood.angry]!.contains('rather than anything maximal');
          return check(ok, 'Sad: "${s[Mood.sad]}" | Stressed: "${s[Mood.stressed]}" | Angry: "${s[Mood.angry]}"');
        });
    atc('ATC-M3-U03', req: 'M3-FR3', objective: 'The calorie estimate on the workout card grows with body weight', input: 'The first workout day of a plan at 50 kg and at 100 kg',
        expected: 'Positive, and higher at 100 kg than at 50 kg', run: () {
          final p = profile(goal: 'Lose Weight');
          final plan = PlanGenerator(db).generate(p, rules.classify(p));
          final day = plan.week.whereType<WorkoutDay>().first;
          final a = day.kcal(50), b = day.kcal(100);
          return check(a > 0 && b > a && day.durationMin > 0, '${day.durationMin} min; ${a} kcal at 50 kg; ${b} kcal at 100 kg');
        });
  });
  // ---------------------------------------------------------------- Module 4: Workout & Exercise
  group('Module 4 workout plan generation', () {
    PersonalizedPlan planFor(HealthProfile p, {int variant = 0}) => PlanGenerator(db).generate(p, rules.classify(p), variant: variant);
    Iterable<Exercise> exercisesOf(PersonalizedPlan plan) => plan.week.whereType<WorkoutDay>().expand((d) => d.exercises).map((e) => e.exercise);

    atc('ATC-M4-U01', req: 'M4-FR1', objective: 'Cardiac plan has only low-impact exercises and no HIIT or isometric holds', input: 'condition "Heart Disease", goal Lose Weight, 6 days requested',
        expected: 'Low intensity, at most 4 days, no high-impact / HIIT / isometric exercise', run: () {
          final plan = planFor(profile(conditions: ['Heart Disease'], goal: 'Lose Weight', freq: 6));
          final bad = exercisesOf(plan).where((e) => e.impact != 'low' || e.tags.contains('hiit') || e.tags.contains('isometric')).length;
          return check(plan.intensity == 'Low' && plan.workoutDays <= 4 && bad == 0, 'Intensity ${plan.intensity}; ${plan.workoutDays} workout days; $bad restricted exercises');
        });
    atc('ATC-M4-U02', req: 'M4-FR1', objective: 'Obese plan contains no high-impact exercise', input: '175 cm, 105 kg, goal Lose Weight, 5 days',
        expected: 'Zero high-impact exercises', run: () {
          final plan = planFor(profile(weight: 105, goal: 'Lose Weight', freq: 5));
          final high = exercisesOf(plan).where((e) => e.impact == 'high').length;
          return check(plan.category == 'Obese' && high == 0, 'Category ${plan.category}; $high high-impact exercises');
        });
    atc('ATC-M4-U03', req: 'M4-FR3', objective: 'Hypertension keeps isometric holds to 20 seconds or less', input: 'condition "Hypertension"',
        expected: 'Every timed hold is at most 20 s; no HIIT', run: () {
          final plan = planFor(profile(conditions: ['Hypertension']));
          final holds = plan.week.whereType<WorkoutDay>().expand((d) => d.exercises).where((e) => e.exercise.tags.contains('isometric'));
          final longest = holds.fold<int>(0, (m, e) => e.seconds > m ? e.seconds : m);
          final hiit = exercisesOf(plan).where((e) => e.tags.contains('hiit')).length;
          return check(longest <= 20 && hiit == 0, 'Longest isometric hold $longest s; $hiit HIIT exercises');
        });
    atc('ATC-M4-U04', req: 'M4-FR5', objective: 'Every workout day starts with a warm-up and ends with a cool-down', input: 'default healthy profile, 4 days',
        expected: 'Warm-up first and cool-down last on every day', run: () {
          final plan = planFor(profile());
          final days = plan.week.whereType<WorkoutDay>().toList();
          final okAll = days.every((d) => d.exercises.first.exercise.id == 'warmup' && d.exercises.last.exercise.id == 'cooldown');
          return check(days.isNotEmpty && okAll, '${days.length} workout days checked; warm-up first and cool-down last on all = $okAll');
        });
    atc('ATC-M4-U05', req: 'M4-FR2', objective: 'Balance training is added from age 65, not before', input: 'age 64 and age 66',
        expected: 'No balance exercise at 64; at least one at 66', run: () {
          int balance(PersonalizedPlan p) => exercisesOf(p).where((e) => e.tags.contains('balance')).length;
          final young = balance(planFor(profile(age: 64)));
          final older = balance(planFor(profile(age: 66)));
          return check(young == 0 && older > 0, 'Balance exercises at 64: $young; at 66: $older');
        });
    atc('ATC-M4-U06', req: 'M4-FR5', objective: 'Regenerating the plan changes the exercises', input: 'plan variant 0 versus variant 1',
        expected: 'Different exercise selection', run: () {
          String sig(PersonalizedPlan p) => exercisesOf(p).map((e) => e.id).join(',');
          final a = sig(planFor(profile(), variant: 0));
          final b = sig(planFor(profile(), variant: 1));
          return check(a != b, 'Variant 0 and variant 1 give ${a == b ? 'the same' : 'different'} exercises');
        });
  });

  // ---------------------------------------------------------------- Module 8: Smart Diet & Calorie Tracking
  group('Module 8 food logging logic', () {
    late FoodParser parser;
    setUp(() => parser = FoodParser(db));

    atc('ATC-M8-U01', req: 'M8-FR8', objective: 'Text entry is parsed into foods and servings', input: '"2 rotis and a bowl of daal"',
        expected: '2 x roti (220 kcal) and 1 x daal', run: () {
          final r = parser.parse('2 rotis and a bowl of daal');
          final ok = r.length == 2 && r[0].item!.id == 'roti' && r[0].servings == 2 && (r[0].kcal - 220).abs() < 0.5 && r[1].item!.id == 'daal' && r[1].servings == 1;
          return check(ok, 'Found ${r.map((p) => '${p.servings} x ${p.item?.id}').join(' and ')}; roti = ${r[0].kcal.toStringAsFixed(0)} kcal');
        });
    atc('ATC-M8-U02', req: 'M8-FR8', objective: 'Gram quantities scale by serving weight', input: '"150g grilled chicken breast"',
        expected: 'About 248 kcal', run: () { final r = parser.parse('150g grilled chicken breast'); return check((r.single.kcal - 248).abs() < 1, '${r.single.item!.name}: ${r.single.kcal.toStringAsFixed(1)} kcal'); });
    atc('ATC-M8-U03', req: 'M8-FR8', objective: 'Fractions are understood', input: '"half a cup of rice"',
        expected: '0.5 servings', run: () { final r = parser.parse('half a cup of rice'); return same(r.single.servings, 0.5, say: 'Servings = ${r.single.servings}'); });
    atc('ATC-M8-U04', req: 'M8-FR8', objective: 'An unknown food is reported rather than guessed', input: '"2 eggs, toast + green tea and blorptastic"',
        expected: 'Four parts; the unknown one has no food', run: () {
          final r = parser.parse('2 eggs, toast + green tea and blorptastic');
          return check(r.length == 4 && r.last.item == null && r.take(3).every((p) => p.item != null), 'Parts: ${r.map((p) => p.item?.id ?? 'UNKNOWN').join(', ')}');
        });
    atc('ATC-M8-U05', req: 'M8-FR7', objective: 'Food search finds a food from a partial name', input: '"chick"',
        expected: 'Results include grilled chicken', run: () { final ids = db.search('chick', limit: 20).map((f) => f.id).toList(); return check(ids.contains('grilled_chicken'), 'Found: ${ids.take(5).join(', ')}'); });
    atc('ATC-M8-U06', req: 'M8-FR2', objective: 'Macro shares always add up to 100%', input: 'protein 33.3 g, carbs 66.6 g, fat 12.1 g',
        expected: 'Shares sum to 100', run: () { final m = MacroShare.fromGrams(protein: 33.3, carbs: 66.6, fat: 12.1); return check(m.protein + m.carbs + m.fat == 100, '${m.protein}% + ${m.carbs}% + ${m.fat}% = ${m.protein + m.carbs + m.fat}%'); });
    atc('ATC-M8-U07', req: 'M8-FR4', objective: 'Calories are totalled by meal slot', input: 'Breakfast 300 + 100 kcal, Lunch 500 kcal',
        expected: 'Breakfast 400, Lunch 500, Dinner 0', run: () {
          FoodEntry e(String meal, double kcal) => FoodEntry(date: '2026-10-15', meal: meal, name: 'x', quantity: 1, unit: 'serving', kcal: kcal, protein: 0, carbs: 0, fat: 0);
          final by = kcalByMeal([e('Breakfast', 300), e('Lunch', 500), e('Breakfast', 100)]);
          return check(by['Breakfast'] == 400 && by['Lunch'] == 500 && by['Dinner'] == 0, 'Breakfast ${by['Breakfast']}, Lunch ${by['Lunch']}, Dinner ${by['Dinner']}');
        });
    atc('ATC-M8-U08', req: 'M8-FR13', objective: 'Net calories = consumed minus burned', input: 'consumed 1800, burned 350',
        expected: '1450', run: () { final n = netKcal(consumed: 1800, burned: 350); return same(n, 1450, say: 'Net = $n'); });
    atc('ATC-M8-U09', req: 'M8-FR13', objective: 'The daily verdict never praises a very low intake', input: 'goal Lose Weight, consumed 600, target 1800, BMR 1500',
        expected: 'Mentions "very low intake"', run: () { final v = dailyVerdict(goal: 'Lose Weight', consumed: 600, target: 1800, bmr: 1500); return check(v.contains('very low intake'), 'Verdict: "$v"'); });
    atc('ATC-M8-U10', req: 'M8-FR13', objective: 'The daily verdict recognises a day on target', input: 'goal Lose Weight, consumed 1790, target 1800, BMR 1500',
        expected: 'Says "right on your daily target"', run: () { final v = dailyVerdict(goal: 'Lose Weight', consumed: 1790, target: 1800, bmr: 1500); return check(v.contains('right on your daily target'), 'Verdict: "$v"'); });
  });

  // ---------------------------------------------------------------- Module 9: Nutrition Plan
  group('Module 9 nutrition plan', () {
    PersonalizedPlan planFor(HealthProfile p, {int variant = 0}) => PlanGenerator(db).generate(p, rules.classify(p), variant: variant);

    atc('ATC-M9-U01', req: 'M9-FR2', objective: 'Protein, carbs and fat add up to the calorie target', input: 'goal Lose Weight, 175 cm, 70 kg',
        expected: 'Macro calories within 40 kcal of the target', run: () {
          final n = planFor(profile(goal: 'Lose Weight')).nutrition;
          final fromMacros = n.proteinG * 4 + n.carbsG * 4 + n.fatG * 9;
          return check((fromMacros - n.targetKcal).abs() < 40, 'Macros give $fromMacros kcal; target ${n.targetKcal} kcal');
        });
    atc('ATC-M9-U02', req: 'M9-FR6', objective: 'A meal plan never contains the user\'s allergens', input: 'allergies Dairy, Gluten, Eggs, Nuts; 6 plan variants',
        expected: 'No allergen in any meal of any variant', run: () {
          final p = profile(allergies: ['Dairy', 'Gluten', 'Eggs', 'Nuts'], goal: 'Lose Weight');
          var conflicts = 0, items = 0;
          for (var v = 0; v < 6; v++) {
            for (final list in planFor(p, variant: v).nutrition.meals.values) {
              for (final i in list) { items++; conflicts += i.food.conflictsWith(p.allergies).length; }
            }
          }
          return check(conflicts == 0 && items > 0, '$items meal items checked across 6 variants; $conflicts allergen conflicts');
        });
    atc('ATC-M9-U03', req: 'M9-FR6', objective: 'A diabetic meal plan has no high-sugar or refined foods', input: 'condition "Diabetes"; 6 plan variants',
        expected: 'None of the foods is tagged highSugar or refined', run: () {
          var bad = 0, items = 0;
          for (var v = 0; v < 6; v++) {
            for (final list in planFor(profile(conditions: ['Diabetes']), variant: v).nutrition.meals.values) {
              for (final i in list) { items++; if (i.food.tags.contains('highSugar') || i.food.tags.contains('refined')) bad++; }
            }
          }
          return check(bad == 0 && items > 0, '$items items checked; $bad high-sugar or refined foods');
        });
    atc('ATC-M9-U04', req: 'M9-FR5', objective: 'Meal calories land near the daily target', input: '175 cm, 75 kg',
        expected: 'Total of meals between 75% and 125% of the target', run: () {
          final n = planFor(profile(weight: 75)).nutrition;
          final total = n.meals.keys.fold(0.0, (s, m) => s + n.mealKcal(m));
          return check(total >= n.targetKcal * 0.75 && total <= n.targetKcal * 1.25, 'Meals total ${total.round()} kcal; target ${n.targetKcal} kcal');
        });
    atc('ATC-M9-U05', req: 'M9-FR1', objective: 'The calorie deficit never goes below the safe floor', input: 'female, BMR 1100, maintenance 1500, BMI 22',
        expected: 'Deficit target is 1200 kcal and a safety note is given', run: () {
          final t = HealthCalc.calorieTargets(bmr: 1100, tdee: 1500, gender: 'Female', bmi: 22);
          return check(t.deficit == 1200 && t.safetyNote != null, 'Deficit ${t.deficit} kcal; note: "${t.safetyNote}"');
        });
    atc('ATC-M9-U06', req: 'M9-FR1', objective: 'No calorie deficit is set for an underweight user', input: 'female, BMR 1300, maintenance 1800, BMI 17',
        expected: 'Deficit target equals maintenance', run: () { final u = HealthCalc.calorieTargets(bmr: 1300, tdee: 1800, gender: 'Female', bmi: 17); return check(u.deficit == u.maintain, 'Deficit ${u.deficit}, maintenance ${u.maintain}'); });
    atc('ATC-M9-U07', req: 'M9-FR1', objective: 'Diabetic macros cap carbohydrates at 40% of calories', input: '2000 kcal, 70 kg, diabetic',
        expected: 'Carbohydrate share at most 40%', run: () { final m = HealthCalc.macros(kcal: 2000, weightKg: 70, goal: 'Maintain & Stay Fit', diabetic: true); final share = m.carbsG * 4 / 2000; return check(share <= 0.401, 'Carbohydrates ${m.carbsG} g = ${(share * 100).toStringAsFixed(1)}% of calories'); });
    atc('ATC-M9-U08', req: 'M9-FR7', objective: 'Three nutrition tips a day and none repeats within a week', input: 'pool of 28 tips, 7 consecutive days',
        expected: '3 tips per day, 21 different tips in 7 days', run: () {
          final pool = [for (var i = 0; i < 28; i++) 'tip $i'];
          final plan = NutritionPlan(goalLabel: 'x', targetKcal: 2000, proteinG: 100, carbsG: 200, fatG: 60, waterLitres: 2, meals: const {}, avoid: const [], tips: const [], tipPool: pool);
          final seen = <String>{};
          var perDayOk = true;
          for (var d = 0; d < 7; d++) {
            final t = plan.tipsFor(DateTime(2026, 10, 15).add(Duration(days: d)));
            if (t.length != 3) perDayOk = false;
            seen.addAll(t);
          }
          return check(perDayOk && seen.length == 21, 'Tips per day all 3 = $perDayOk; different tips in 7 days = ${seen.length}');
        });
  });

  // ---------------------------------------------------------------- Module 10: Allergy & Ingredient Scanner
  group('Module 10 allergen matching', () {
    const label = 'INGREDIENTS: Wheat flour, sugar, milk powder, soy oil, peanut butter, salt, emulsifier (E322).';
    atc('ATC-M10-U01', req: 'M10-FR3', objective: 'Allergens on a label are found for a user with those allergies', input: 'label with wheat, milk, soy, peanut; allergies Dairy, Nuts, Gluten, Soy, Shellfish',
        expected: 'Dairy, Nuts, Gluten and Soy found; not safe', run: () {
          final r = AllergenMatcher.analyze(label, ['Dairy', 'Nuts', 'Gluten', 'Soy', 'Shellfish']);
          final found = (r.allergensFound.toList()..sort()).join(', ');
          return check(r.allergensFound.length == 4 && !r.isSafe && !r.allergensFound.contains('Shellfish'), 'Found: $found; safe = ${r.isSafe}');
        });
    atc('ATC-M10-U02', req: 'M10-FR3', objective: 'Only the user\'s own allergies are checked', input: 'same label; allergy Shellfish only',
        expected: 'Product is safe', run: () { final r = AllergenMatcher.analyze(label, ['Shellfish']); return check(r.isSafe, 'Safe = ${r.isSafe}'); });
    atc('ATC-M10-U03', req: 'M10-FR4', objective: 'Look-alike ingredients are not flagged', input: 'coconut milk, cocoa butter, rice flour, nutmeg, eggplant, almond milk; allergies Dairy, Gluten, Nuts, Eggs',
        expected: 'Only Nuts (almond milk)', run: () {
          final r = AllergenMatcher.analyze('Ingredients: coconut milk, cocoa butter, rice flour, nutmeg, eggplant, almond milk', ['Dairy', 'Gluten', 'Nuts', 'Eggs']);
          return check(r.allergensFound.length == 1 && r.allergensFound.contains('Nuts'), 'Found: ${r.allergensFound.join(', ')}');
        });
    atc('ATC-M10-U04', req: 'M10-FR4', objective: 'OCR digit/letter confusion is tolerated', input: '"mi1k solids" (digit 1 instead of l); allergy Dairy',
        expected: 'Dairy found', run: () { final r = AllergenMatcher.analyze('Ingredients: sugar, mi1k solids, salt', ['Dairy']); return check(r.allergensFound.contains('Dairy'), 'Found: ${r.allergensFound.join(', ')}'); });
    atc('ATC-M10-U05', req: 'M10-FR4', objective: 'A small spelling error is tolerated (fuzzy match)', input: '"buttter" (extra t); allergy Dairy',
        expected: 'Dairy found by an approximate match', run: () {
          final r = AllergenMatcher.analyze('Ingredients: sugar, buttter, salt', ['Dairy']);
          final exact = r.ingredients.firstWhere((i) => i.flagged).hits.single.exact;
          return check(r.allergensFound.contains('Dairy') && !exact, 'Found: ${r.allergensFound.join(', ')}; exact match = $exact');
        });
    atc('ATC-M10-U06', req: 'M10-FR6', objective: '"May contain" statements are reported as trace risk', input: '"May contain traces of peanuts and milk"; allergies Nuts, Dairy',
        expected: 'No direct hit; trace allergens Nuts and Dairy; not safe', run: () {
          final r = AllergenMatcher.analyze('Ingredients: rice, salt. May contain traces of peanuts and milk.', ['Nuts', 'Dairy']);
          return check(!r.hasDirectHit && r.traceAllergens.length == 2 && !r.isSafe, 'Direct hit = ${r.hasDirectHit}; trace: ${r.traceAllergens.join(', ')}; safe = ${r.isSafe}');
        });
  });

  // ---------------------------------------------------------------- Module 11: Predictive Body Transformation (straight-line projection)
  group('Module 11 weight projection', () {
    final today = DateTime(2026, 10, 14);
    List<WeightPoint> line(double perDay, {int n = 8, int stepDays = 3, double start = 70}) =>
        [for (var i = 0; i < n; i++) WeightPoint(today.subtract(Duration(days: (n - 1 - i) * stepDays)), start + perDay * i * stepDays)];
    atc('ATC-M11-U01', req: 'M11-FR5', objective: 'Too few weigh-ins give no projection and say why', input: '3 weigh-ins',
        expected: 'Not reliable; a reason is given', run: () { final p = projectWeight(weights: line(-0.05, n: 3), today: today); return check(!p.reliable && p.note != null, 'Reliable = ${p.reliable}; note: "${p.note}"'); });
    atc('ATC-M11-U02', req: 'M11-FR5', objective: 'A steady loss is extrapolated and the time to the target is worked out', input: '8 weigh-ins falling 0.05 kg/day, target 68 kg',
        expected: 'About -0.35 kg/week and a number of weeks to the target', run: () {
          final p = projectWeight(weights: line(-0.05), today: today, targetKg: 68);
          return check(p.reliable && (p.kgPerWeek! + 0.35).abs() < 1e-6 && p.weeksToTarget != null && p.weeksToTarget! > 0, '${p.kgPerWeek!.toStringAsFixed(2)} kg/week; ${p.weeksToTarget!.toStringAsFixed(1)} weeks to the target');
        });
    atc('ATC-M11-U03', req: 'M11-FR5', objective: 'A trend leading away from the target gives no time to target', input: '8 weigh-ins rising 0.05 kg/day, target 60 kg',
        expected: 'No weeks-to-target value', run: () { final p = projectWeight(weights: line(0.05), today: today, targetKg: 60); return check(p.weeksToTarget == null, 'Weeks to target = ${p.weeksToTarget}'); });
  });

  // ---------------------------------------------------------------- Module 12: Community Ranking & Gamification
  group('Module 12 scoring, badges and levels', () {
    final mon = DateTime(2026, 10, 12);
    final today = DateTime(2026, 10, 15);
    List<DayRecord> run(DateTime last, List<bool> activeOldestFirst) {
      final n = activeOldestFirst.length;
      return [for (var i = 0; i < n; i++) day(last.subtract(Duration(days: n - 1 - i)), done: activeOldestFirst[i])];
    }

    atc('ATC-M12-U01', req: 'M12-FR1', objective: 'A perfect week scores 100', input: '2 planned workouts done, food logged every day on target',
        expected: 'Score 100', run: () {
          final days = [for (var i = 0; i < 4; i++) day(mon.add(Duration(days: i)), planned: i.isEven, done: i.isEven, logged: true)];
          final s = Gamification.weeklyScore(days).total;
          return check((s - 100).abs() < 1e-9, 'Score = $s');
        });
    atc('ATC-M12-U02', req: 'M12-FR1', objective: 'A week with nothing done scores 0', input: '4 planned days, nothing done or logged',
        expected: 'Score 0', run: () { final s = Gamification.weeklyScore([for (var i = 0; i < 4; i++) day(mon.add(Duration(days: i)), planned: true)]).total; return same(s, 0, say: 'Score = $s'); });
    atc('ATC-M12-U03', req: 'M12-FR1', objective: 'Score parts are weighted 50 / 25 / 25', input: 'training 50%, logging 50%, calories on target 50%',
        expected: 'Score 50', run: () {
          final days = [
            day(mon, planned: true, done: true, logged: true, kcal: 2000),
            day(mon.add(const Duration(days: 1)), planned: true, logged: true, kcal: 900),
            day(mon.add(const Duration(days: 2))),
            day(mon.add(const Duration(days: 3))),
          ];
          final s = Gamification.weeklyScore(days).total;
          return check((s - 50).abs() < 1e-9, 'Score = $s');
        });
    atc('ATC-M12-U04', req: 'M12-FR4', objective: 'Score thresholds map to Beginner / Intermediate / Advanced (boundary values)', input: 'scores 39.9, 40, 69.9, 70',
        expected: 'Beginner, Intermediate, Intermediate, Advanced', run: () {
          final r = [39.9, 40.0, 69.9, 70.0].map((s) => Gamification.levelForScore(s).name).toList();
          return check(r.join(',') == 'beginner,intermediate,intermediate,advanced', 'Levels: ${r.join(', ')}');
        });
    atc('ATC-M12-U05', req: 'M12-FR4', objective: 'K-Means groups a cohort of 15 into three tiers', input: '6 low, 6 mid and 6 high scorers',
        expected: 'Low = Beginner, mid = Intermediate, high = Advanced; method is K-Means', run: () {
          final members = [
            for (var i = 0; i < 6; i++) CohortMember('low$i', 10 + i.toDouble(), 0, 1),
            for (var i = 0; i < 6; i++) CohortMember('mid$i', 50 + i.toDouble(), 3, 4),
            for (var i = 0; i < 6; i++) CohortMember('high$i', 90 + i.toDouble(), 6, 7),
          ];
          final r = groupCohort(members);
          return check(r.method.startsWith('K-Means') && r.levels['low0'] == FitnessLevel.beginner && r.levels['mid3'] == FitnessLevel.intermediate && r.levels['high5'] == FitnessLevel.advanced,
              'Method "${r.method}"; low0 ${r.levels['low0']?.name}, mid3 ${r.levels['mid3']?.name}, high5 ${r.levels['high5']?.name}');
        });
    atc('ATC-M12-U06', req: 'M12-FR8', objective: 'A streak counts consecutive active days and today may still be empty', input: 'active, active, active; then active, active, not yet',
        expected: '3; then 2', run: () {
          final a = Gamification.activeStreak(run(today, [true, true, true]));
          final b = Gamification.activeStreak(run(today, [true, true, false]));
          return check(a == 3 && b == 2, 'Streaks: $a and $b');
        });
    atc('ATC-M12-U07', req: 'M12-FR6', objective: '7-day and 30-day streak badges are earned only at their threshold', input: '6, 7 and 30 active days',
        expected: '6 days: no badge; 7 days: daily_7; 30 days: daily_7 and daily_30', run: () {
          final six = Gamification.earnedBadgeIds(run(today, List.filled(6, true)), today);
          final seven = Gamification.earnedBadgeIds(run(today, List.filled(7, true)), today);
          final thirty = Gamification.earnedBadgeIds(run(today, List.filled(30, true)), today);
          return check(!six.contains('daily_7') && seven.contains('daily_7') && !seven.contains('daily_30') && thirty.contains('daily_7') && thirty.contains('daily_30'),
              '6 days: ${six.contains('daily_7')}; 7 days: ${seven.contains('daily_7')}/${seven.contains('daily_30')}; 30 days: ${thirty.contains('daily_7')}/${thirty.contains('daily_30')}');
        });
    atc('ATC-M12-U08', req: 'M12-FR7', objective: 'The badge catalogue marks earned badges and keeps locked ones', input: 'a 7-day streak',
        expected: 'Catalogue of 10 badges, daily_7 earned and others locked', run: () {
          final earned = Gamification.earnedBadgeIds(run(today, List.filled(7, true)), today);
          return check(Gamification.catalogue.length == 10 && earned.contains('daily_7') && earned.length < Gamification.catalogue.length, '${Gamification.catalogue.length} badges in the catalogue; ${earned.length} earned');
        });
    atc('ATC-M12-U09', req: 'M12-FR10', objective: 'XP levels start at 100 x L x (L-1)', input: 'XP 0, 199, 200, 599, 600',
        expected: 'Levels 1, 1, 2, 2, 3', run: () { final l = [0, 199, 200, 599, 600].map(Xp.levelOf).toList(); return check(l.join(',') == '1,1,2,2,3', 'Levels: ${l.join(', ')}'); });
  });

  // ---------------------------------------------------------------- Module 13: AI Chatbot
  group('Module 13 chatbot', () {
    const bot = ChatbotEngine();
    late ChatContext ctx;
    setUp(() {
      final p = profile(allergies: ['Dairy'], goal: 'Lose Weight');
      final cls = rules.classify(p);
      ctx = ChatContext(profile: p, classification: cls, plan: PlanGenerator(db).generate(p, cls), db: db, consumedKcal: 600, now: DateTime(2026, 10, 12, 13));
    });
    atc('ATC-M13-U01', req: 'M13-FR1', objective: 'Intent is detected from typed text', input: '"what is my bmi"',
        expected: 'Intent "bmi"', run: () { final r = bot.respond('what is my bmi', ctx); return same(r.intent, 'bmi', say: 'Intent = "${r.intent}"'); });
    atc('ATC-M13-U02', req: 'M13-FR3', objective: 'Calories left today come from the real food log', input: '"how many calories left" with 600 kcal logged',
        expected: 'Answer contains 600', run: () { final r = bot.respond('how many calories left', ctx); return check(r.text.contains('600'), 'Answer: "${r.text.split('\n').first}"'); });
    atc('ATC-M13-U03', req: 'M13-FR3', objective: 'Calorie lookup adds up several foods', input: '"How many calories in 2 rotis and daal?"',
        expected: 'Intent calorie_lookup, 450 kcal (220 + 230)', run: () { final r = bot.respond('How many calories in 2 rotis and daal?', ctx); return check(r.intent == 'calorie_lookup' && r.text.contains('450 kcal'), 'Intent "${r.intent}"; answer mentions 450 kcal = ${r.text.contains('450 kcal')}'); });
    atc('ATC-M13-U04', req: 'M13-FR4', objective: 'A symptom message recommends a specialist consultation', input: '"my knee hurts after squats"',
        expected: 'Intent health_concern with a "Book a consultation" action', run: () {
          final r = bot.respond('my knee hurts after squats', ctx);
          return check(r.intent == 'health_concern' && r.actions.any((a) => a.type == 'consult'), 'Intent "${r.intent}"; actions: ${r.actions.map((a) => a.type).join(', ')}');
        });
    atc('ATC-M13-U05', req: 'M13-FR4', objective: 'Chest pain is treated as an emergency', input: '"I have chest pain"',
        expected: 'Intent emergency and the word "emergency" in the answer', run: () { final r = bot.respond('I have chest pain', ctx); return check(r.intent == 'emergency' && r.text.contains('emergency'), 'Intent "${r.intent}"'); });
    atc('ATC-M13-U06', req: 'M13-FR3', objective: 'The bot warns when a food is on the user\'s allergy list', input: '"can I eat butter chicken?" with a Dairy allergy',
        expected: 'Answer says it is on the allergy list', run: () { final r = bot.respond('can I eat butter chicken?', ctx); return check(r.text.contains('on your allergy list'), 'Warns about the allergy = ${r.text.contains('on your allergy list')}'); });
    atc('ATC-M13-U07', req: 'M13-FR2', objective: 'Nonsense input gets a polite fallback', input: '"asdfgh qwerty"',
        expected: 'Intent "fallback"', run: () { final r = bot.respond('asdfgh qwerty', ctx); return same(r.intent, 'fallback', say: 'Intent = "${r.intent}"'); });
  });

  // ---------------------------------------------------------------- Module 14: Online Consultation
  group('Module 14 consultation rules', () {
    final now = DateTime.utc(2026, 10, 19, 3, 0); // Monday 08:00 in Pakistan
    Specialist spec({String id = 's', String name = 'Sara Khan', SpecialistType type = SpecialistType.nutritionist, String specialty = 'Weight management', double rating = 4.8, int reviews = 40, bool available = true, bool emergency = false}) =>
        Specialist(id: id, name: name, type: type, specialty: specialty, rating: rating, reviewCount: reviews, videoFee: 2000, chatFee: 1200, available: available, emergency: emergency);
    Appointment appt(AppointmentStatus status, {DateTime? start, String link = 'https://meet.example/room'}) => Appointment(
        id: 'a', patientId: 'p', patientName: 'P', specialistId: 's', specialistName: 'Dr', role: SpecialistType.doctor, startAt: start ?? now.add(const Duration(days: 1)),
        durationMinutes: 30, type: ConsultType.video, status: status, fee: 2000, meetingLink: link, createdAt: now);

    atc('ATC-M14-U01', req: 'M14-FR2', objective: 'Time slots follow the specialist\'s own clock', input: 'Monday 09:00-17:00, 30-minute slots, Pakistan time (UTC+5)',
        expected: '16 slots, first at 04:00 UTC, last at 11:30 UTC', run: () {
          final s = spec();
          final slots = ConsultationRules.daySlots(s, ConsultationRules.specialistToday(s, now));
          return check(slots.length == 16 && slots.first == DateTime.utc(2026, 10, 19, 4) && slots.last == DateTime.utc(2026, 10, 19, 11, 30), '${slots.length} slots; first ${slots.first.toIso8601String()}; last ${slots.last.toIso8601String()}');
        });
    atc('ATC-M14-U02', req: 'M14-FR2', objective: 'A day off has no slots', input: 'Saturday for a Monday-Friday specialist',
        expected: 'No slots', run: () { final r = ConsultationRules.daySlots(spec(), DateTime.utc(2026, 10, 24)); return check(r.isEmpty, '${r.length} slots'); });
    atc('ATC-M14-U03', req: 'M14-FR2', objective: 'Booked times and times that are too soon are not offered', input: '08:50 now; 09:00 too soon, 09:30 booked',
        expected: 'First open slot is 10:00; 14 slots offered', run: () {
          final open = ConsultationRules.openSlots(spec(), DateTime.utc(2026, 10, 19), now: DateTime.utc(2026, 10, 19, 3, 50), booked: {DateTime.utc(2026, 10, 19, 4, 30).millisecondsSinceEpoch});
          return check(open.first == DateTime.utc(2026, 10, 19, 5) && open.length == 14, 'First open slot ${open.first.toIso8601String()}; ${open.length} slots');
        });
    atc('ATC-M14-U04', req: 'M14-FR2', objective: 'A specialist who is not taking bookings offers nothing', input: 'available = false',
        expected: 'No open slots', run: () { final r = ConsultationRules.openSlots(spec(available: false), DateTime.utc(2026, 10, 19), now: now); return check(r.isEmpty, '${r.length} slots'); });
    atc('ATC-M14-U05', req: 'M14-FR2', objective: 'A note of exactly 500 characters is accepted (boundary)', input: 'note of 500 characters',
        expected: 'No booking problem', run: () { final p = ConsultationRules.bookingProblem(specialist: spec(), slot: DateTime.utc(2026, 10, 19, 5), notes: 'x' * 500, now: now); return check(p == null, p ?? 'No problem found'); });
    atc('ATC-M14-U06', req: 'M14-FR2', objective: 'A note of 501 characters is rejected (boundary)', input: 'note of 501 characters',
        expected: 'Booking problem mentioning 500', run: () { final p = ConsultationRules.bookingProblem(specialist: spec(), slot: DateTime.utc(2026, 10, 19, 5), notes: 'x' * 501, now: now); return check(p != null && p.contains('500'), 'Problem: "$p"'); });
    atc('ATC-M14-U07', req: 'M14-FR2', objective: 'A slot that was just taken is refused', input: 'slot 10:00 already booked',
        expected: 'Message says the time was just taken', run: () { final s = DateTime.utc(2026, 10, 19, 5); final p = ConsultationRules.bookingProblem(specialist: spec(), slot: s, notes: '', now: now, booked: {s.millisecondsSinceEpoch}); return check(p != null && p.contains('just taken'), 'Problem: "$p"'); });
    atc('ATC-M14-U08', req: 'M14-FR1', objective: 'The specialist list filters by type', input: 'doctor, nutritionist and trainer; filter = trainer',
        expected: 'Only the trainer', run: () {
          final all = [spec(id: 'd', type: SpecialistType.doctor), spec(id: 'n'), spec(id: 't', type: SpecialistType.trainer)];
          final r = ConsultationRules.filter(all, type: SpecialistType.trainer, now: now);
          return check(r.length == 1 && r.first.id == 't', 'Result: ${r.map((s) => s.id).join(', ')}');
        });
    atc('ATC-M14-U09', req: 'M14-FR1', objective: 'Search matches name or specialty, ignoring case', input: '"SPORTS"',
        expected: 'The sports nutritionist', run: () {
          final all = [spec(id: 'n', specialty: 'Sports nutrition'), spec(id: 'o', specialty: 'Diabetes')];
          final r = ConsultationRules.filter(all, query: 'SPORTS', now: now);
          return check(r.length == 1 && r.first.id == 'n', 'Result: ${r.map((s) => s.id).join(', ')}');
        });
    atc('ATC-M14-U10', req: 'M14-FR1', objective: '"Top rated" needs 4.5 stars and at least one review', input: 'rating 4.9/80 reviews, rating 4.7/0 reviews, rating 4.2/10 reviews',
        expected: 'Only the first', run: () {
          final all = [spec(id: 'a', rating: 4.9, reviews: 80), spec(id: 'b', rating: 4.7, reviews: 0), spec(id: 'c', rating: 4.2, reviews: 10)];
          final r = ConsultationRules.filter(all, topRated: true, now: now);
          return check(r.length == 1 && r.first.id == 'a', 'Result: ${r.map((s) => s.id).join(', ')}');
        });
    atc('ATC-M14-U11', req: 'M14-FR3', objective: 'The video room opens five minutes before the start', input: 'confirmed appointment; 6 and 5 minutes before the start',
        expected: 'Closed at -6 min, open at -5 min', run: () {
          final start = DateTime.utc(2026, 10, 20, 5);
          final a = appt(AppointmentStatus.confirmed, start: start);
          final early = ConsultationRules.canJoin(a, start.subtract(const Duration(minutes: 6)));
          final open = ConsultationRules.canJoin(a, start.subtract(const Duration(minutes: 5)));
          return check(!early && open, 'At -6 min can join = $early; at -5 min can join = $open');
        });
    atc('ATC-M14-U12', req: 'M14-FR3', objective: 'There is nothing to join before the specialist accepts', input: 'status "requested" (no video link yet)',
        expected: 'Cannot join', run: () { final start = DateTime.utc(2026, 10, 20, 5); final j = ConsultationRules.canJoin(appt(AppointmentStatus.requested, start: start, link: ''), start.subtract(const Duration(minutes: 1))); return check(!j, 'Can join = $j'); });
    atc('ATC-M14-U13', req: 'M14-FR2', objective: 'A request can be cancelled until it starts, but not after', input: 'requested appointment; 30 minutes before and at the start',
        expected: 'Cancellable before, not at the start', run: () {
          final start = DateTime.utc(2026, 10, 20, 5);
          final a = appt(AppointmentStatus.requested, start: start, link: '');
          final before = ConsultationRules.canCancel(a, start.subtract(const Duration(minutes: 30)));
          final atStart = ConsultationRules.canCancel(a, start);
          return check(before && !atStart, 'Before the start: $before; at the start: $atStart');
        });
    atc('ATC-M14-U14', req: 'M14-FR2', objective: 'A request nobody answered before its start time expires', input: 'requested appointment, now = start time',
        expected: 'Expired and no longer upcoming', run: () {
          final start = DateTime.utc(2026, 10, 20, 5);
          final a = appt(AppointmentStatus.requested, start: start, link: '');
          return check(ConsultationRules.isExpiredRequest(a, start) && !ConsultationRules.isUpcoming(a, start), 'Expired = ${ConsultationRules.isExpiredRequest(a, start)}; upcoming = ${ConsultationRules.isUpcoming(a, start)}');
        });
    final diet = SpecialistDietPlan(approvedAsIs: false, note: 'Follow for 4 weeks', targetKcal: 1800, proteinG: 120, carbsG: 200, fatG: 55, avoid: const ['Fried foods'], tips: const ['Drink water before meals'], by: const PlanAuthor('Sara Khan', 'nutritionist'), at: DateTime(2026, 10, 19));
    Exercise ex(String id, {String group = 'legs', bool timed = false}) => Exercise(id: id, name: id, icon: '', group: group, muscles: const [], impact: 'low', level: 1, met: 4, steps: const [], timed: timed, baseReps: 12, baseSeconds: 30);
    final lib = {for (final e in [ex('warmup', group: 'mobility', timed: true), ex('cooldown', group: 'mobility', timed: true), ex('squat'), ex('walk', group: 'cardio', timed: true)]) e.id: e};
    PersonalizedPlan base() => PersonalizedPlan(
        category: 'Normal', intensity: 'Moderate', variant: 0, week: [WorkoutDay(name: 'Baymax day', focus: 'Full body', exercises: [PlannedExercise(exercise: lib['squat']!, sets: 3, reps: 10, seconds: 0, restSeconds: 45)]), null, null, null, null, null, null],
        restrictionNotes: const [], nutrition: const NutritionPlan(goalLabel: 'Lose weight', targetKcal: 2000, proteinG: 110, carbsG: 230, fatG: 65, waterLitres: 2.5, meals: {}, avoid: ['Sugary drinks'], tips: ['Walk after meals']));
    PersonalizedPlan apply(PersonalizedPlan b, SpecialistPlans p, {PlanChoices c = PlanChoices.defaults}) => applySpecialistPlans(b, p, c, exercise: (id) => lib[id], warmUp: lib['warmup']!, coolDown: lib['cooldown']!);

    atc('ATC-M14-U15', req: 'M14-FR5', objective: 'A specialist\'s diet plan replaces the calorie target and macros and adds advice first', input: 'Baymax target 2000 kcal; specialist target 1800 kcal, macros 120/200/55',
        expected: 'Target 1800 kcal; avoid list starts with "Fried foods"; Baymax advice kept', run: () {
          final n = apply(base(), SpecialistPlans(diet: diet)).nutrition;
          return check(n.targetKcal == 1800 && n.proteinG == 120 && n.avoid.first == 'Fried foods' && n.tips.last == 'Walk after meals', 'Target ${n.targetKcal} kcal; macros ${n.proteinG}/${n.carbsG}/${n.fatG}; first avoid "${n.avoid.first}"; last tip "${n.tips.last}"');
        });
    atc('ATC-M14-U16', req: 'M14-FR5', objective: '"Approved as is" changes nothing in the plan', input: 'specialist status approved',
        expected: 'The Baymax plan is returned unchanged', run: () {
          final approved = SpecialistDietPlan(approvedAsIs: true, by: const PlanAuthor('Sara Khan', 'nutritionist'), at: DateTime(2026, 10, 19));
          final b = base();
          return check(identical(apply(b, SpecialistPlans(diet: approved)), b), 'Plan returned unchanged = ${identical(apply(b, SpecialistPlans(diet: approved)), b)}');
        });
    atc('ATC-M14-U17', req: 'M14-FR5', objective: 'The member\'s choice to use Baymax\'s plan is respected', input: 'specialist plan present; member choice = Baymax',
        expected: 'Calorie target stays 2000', run: () { final n = apply(base(), SpecialistPlans(diet: diet), c: const PlanChoices(specialistDiet: false)).nutrition; return check(n.targetKcal == 2000, 'Target = ${n.targetKcal} kcal'); });
    atc('ATC-M14-U18', req: 'M14-FR5', objective: 'A specialist\'s weekly schedule replaces the week with warm-up and cool-down', input: 'Monday walk 900 s; Wednesday squat 3x15; other days rest',
        expected: '2 workout days; warm-up first and cool-down last on each', run: () {
          final w = SpecialistWorkoutPlan(approvedAsIs: false, note: 'Build slowly', by: const PlanAuthor('Ali Raza', 'trainer'), at: DateTime(2026, 10, 19), schedule: [
            const SpecialistWorkoutDay(day: 1, rest: false, items: [SpecialistExercise(exerciseId: 'walk', sets: 1, seconds: 900)]),
            const SpecialistWorkoutDay(day: 2, rest: true),
            const SpecialistWorkoutDay(day: 3, rest: false, items: [SpecialistExercise(exerciseId: 'squat', sets: 3, reps: 15)]),
            for (var d = 4; d <= 7; d++) SpecialistWorkoutDay(day: d, rest: true),
          ]);
          final out = apply(base(), SpecialistPlans(workout: w));
          final days = out.week.whereType<WorkoutDay>().toList();
          final ok = days.length == 2 && days.every((d) => d.exercises.first.exercise.id == 'warmup' && d.exercises.last.exercise.id == 'cooldown');
          return check(ok, '${days.length} workout days; Monday exercises: ${out.week[0]!.exercises.map((e) => e.exercise.id).join(' > ')}');
        });
  });

  // ---------------------------------------------------------------- Module 15: Payment Integration
  group('Module 15 payment rules', () {
    final now = DateTime.utc(2026, 10, 19, 3, 0);
    atc('ATC-M15-U01', req: 'M15-FR3', objective: 'A valid card number passes the check-digit test', input: '"4242 4242 4242 4242"',
        expected: 'Valid', run: () { final v = PaymentRules.luhn(PaymentRules.digitsOnly('4242 4242 4242 4242')); return check(v, 'Check-digit test passed = $v'); });
    atc('ATC-M15-U02', req: 'M15-FR3', objective: 'A mistyped card number fails the check-digit test', input: '"4242 4242 4242 4241"',
        expected: 'Invalid', run: () { final v = PaymentRules.luhn('4242424242424241'); return check(!v, 'Check-digit test passed = $v'); });
    atc('ATC-M15-U03', req: 'M15-FR3', objective: 'Visa and Mastercard are recognised', input: '4242 4242 4242 4242; 5555 5555 5555 4444',
        expected: 'Visa; Mastercard', run: () { final a = PaymentRules.brandOf('4242 4242 4242 4242'); final b = PaymentRules.brandOf('5555555555554444'); return check(a == 'Visa' && b == 'Mastercard', 'Brands: $a; $b'); });
    atc('ATC-M15-U04', req: 'M15-FR3', objective: 'Other card brands are not accepted', input: 'American Express 3782 8224 6310 005',
        expected: 'No supported brand', run: () { final b = PaymentRules.brandOf('378282246310005'); return check(b == null, 'Brand = $b'); });
    atc('ATC-M15-U05', req: 'M15-FR3', objective: 'A card is good through the last day of its expiry month (boundary)', input: 'expiry 10/26 on 31 Oct 2026 23:59 and on 1 Nov 2026',
        expected: 'Not expired on 31 Oct; expired on 1 Nov', run: () {
          final a = PaymentRules.expiryInPast('10/26', DateTime(2026, 10, 31, 23, 59));
          final b = PaymentRules.expiryInPast('10/26', DateTime(2026, 11, 1));
          return check(!a && b, 'Expired on 31 Oct: $a; expired on 1 Nov: $b');
        });
    atc('ATC-M15-U06', req: 'M15-FR3', objective: 'All four card fields are mandatory', input: 'empty card form',
        expected: 'Errors for number, expiry, cvv and holder', run: () { final e = PaymentRules.validateCard(const CardInput(), now); return check(e.keys.toSet().containsAll({'number', 'expiry', 'cvv', 'holder'}), 'Errors on: ${e.keys.join(', ')}'); });
    atc('ATC-M15-U07', req: 'M15-FR3', objective: 'A CVV must be exactly 3 digits', input: 'CVV "12" and "1234"',
        expected: 'Both rejected', run: () {
          const base = CardInput(number: '4242424242424242', expiry: '12/30', holder: 'A B');
          final a = PaymentRules.validateCard(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '12', holder: 'A B'), now).containsKey('cvv');
          final b = PaymentRules.validateCard(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '1234', holder: 'A B'), now).containsKey('cvv');
          return check(a && b && base.cvv == '', 'Rejected "12": $a; rejected "1234": $b');
        });
    atc('ATC-M15-U08', req: 'M15-FR3', objective: 'A Pakistani mobile number is normalised from common spellings', input: '"0300 1234567", "+92 300 1234567"',
        expected: 'Both become 03001234567', run: () { final a = PaymentRules.normalizeMobile('0300 1234567'); final b = PaymentRules.normalizeMobile('+92 300 1234567'); return check(a == '03001234567' && b == '03001234567', 'Normalised: $a; $b'); });
    atc('ATC-M15-U09', req: 'M15-FR4', objective: 'The total equals consultation fee plus platform fee', input: 'fee 2000, platform fee 150',
        expected: 'PKR 2150', run: () { final t = const OrderSummary(consultationFee: 2000, platformFee: 150).total; return same(t, 2150, say: 'Total = PKR $t'); });
    atc('ATC-M15-U10', req: 'M15-FR4', objective: 'A zero platform fee still gives the right total', input: 'fee 2000, platform fee 0',
        expected: 'PKR 2000', run: () { final t = const OrderSummary(consultationFee: 2000).total; return same(t, 2000, say: 'Total = PKR $t'); });
    atc('ATC-M15-U11', req: 'M15-FR5', objective: 'The test gateway declines the published decline card', input: 'card 4000 0000 0000 0002',
        expected: 'Declined with a reason', run: () async {
          final r = await SandboxGateway(delay: Duration.zero).charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4000 0000 0000 0002', expiry: '12/30', cvv: '123', holder: 'A B')));
          return check(!r.success && (r.message ?? '').contains('declined'), 'Success = ${r.success}; message: "${r.message}"');
        });
    atc('ATC-M15-U12', req: 'M15-FR5', objective: 'A real-looking card is refused by the test gateway, never "charged"', input: 'card 4111 1111 1111 1111',
        expected: 'Refused with the test-card hint', run: () async {
          final r = await SandboxGateway(delay: Duration.zero).charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4111 1111 1111 1111', expiry: '12/30', cvv: '123', holder: 'A B')));
          return check(!r.success && (r.message ?? '').contains('4242 4242 4242 4242'), 'Success = ${r.success}; message: "${r.message}"');
        });
    atc('ATC-M15-U13', req: 'M15-FR6', objective: 'A successful test payment returns a reference, brand and last four digits only', input: 'card 4242 4242 4242 4242',
        expected: 'Success with reference, "Visa", "4242"', run: () async {
          final r = await SandboxGateway(delay: Duration.zero).charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4242 4242 4242 4242', expiry: '12/30', cvv: '123', holder: 'A B')));
          return check(r.success && r.brand == 'Visa' && r.last4 == '4242' && (r.reference ?? '').startsWith('sbx_c_'), 'Success = ${r.success}; brand ${r.brand}; last four ${r.last4}; reference ${r.reference}');
        });
    atc('ATC-M15-U14', req: 'M15-FR6', objective: 'The hold on an unpaid booking counts down and never goes below zero', input: '10-minute hold; 9 min 19 s later; 1 hour later',
        expected: '10:00 at the start, 0:41 after 9:19, zero after an hour', run: () {
          final until = now.add(const Duration(minutes: 10));
          final a = PaymentRules.countdown(PaymentRules.holdRemaining(until, now));
          final b = PaymentRules.countdown(PaymentRules.holdRemaining(until, now.add(const Duration(minutes: 9, seconds: 19))));
          final c = PaymentRules.holdRemaining(until, now.add(const Duration(hours: 1)));
          return check(a == '10:00' && b == '0:41' && c == Duration.zero, 'Countdown: $a, $b, ${c.inSeconds} s');
        });
  });

  // ---------------------------------------------------------------- Module 16: Secure Data Management & Smart Alerts
  group('Module 16 roles and reminders', () {
    atc('ATC-M16-U01', req: 'M16-FR2', objective: 'An unknown or missing role is treated as a plain member', input: 'null; "superuser"; "doctor"',
        expected: 'member; member; doctor', run: () { final r = [UserRoleRules.parse(null), UserRoleRules.parse('superuser'), UserRoleRules.parse('doctor')]; return check(r[0] == UserRole.user && r[1] == UserRole.user && r[2] == UserRole.doctor, 'Roles: ${r.map((x) => x.name).join('; ')}'); });
    atc('ATC-M16-U02', req: 'M16-FR2', objective: 'A member cannot view assigned patients\' data', input: 'member role',
        expected: 'viewOwnData allowed; viewAssignedPatientData refused', run: () { final a = UserRole.user.can(Permission.viewOwnData); final b = UserRole.user.can(Permission.viewAssignedPatientData); return check(a && !b, 'Own data: $a; patients\' data: $b'); });
    atc('ATC-M16-U03', req: 'M16-FR2', objective: 'Only a doctor may upload prescriptions', input: 'doctor and trainer roles',
        expected: 'Doctor allowed; trainer refused', run: () { final d = UserRole.doctor.can(Permission.uploadPrescriptions); final t = UserRole.trainer.can(Permission.uploadPrescriptions); return check(d && !t, 'Doctor: $d; trainer: $t'); });
    atc('ATC-M16-U04', req: 'M16-FR2', objective: 'An administrator manages accounts but cannot read health data', input: 'admin role',
        expected: 'manageAccounts allowed; viewAssignedPatientData refused', run: () { final a = UserRole.admin.can(Permission.manageAccounts); final b = UserRole.admin.can(Permission.viewAssignedPatientData); return check(a && !b, 'Manage accounts: $a; read patient data: $b'); });
    atc('ATC-M16-U05', req: 'M16-FR5', objective: 'Rest days alone are not inactivity', input: 'planned Mon/Wed/Fri; last workout Fri 9 Oct; today Mon 12 Oct',
        expected: 'No inactivity alert', run: () { final r = detectInactivity(today: DateTime(2026, 10, 12), lastWorkout: DateTime(2026, 10, 9), plannedWeekdays: {1, 3, 5}); return check(r == null, 'Alert = ${r == null ? 'none' : 'raised'}'); });
    atc('ATC-M16-U06', req: 'M16-FR5', objective: 'A missed planned day over three days is inactivity', input: 'planned Mon/Wed/Fri; last workout Fri 9 Oct; today Wed 14 Oct',
        expected: 'Alert: 5 days since workout, 1 missed planned day', run: () { final r = detectInactivity(today: DateTime(2026, 10, 14), lastWorkout: DateTime(2026, 10, 9), plannedWeekdays: {1, 3, 5}); return check(r != null && r.daysSinceWorkout == 5 && r.missedPlannedDays == 1, 'Days since workout ${r?.daysSinceWorkout}; missed planned days ${r?.missedPlannedDays}'); });
    atc('ATC-M16-U07', req: 'M16-FR3', objective: 'The next workout reminder is the next occurrence of the weekday and time', input: 'now Wed 14 Oct 10:00; reminder Wed 18:30; Wed 09:00',
        expected: 'Today 18:30; next Wednesday 09:00', run: () {
          final now = DateTime(2026, 10, 14, 10);
          final a = nextWeekdayAt(now, DateTime.wednesday, 18, 30);
          final b = nextWeekdayAt(now, DateTime.wednesday, 9, 0);
          return check(a == DateTime(2026, 10, 14, 18, 30) && b == DateTime(2026, 10, 21, 9), 'Next: $a; $b');
        });
  });

  // ---------------------------------------------------------------- Module 17: Analytics & Progress Dashboard
  group('Module 17 analytics', () {
    atc('ATC-M17-U01', req: 'M17-FR5', objective: 'The moving average uses only logged days inside a 3-day window', input: '[2000, null, 2200, 1800, null]',
        expected: '[2000, 2000, 2100, 2000, 2000]', run: () {
          final r = AnalyticsScreen.movingAverage([2000, null, 2200, 1800, null]);
          return check(r.join(',') == '2000.0,2000.0,2100.0,2000.0,2000.0', 'Smoothed: ${r.join(', ')}');
        });
    atc('ATC-M17-U02', req: 'M17-FR5', objective: 'A window with no logged day gives no value rather than zero', input: '[null, null, null, 2000]',
        expected: '[null, null, null, 2000]', run: () {
          final r = AnalyticsScreen.movingAverage([null, null, null, 2000]);
          return check(r[0] == null && r[1] == null && r[2] == null && r[3] == 2000, 'Smoothed: ${r.join(', ')}');
        });
  });
}

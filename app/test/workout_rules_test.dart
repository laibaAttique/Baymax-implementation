import 'dart:math';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- Oracle: the Module 3 restriction logic exactly as it was in plan_generator.dart before the rules moved to the
// repository (copied from commit fb98995). The repository must reproduce it for every person.
class _Legacy {
  final bool noHighImpact, noHiit, noIsometric, noPlyo, includeBalance, strengthFocus;
  final int maxLevel, maxDays, maxSessionMin;
  final int? maxHold;
  final List<String> notes;
  _Legacy(this.noHighImpact, this.noHiit, this.noIsometric, this.noPlyo, this.includeBalance, this.strengthFocus, this.maxLevel,
      this.maxDays, this.maxSessionMin, this.maxHold, this.notes);
}

String _legacyIntensity(HealthProfile p, ClassificationResult cls) {
  var level = switch (cls.category) {
    'Cardiac' || 'At-Risk' || 'Obese' => 0,
    _ => 1,
  };
  if (p.activityLevel == 'Sedentary') level -= 1;
  if ((p.activityLevel == 'Very Active' || p.activityLevel == 'Athlete') && (cls.category == 'Healthy' || cls.category == 'Overweight')) {
    level += 1;
  }
  return const ['Low', 'Moderate', 'High'][level.clamp(0, 2)];
}

_Legacy _legacy(HealthProfile p, ClassificationResult cls, String intensity) {
  final bmi = p.bmi;
  final age = p.age ?? 30;
  final cardiac = cls.isCardiac;
  final hypertension = p.hasCondition('Hypertension');
  final diabetic = p.hasCondition('Diabetes');
  final asthma = p.hasCondition('Asthma');
  final underweight = bmi > 0 && bmi < 18.5;
  final obese = bmi >= 30;
  final overweight = bmi >= 25;
  final senior = age >= 55;
  final beginner = p.activityLevel == 'Sedentary';
  final noHighImpact = obese || cardiac || hypertension || senior;
  final noHiit = cardiac || hypertension || diabetic || asthma || senior || bmi >= 35 || intensity == 'Low';
  final noIsometric = cardiac;
  final noPlyo = noHighImpact || overweight;
  final maxLevel = (cardiac || beginner || intensity == 'Low' || noHiit) ? 2 : 3;
  final maxDays = cardiac || age >= 60 ? 4 : (obese || hypertension || diabetic ? 5 : 6);
  final maxSession = cardiac ? 30 : (intensity == 'Low' ? 35 : (intensity == 'Moderate' ? 45 : 55));
  final notes = <String>[];
  if (cardiac) {
    notes.add('Heart condition: only low-impact, steady-effort exercise is included — no maximal-effort or breath-holding work. '
        'Get your doctor\'s clearance before starting, and stop immediately if you feel chest pain, dizziness or unusual breathlessness.');
  }
  if (hypertension) {
    notes.add('Hypertension: high-intensity intervals and high-impact moves are removed, and static holds (planks, wall sits) are capped at 20 seconds. '
        'Breathe steadily and never hold your breath — straining raises blood pressure. Check with your doctor about the right intensity for you.');
  }
  if (diabetic) {
    notes.add('Diabetes: sessions are steady and moderate. Check your blood sugar before and after exercise, keep fast-acting carbohydrates nearby, and ask your doctor before training on an empty stomach.');
  }
  if (asthma) notes.add('Asthma: high-intensity intervals are removed. Warm up thoroughly and keep your reliever inhaler with you.');
  if (obese && !cardiac) {
    notes.add('BMI ${bmi.toStringAsFixed(1)}: jumping and running-style moves are replaced with low-impact options to protect your knees and ankles.');
  } else if (overweight && !noHighImpact) {
    notes.add('Jump (plyometric) exercises are removed to reduce joint stress at your current weight.');
  }
  if (underweight) {
    notes.add('Underweight BMI: the plan focuses on strength training and limits cardio so you do not burn the energy you need to gain healthy weight.');
  }
  if (senior) notes.add('Age 55+: high-impact moves are removed as a precaution.');
  if (age >= 65) notes.add('Age 65+: balance training is added, as WHO recommends for older adults.');
  if (beginner) notes.add('You are starting from a sedentary baseline, so sessions are shorter and exercises are beginner-friendly. Increase gradually.');
  if (notes.isEmpty) notes.add('No medical restrictions detected. Warm up before every session and stop if something hurts.');
  return _Legacy(noHighImpact, noHiit, noIsometric, noPlyo, age >= 65, underweight, maxLevel, maxDays, maxSession,
      hypertension ? 20 : null, notes);
}

HealthProfile _person({
  List<String> conditions = const [],
  double weight = 70,
  double height = 170,
  String dob = '1995-06-01',
  String activity = 'Moderately Active',
}) =>
    HealthProfile(
      fullName: 'Test Person',
      dob: dob,
      gender: 'Female',
      heightValue: height,
      weightValue: weight,
      medicalConditions: conditions,
      primaryGoal: 'Lose Weight',
      activityLevel: activity,
      workoutFrequency: 4,
    );

Exercise _ex(String id, {String impact = 'low', List<String> tags = const [], List<String> joints = const [], int level = 1, String source = 'baymax'}) =>
    Exercise(
      id: id,
      name: id,
      icon: '',
      group: 'legs',
      muscles: const [],
      impact: impact,
      level: level,
      met: 3,
      steps: const ['x'],
      tags: tags,
      joints: joints,
      source: source,
    );

SafetyAssessment _assess(HealthProfile p, {WorkoutReadiness? readiness, SafetyRuleEngine engine = SafetyRuleRepository.engine}) {
  final cls = const RuleBasedClassifier().classify(p);
  return engine.assess(HealthFacts.from(p, cls, _legacyIntensity(p, cls), readiness: readiness));
}

void main() {
  test('the repository reproduces the Module 3 restrictions exactly for 3,000 random people', () {
    final rnd = Random(42);
    const conds = ['Diabetes', 'Hypertension', 'Heart Disease', 'Asthma', 'Obesity', 'PCOS'];
    const activity = ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active', 'Athlete'];
    for (var i = 0; i < 3000; i++) {
      final p = _person(
        conditions: [for (final c in conds) if (rnd.nextDouble() < 0.18) c],
        weight: 38 + rnd.nextDouble() * 110,
        height: 145 + rnd.nextDouble() * 50,
        dob: rnd.nextDouble() < 0.05 ? '' : '${1940 + rnd.nextInt(68)}-0${1 + rnd.nextInt(9)}-15',
        activity: activity[rnd.nextInt(activity.length)],
      );
      final cls = const RuleBasedClassifier().classify(p);
      final intensity = _legacyIntensity(p, cls);
      final old = _legacy(p, cls, intensity);
      final a = SafetyRuleRepository.engine.assess(HealthFacts.from(p, cls, intensity));
      final why = 'person $i: bmi ${p.bmi.toStringAsFixed(1)}, age ${p.age}, ${p.medicalConditions}, ${p.activityLevel}, ${cls.category}';
      expect(a.excludedImpact.contains('high'), old.noHighImpact, reason: why);
      expect(a.excludedTags.contains('hiit'), old.noHiit, reason: why);
      expect(a.excludedTags.contains('isometric'), old.noIsometric, reason: why);
      expect(a.excludedTags.contains('plyo'), old.noPlyo, reason: why);
      expect(a.includeBalance, old.includeBalance, reason: why);
      expect(a.strengthFocus, old.strengthFocus, reason: why);
      expect(a.maxLevel, old.maxLevel, reason: why);
      expect(a.maxDays, old.maxDays, reason: why);
      expect(a.maxSessionMin, old.maxSessionMin, reason: why);
      expect(a.maxHoldSeconds, old.maxHold, reason: why);
      expect(a.notes, old.notes, reason: why);
      expect(a.gate.status, WorkoutGateStatus.eligible, reason: 'no screening without readiness answers');
    }
  });

  group('Repository integrity', () {
    test('ids are unique, every rule cites a known source, and nothing is marked approved', () {
      final ids = <String>{};
      for (final r in SafetyRuleRepository.rules) {
        expect(ids.add(r.id), isTrue, reason: 'duplicate ${r.id}');
        for (final e in r.evidence) {
          expect(SafetyRuleRepository.evidence.containsKey(e), isTrue, reason: '${r.id} cites unknown $e');
        }
        if (r.kind != RuleKind.program) expect(r.evidence, isNotEmpty, reason: '${r.id} has no evidence');
        expect(r.reviewStatus, 'pending', reason: 'no rule has been professionally reviewed yet');
        expect(r.effects.allowTags, isEmpty, reason: 'no shipped rule relaxes anything');
      }
    });
  });

  group('Screening gate', () {
    test('warning symptoms stop plan generation for anyone', () {
      final a = _assess(_person(), readiness: const WorkoutReadiness(symptoms: {'chestPain'}));
      expect(a.gate.status, WorkoutGateStatus.needsClearance);
      expect(a.gate.ruleIds, contains('SCR-SYMPTOMS'));
      expect(a.gate.reasons.single, contains('see a doctor'));
    });

    test('heart condition: unanswered needs info, no clearance needs clearance, clearance allows a restricted plan', () {
      final heart = _person(conditions: ['Heart Disease']);
      expect(_assess(heart, readiness: WorkoutReadiness.unanswered).gate.status, WorkoutGateStatus.needsInfo);
      expect(_assess(heart, readiness: const WorkoutReadiness(clearance: false)).gate.status, WorkoutGateStatus.needsClearance);
      expect(_assess(heart, readiness: const WorkoutReadiness()).gate.status, WorkoutGateStatus.needsClearance,
          reason: '"not sure" is not clearance');
      final cleared = _assess(heart, readiness: const WorkoutReadiness(clearance: true));
      expect(cleared.gate.status, WorkoutGateStatus.eligible);
      expect(cleared.excludedImpact, contains('high'), reason: 'clearance does not lift the cardiac restrictions');
      expect(cleared.excludedTags, containsAll(['hiit', 'isometric']));
    });

    test('missing date of birth or weight asks for information', () {
      expect(_assess(_person(dob: ''), readiness: const WorkoutReadiness()).gate.status, WorkoutGateStatus.needsInfo);
      expect(_assess(_person(weight: 0), readiness: const WorkoutReadiness()).gate.status, WorkoutGateStatus.needsInfo);
    });

    test('the most severe gate wins when several apply', () {
      final a = _assess(_person(conditions: ['Heart Disease'], dob: ''), readiness: const WorkoutReadiness(symptoms: {'dizziness'}));
      expect(a.gate.status, WorkoutGateStatus.needsClearance);
      expect(a.gate.ruleIds, containsAll(['SCR-SYMPTOMS', 'SCR-CARDIAC-CLEARANCE', 'SCR-MISSING-AGE']));
    });

    test('a healthy person with answers is eligible', () {
      final a = _assess(_person(), readiness: const WorkoutReadiness(equipment: {'dumbbell'}));
      expect(a.gate.status, WorkoutGateStatus.eligible);
      expect(a.gate.reasons, isEmpty);
    });
  });

  group('Exercise decisions', () {
    test('a documented restriction excludes, and names the rule', () {
      final a = _assess(_person(conditions: ['Hypertension']));
      final d = a.decide(_ex('jump', impact: 'high'));
      expect(d.outcome, ExerciseOutcome.excluded);
      expect(d.ruleIds, contains('MED-HTN'));
      expect(a.decide(_ex('hiit', tags: ['hiit'])).outcome, ExerciseOutcome.excluded);
    });

    test('hypertension: holds are allowed but capped, loaded exercises carry the breathing modification', () {
      final a = _assess(_person(conditions: ['Hypertension']));
      final hold = a.decide(_ex('plank', tags: ['isometric']));
      expect(hold.outcome, ExerciseOutcome.eligibleWithModifications);
      expect(hold.notes.single, contains('20 s'));
      final loaded = a.decide(_ex('db', tags: ['externalLoad']));
      expect(loaded.outcome, ExerciseOutcome.eligibleWithModifications);
      expect(loaded.notes.single, contains('never hold your breath'));
    });

    test('injury: high impact on the joint is excluded, low impact on it is adapted, others untouched', () {
      final a = _assess(_person(), readiness: const WorkoutReadiness(injuries: {'knee'}));
      expect(a.decide(_ex('jump', impact: 'high', joints: ['knee'])).outcome, ExerciseOutcome.excluded);
      final squat = a.decide(_ex('squat', joints: ['knee']));
      expect(squat.outcome, ExerciseOutcome.eligibleWithModifications);
      expect(squat.ruleIds, ['INJ-KNEE']);
      expect(a.decide(_ex('press', joints: ['shoulder'])).outcome, ExerciseOutcome.eligible);
    });

    test('unknown impact is not treated as safe when it matters', () {
      final restricted = _assess(_person(weight: 110));
      expect(restricted.decide(_ex('mystery', impact: 'unknown')).outcome, ExerciseOutcome.requiresInformation);
      expect(restricted.decide(_ex('mystery', impact: 'unknown')).schedulable, isFalse);
      final injured = _assess(_person(), readiness: const WorkoutReadiness(injuries: {'ankle'}));
      expect(injured.decide(_ex('mystery', impact: 'unknown')).schedulable, isFalse);
    });

    test('program scope: maximal lifting and expert dataset exercises are never scheduled', () {
      final a = _assess(_person(activity: 'Athlete'));
      expect(a.decide(_ex('snatch', tags: ['maximal'])).outcome, ExerciseOutcome.excluded);
      expect(a.decide(_ex('expert', level: 3, source: 'free-exercise-db')).outcome, ExerciseOutcome.excluded);
      expect(a.decide(_ex('curated-expert', level: 3)).outcome, ExerciseOutcome.eligible, reason: 'curated level 3 follows maxLevel only');
    });
  });

  group('Approval and conflicts', () {
    const relax = SafetyRule(
      id: 'TEST-ALLOW-MAXIMAL',
      title: 'Supervised lifter',
      kind: RuleKind.program,
      basis: RuleBasis.teamPrecaution,
      when: [],
      effects: Effects(allowTags: {'maximal', 'hiit'}),
      evidence: [],
    );
    const relaxApproved = SafetyRule(
      id: 'TEST-ALLOW-MAXIMAL-APPROVED',
      title: 'Supervised lifter',
      kind: RuleKind.program,
      basis: RuleBasis.teamPrecaution,
      when: [],
      effects: Effects(allowTags: {'maximal', 'hiit'}),
      evidence: [],
      reviewStatus: 'approved',
      approvedBy: 'Test reviewer',
    );

    test('an unapproved rule cannot authorise anything', () {
      const engine = SafetyRuleEngine(version: 't', rules: [...SafetyRuleRepository.rules, relax]);
      final a = _assess(_person(activity: 'Athlete'), engine: engine);
      expect(a.decide(_ex('snatch', tags: ['maximal'])).outcome, ExerciseOutcome.excluded);
    });

    test('an approved rule lifts only program-scope exclusions, never medical ones', () {
      const engine = SafetyRuleEngine(version: 't', rules: [...SafetyRuleRepository.rules, relaxApproved]);
      final healthy = _assess(_person(activity: 'Athlete'), engine: engine);
      expect(healthy.decide(_ex('snatch', tags: ['maximal'])).outcome, ExerciseOutcome.eligible);
      final asthma = _assess(_person(conditions: ['Asthma'], activity: 'Athlete'), engine: engine);
      expect(asthma.decide(_ex('intervals', tags: ['hiit'])).outcome, ExerciseOutcome.excluded,
          reason: 'MED-ASTHMA still excludes HIIT');
    });

    test('conflicting caps resolve to the most restrictive value', () {
      final a = _assess(_person(conditions: ['Heart Disease', 'Hypertension', 'Diabetes'], dob: '1950-01-01'));
      expect(a.maxDays, 4);
      expect(a.maxSessionMin, 30);
      expect(a.maxLevel, 2);
      expect(a.excludedTags, containsAll(['hiit', 'isometric', 'plyo']));
    });

    test('identical inputs give identical assessments', () {
      final p = _person(conditions: ['Hypertension', 'Asthma'], weight: 95);
      final a = _assess(p, readiness: const WorkoutReadiness(injuries: {'knee', 'wrist'}));
      final b = _assess(p, readiness: const WorkoutReadiness(injuries: {'wrist', 'knee'}));
      expect(a.notes, b.notes);
      expect(a.hits.map((h) => h.rule.id).toList(), b.hits.map((h) => h.rule.id).toList());
      expect(a.decide(_ex('lunge', joints: ['knee', 'wrist'])).notes, b.decide(_ex('lunge', joints: ['knee', 'wrist'])).notes);
    });
  });
}

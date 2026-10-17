import '../../models/plan.dart';
import 'safety_rule_engine.dart';

/// Module 4 knowledge base, part 2: the versioned health → exercise rule repository. DATA ONLY — the logic is in
/// `safety_rule_engine.dart`.
///
/// Status: every rule is `pending` professional review. The medical rules (MED-, BODY-, AGE-, EXP-, INT-) are the team's
/// existing Module 3 restrictions, moved here unchanged so they can be reviewed and versioned; the screening, injury and
/// program rules are new. Rules marked [RuleBasis.teamPrecaution] are conservative choices motivated by, but not quoted
/// from, the cited sources. None of this is medical clearance.
///
/// Changing a rule: edit it here, bump [version], and note it in PROGRESS.md. Approving a rule: set `reviewStatus:
/// 'approved'` and `approvedBy` (name and role of the qualified reviewer).
class SafetyRuleRepository {
  SafetyRuleRepository._();

  static const version = 'rules-2026.10.1';

  static const evidence = {
    'riebe2015': EvidenceSource(
        'Riebe D, et al. Updating ACSM\'s recommendations for exercise preparticipation health screening. Med Sci Sports Exerc 2015; 47(11): 2473–2479.'),
    'parq': EvidenceSource(
        'Warburton DER, Jamnik VK, Bredin SSD, Gledhill N. The Physical Activity Readiness Questionnaire for Everyone (PAR-Q+) and electronic Physical Activity Readiness Medical Examination (ePARmed-X+). Health Fit J Can 2011; 4(2): 3–23.',
        'https://eparmedx.com/'),
    'acsm11': EvidenceSource('American College of Sports Medicine. ACSM\'s Guidelines for Exercise Testing and Prescription, 11th ed. Wolters Kluwer, 2021.'),
    'aha2024': EvidenceSource(
        'Paluch AE, et al. Resistance exercise training in individuals with and without cardiovascular disease: 2023 update — a scientific statement from the American Heart Association. Circulation 2024; 149: e217–e231.'),
    'ada2016': EvidenceSource(
        'Colberg SR, et al. Physical activity/exercise and diabetes: a position statement of the American Diabetes Association. Diabetes Care 2016; 39(11): 2065–2079.'),
    'acsmHtn2004': EvidenceSource('Pescatello LS, et al. Exercise and hypertension (ACSM position stand). Med Sci Sports Exerc 2004; 36(3): 533–553.'),
    'who2020': EvidenceSource('WHO. Guidelines on physical activity and sedentary behaviour. Geneva, 2020.'),
  };

  static const _cardiac = Pred(Fact.classification, Op.eq, 'Cardiac');
  static const _heartDisease = Pred(Fact.conditions, Op.contains, 'Heart Disease');

  static const _lightLoad = 'Use a light weight you could lift about 15 times, breathe out as you lift and never hold your breath';

  static const rules = <SafetyRule>[
    // ---------------- Screening: may a plan be generated at all? ----------------
    SafetyRule(
      id: 'SCR-SYMPTOMS',
      title: 'Warning symptoms reported',
      kind: RuleKind.screening,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.symptoms, Op.notEmpty)],
      effects: Effects(gate: WorkoutGateStatus.needsClearance),
      note: 'You reported a warning sign (for example chest pain, fainting, unusual breathlessness, or a doctor\'s advice to limit activity). '
          'Please see a doctor before starting an exercise programme. Baymax will not generate a plan until you update your answers after that visit.',
      evidence: ['riebe2015', 'parq'],
    ),
    SafetyRule(
      id: 'SCR-CARDIAC-UNANSWERED',
      title: 'Heart condition: readiness questions not answered',
      kind: RuleKind.screening,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.answered, Op.eq, false), _cardiac],
      effects: Effects(gate: WorkoutGateStatus.needsInfo),
      note: 'Because you have a heart condition, please answer the exercise readiness questions (including whether your doctor has cleared you) before a plan is made.',
      evidence: ['riebe2015', 'aha2024'],
    ),
    SafetyRule(
      id: 'SCR-CARDIAC-CLEARANCE',
      title: 'Heart condition without a doctor\'s clearance',
      kind: RuleKind.screening,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.answered, Op.eq, true), _cardiac, Pred(Fact.clearance, Op.ne, true)],
      effects: Effects(gate: WorkoutGateStatus.needsClearance),
      note: 'With a heart condition, a doctor should clear you for exercise first. Once they have, update your readiness answers and your plan will be generated.',
      evidence: ['riebe2015', 'aha2024'],
    ),
    SafetyRule(
      id: 'SCR-HEART-CONDITION-LISTED',
      title: 'Heart disease listed but classification differs',
      kind: RuleKind.screening,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.answered, Op.eq, true), _heartDisease, Pred(Fact.classification, Op.ne, 'Cardiac'), Pred(Fact.clearance, Op.ne, true)],
      effects: Effects(gate: WorkoutGateStatus.needsClearance),
      note: 'You listed heart disease. A doctor should clear you for exercise before a plan is generated.',
      evidence: ['riebe2015'],
    ),
    SafetyRule(
      id: 'SCR-MISSING-WEIGHT',
      title: 'Weight missing',
      kind: RuleKind.screening,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.answered, Op.eq, true), Pred(Fact.weightKg, Op.lt, 1)],
      effects: Effects(gate: WorkoutGateStatus.needsInfo),
      note: 'Your weight is missing; intensity and energy estimates depend on it. Please add it in your profile.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'SCR-MISSING-HEIGHT',
      title: 'Height missing',
      kind: RuleKind.screening,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.answered, Op.eq, true), Pred(Fact.heightCm, Op.lt, 1)],
      effects: Effects(gate: WorkoutGateStatus.needsInfo),
      note: 'Your height is missing, so your BMI-based rules cannot be applied. Please add it in your profile.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'SCR-MISSING-AGE',
      title: 'Date of birth missing',
      kind: RuleKind.screening,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.answered, Op.eq, true), Pred(Fact.ageRecorded, Op.eq, false)],
      effects: Effects(gate: WorkoutGateStatus.needsInfo),
      note: 'Your date of birth is missing; several safety rules depend on age. Please add it in your profile.',
      evidence: ['acsm11'],
    ),

    // ---------------- Medical (existing Module 3 restrictions, unchanged) ----------------
    SafetyRule(
      id: 'MED-CARDIAC',
      title: 'Heart condition',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [_cardiac],
      effects: Effects(
        excludeImpact: {'high'},
        excludeTags: {'hiit', 'isometric', 'plyo'},
        maxLevel: 2,
        maxDays: 4,
        maxSessionMin: 30,
        modifyTags: {'externalLoad'},
        modification: _lightLoad,
      ),
      note: 'Heart condition: only low-impact, steady-effort exercise is included — no maximal-effort or breath-holding work. '
          'Get your doctor\'s clearance before starting, and stop immediately if you feel chest pain, dizziness or unusual breathlessness.',
      evidence: ['aha2024', 'acsm11'],
    ),
    SafetyRule(
      id: 'MED-HTN',
      title: 'Hypertension',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.conditions, Op.contains, 'Hypertension')],
      effects: Effects(
        excludeImpact: {'high'},
        excludeTags: {'hiit', 'plyo'},
        maxLevel: 2,
        maxDays: 5,
        maxHoldSeconds: 20,
        modifyTags: {'externalLoad'},
        modification: _lightLoad,
      ),
      note: 'Hypertension: high-intensity intervals and high-impact moves are removed, and static holds (planks, wall sits) are capped at 20 seconds. '
          'Breathe steadily and never hold your breath — straining raises blood pressure. Check with your doctor about the right intensity for you.',
      evidence: ['acsmHtn2004', 'aha2024'],
    ),
    SafetyRule(
      id: 'MED-DIABETES',
      title: 'Diabetes',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.conditions, Op.contains, 'Diabetes')],
      effects: Effects(excludeTags: {'hiit'}, maxLevel: 2, maxDays: 5),
      note: 'Diabetes: sessions are steady and moderate. Check your blood sugar before and after exercise, keep fast-acting carbohydrates nearby, and ask your doctor before training on an empty stomach.',
      evidence: ['ada2016'],
    ),
    SafetyRule(
      id: 'MED-ASTHMA',
      title: 'Asthma',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.conditions, Op.contains, 'Asthma')],
      effects: Effects(excludeTags: {'hiit'}, maxLevel: 2),
      note: 'Asthma: high-intensity intervals are removed. Warm up thoroughly and keep your reliever inhaler with you.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'BODY-OBESE',
      title: 'BMI 30 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.bmi, Op.gte, 30)],
      effects: Effects(excludeImpact: {'high'}, excludeTags: {'plyo'}, maxDays: 5),
      note: 'BMI {bmi}: jumping and running-style moves are replaced with low-impact options to protect your knees and ankles.',
      noteWhen: [Pred(Fact.classification, Op.ne, 'Cardiac')],
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'BODY-SEVERE-OBESITY',
      title: 'BMI 35 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.bmi, Op.gte, 35)],
      effects: Effects(excludeTags: {'hiit'}, maxLevel: 2),
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'BODY-OVERWEIGHT',
      title: 'BMI 25 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.bmi, Op.gte, 25)],
      effects: Effects(excludeTags: {'plyo'}),
      note: 'Jump (plyometric) exercises are removed to reduce joint stress at your current weight.',
      // Shown only when no broader impact rule already explains it (same wording rule as Module 3).
      noteWhen: [
        Pred(Fact.bmi, Op.lt, 30),
        Pred(Fact.classification, Op.ne, 'Cardiac'),
        Pred(Fact.conditions, Op.notContains, 'Hypertension'),
        Pred(Fact.age, Op.lt, 55),
      ],
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'BODY-UNDERWEIGHT',
      title: 'BMI below 18.5',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.bmi, Op.gte, 0.01), Pred(Fact.bmi, Op.lt, 18.5)],
      effects: Effects(strengthFocus: true),
      note: 'Underweight BMI: the plan focuses on strength training and limits cardio so you do not burn the energy you need to gain healthy weight.',
      evidence: ['who2020'],
    ),
    SafetyRule(
      id: 'AGE-55',
      title: 'Age 55 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.age, Op.gte, 55)],
      effects: Effects(excludeImpact: {'high'}, excludeTags: {'hiit', 'plyo'}, maxLevel: 2),
      note: 'Age 55+: high-impact moves are removed as a precaution.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'AGE-60',
      title: 'Age 60 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.age, Op.gte, 60)],
      effects: Effects(maxDays: 4),
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'AGE-65',
      title: 'Age 65 or above',
      kind: RuleKind.medical,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.age, Op.gte, 65)],
      effects: Effects(includeBalance: true),
      note: 'Age 65+: balance training is added, as WHO recommends for older adults.',
      evidence: ['who2020'],
    ),
    SafetyRule(
      id: 'EXP-SEDENTARY',
      title: 'Sedentary starting point',
      kind: RuleKind.medical,
      basis: RuleBasis.guideline,
      when: [Pred(Fact.activityLevel, Op.eq, 'Sedentary')],
      effects: Effects(maxLevel: 2),
      note: 'You are starting from a sedentary baseline, so sessions are shorter and exercises are beginner-friendly. Increase gradually.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INT-LOW',
      title: 'Low intensity plan',
      kind: RuleKind.program,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.intensity, Op.eq, 'Low')],
      effects: Effects(excludeTags: {'hiit'}, maxLevel: 2, maxSessionMin: 35),
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INT-MODERATE',
      title: 'Moderate intensity plan',
      kind: RuleKind.program,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.intensity, Op.eq, 'Moderate')],
      effects: Effects(maxSessionMin: 45),
      evidence: ['who2020'],
    ),

    // ---------------- Injuries (readiness answers) ----------------
    SafetyRule(
      id: 'INJ-KNEE',
      title: 'Knee injury or pain',
      kind: RuleKind.injury,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.injuries, Op.contains, 'knee')],
      effects: Effects(injuredJoint: 'knee'),
      note: 'Knee: high-impact moves that load the knee are left out, and other knee exercises carry a pain-free-range reminder. See a physiotherapist if the pain persists.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INJ-BACK',
      title: 'Lower back injury or pain',
      kind: RuleKind.injury,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.injuries, Op.contains, 'lowerBack')],
      effects: Effects(injuredJoint: 'lowerBack'),
      note: 'Lower back: high-impact moves that load the back are left out, and back exercises carry a pain-free-range reminder.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INJ-SHOULDER',
      title: 'Shoulder injury or pain',
      kind: RuleKind.injury,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.injuries, Op.contains, 'shoulder')],
      effects: Effects(injuredJoint: 'shoulder'),
      note: 'Shoulder: pressing exercises carry a pain-free-range reminder.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INJ-WRIST',
      title: 'Wrist injury or pain',
      kind: RuleKind.injury,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.injuries, Op.contains, 'wrist')],
      effects: Effects(injuredJoint: 'wrist'),
      note: 'Wrist: exercises that put weight on your hands carry a reminder to use your fists or forearms, or skip them if they hurt.',
      evidence: ['acsm11'],
    ),
    SafetyRule(
      id: 'INJ-ANKLE',
      title: 'Ankle injury or pain',
      kind: RuleKind.injury,
      basis: RuleBasis.teamPrecaution,
      when: [Pred(Fact.injuries, Op.contains, 'ankle')],
      effects: Effects(injuredJoint: 'ankle'),
      note: 'Ankle: jumping and running moves are left out.',
      evidence: ['acsm11'],
    ),

    // ---------------- Program scope (not medical) ----------------
    SafetyRule(
      id: 'PRG-NO-MAXIMAL',
      title: 'No maximal lifting in an unsupervised app',
      kind: RuleKind.program,
      basis: RuleBasis.teamPrecaution,
      when: [],
      effects: Effects(excludeTags: {'maximal'}, maxCatalogLevel: 2),
      evidence: ['acsm11'],
    ),
  ];

  static const engine = SafetyRuleEngine(version: version, rules: rules);
}

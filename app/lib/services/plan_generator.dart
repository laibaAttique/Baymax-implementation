import '../models/food.dart';
import '../models/health_profile.dart';
import '../models/plan.dart';
import '../utils/health_calc.dart';
import '../models/workout_readiness.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'exercise_selector.dart';
import 'workout_rules/safety_rule_engine.dart';
import 'workout_rules/safety_rule_repository.dart';
import 'food_database.dart';
import 'health_classifier.dart';
import 'ml/gradient_boosting_model.dart';

/// Phase 2 seam: the Gradient Boosting model that fine-tunes calorie targets
/// (Module 3, FR-4) implements this. Today the rule-based target is used.
abstract class CalorieOptimizer {
  int optimize(HealthProfile profile, int ruleBasedKcal);
}

class RuleBasedCalorieOptimizer implements CalorieOptimizer {
  const RuleBasedCalorieOptimizer();
  @override
  int optimize(HealthProfile profile, int ruleBasedKcal) => ruleBasedKcal;
}

/// Medical restriction rules (Module 3, FR-1) resolved for one user.
class PlanRestrictions {
  final bool noHighImpact;
  final bool noHiit;
  final bool noIsometric;
  final bool noPlyo;
  final bool includeBalance;
  final bool strengthFocus;
  final int maxLevel;
  final int maxDays;
  final int maxSessionMin;

  /// Longest allowed hold for isometric exercises (planks, wall sits), or null
  /// for no cap.
  final int? maxHoldSeconds;
  final List<String> notes;

  /// The rule-repository result these restrictions came from (Module 4). When present it decides eligibility,
  /// including injuries and unknown impact; the flags above are kept for existing callers.
  final SafetyAssessment? assessment;

  const PlanRestrictions({
    required this.noHighImpact,
    required this.noHiit,
    required this.noIsometric,
    required this.noPlyo,
    required this.includeBalance,
    required this.strengthFocus,
    required this.maxLevel,
    required this.maxDays,
    required this.maxSessionMin,
    required this.maxHoldSeconds,
    required this.notes,
    this.assessment,
  });

  factory PlanRestrictions.from(SafetyAssessment a) => PlanRestrictions(
        noHighImpact: a.excludedImpact.contains('high'),
        noHiit: a.excludedTags.contains('hiit'),
        noIsometric: a.excludedTags.contains('isometric'),
        noPlyo: a.excludedTags.contains('plyo'),
        includeBalance: a.includeBalance,
        strengthFocus: a.strengthFocus,
        maxLevel: a.maxLevel,
        maxDays: a.maxDays,
        maxSessionMin: a.maxSessionMin,
        maxHoldSeconds: a.maxHoldSeconds,
        notes: a.notes,
        assessment: a,
      );

  bool allows(Exercise e) {
    final a = assessment;
    if (a != null) return a.decide(e).schedulable;
    if (e.level > maxLevel) return false;
    if (noHighImpact && e.impact == 'high') return false;
    if (noHiit && e.tags.contains('hiit')) return false;
    if (noIsometric && e.tags.contains('isometric')) return false;
    if (noPlyo && e.tags.contains('plyo')) return false;
    return true;
  }
}

class _Slot {
  final String group;
  final int count;
  const _Slot(this.group, this.count);
}

class _Template {
  final String name;
  final String focus;
  final List<_Slot> slots;
  final String kind; // Cardio | HIIT | Strength | Yoga
  const _Template(this.name, this.focus, this.slots, [this.kind = 'Strength']);
}

/// Module 3: builds the weekly workout schedule and nutrition plan.
class PlanGenerator {
  final FoodDatabase foods;
  final CalorieOptimizer optimizer;

  /// Phase 2: trained Gradient Boosting model for calories burned per session (optional).
  final WorkoutCalorieModel? workoutModel;

  const PlanGenerator(this.foods, {this.optimizer = const RuleBasedCalorieOptimizer(), this.workoutModel});

  static const _levels = ['Low', 'Moderate', 'High'];

  /// Weekday indexes (Mon = 0) used for each weekly frequency.
  static const _schedule = {
    2: [0, 3],
    3: [0, 2, 4],
    4: [0, 1, 3, 5],
    5: [0, 1, 3, 4, 5],
    6: [0, 1, 2, 3, 4, 5],
  };

  static const _loseTemplates = [
    _Template('Cardio Burn', 'Cardio + core', [_Slot('cardio', 3), _Slot('core', 1)], 'Cardio'),
    _Template('Full-Body Circuit', 'Strength circuit', [_Slot('legs', 2), _Slot('push', 1), _Slot('back', 1), _Slot('core', 1), _Slot('cardio', 1)]),
    _Template('Low-Impact Cardio & Core', 'Steady cardio + core', [_Slot('cardio', 2), _Slot('core', 2), _Slot('legs', 1)], 'Cardio'),
  ];
  static const _gainTemplates = [
    _Template('Lower Body Strength', 'Legs & glutes', [_Slot('legs', 4), _Slot('core', 1)]),
    _Template('Upper Body Strength', 'Chest, shoulders, arms', [_Slot('push', 3), _Slot('back', 2), _Slot('core', 1)]),
    _Template('Full-Body Strength', 'Total body', [_Slot('legs', 2), _Slot('push', 2), _Slot('back', 1), _Slot('core', 1)]),
    _Template('Core & Conditioning', 'Core + light cardio', [_Slot('core', 3), _Slot('cardio', 1), _Slot('back', 1)]),
  ];
  static const _maintainTemplates = [
    _Template('Full-Body Fitness', 'Total body', [_Slot('legs', 2), _Slot('push', 1), _Slot('back', 1), _Slot('core', 1)]),
    _Template('Cardio & Core', 'Heart health + core', [_Slot('cardio', 2), _Slot('core', 2)], 'Cardio'),
    _Template('Strength Mix', 'Strength & stability', [_Slot('push', 2), _Slot('legs', 2), _Slot('core', 1), _Slot('mobility', 1)]),
  ];

  /// [tooDifficult]: ids of exercises the user recently marked "Too Difficult"
  /// in Manual Guidance (report FR17.4). Each is swapped for an easier or
  /// equally easy exercise of the same group when one is allowed, otherwise it
  /// stays with a lighter dose.
  ///
  /// [readiness] turns on Module 4 screening: the plan is only generated when the safety rules allow it (otherwise the
  /// week is empty and [PersonalizedPlan.gate] says why), reported injuries are applied, and catalogue exercises for the
  /// equipment the person owns join the curated library. Without it the plan is generated as in Module 3.
  PersonalizedPlan generate(
    HealthProfile profile,
    ClassificationResult cls, {
    int variant = 0,
    Set<String> tooDifficult = const {},
    WorkoutReadiness? readiness,
  }) {
    final intensity = _intensity(profile, cls);
    final assessment = SafetyRuleRepository.engine.assess(HealthFacts.from(profile, cls, intensity, readiness: readiness));
    final restrictions = PlanRestrictions.from(assessment);

    if (readiness != null && assessment.gate.status != WorkoutGateStatus.eligible) {
      return PersonalizedPlan(
        category: cls.category,
        intensity: intensity,
        variant: variant,
        week: List<WorkoutDay?>.filled(7, null),
        restrictionNotes: assessment.gate.reasons,
        nutrition: _nutrition(profile, cls, variant),
        gate: assessment.gate,
        rulesVersion: assessment.rulesVersion,
      );
    }
    final extraPool = readiness == null ? const <Exercise>[] : ExerciseCatalog.plannableWith(readiness.equipment);

    final templateGoal = restrictions.strengthFocus ? 'Gain Muscle' : profile.primaryGoal;
    final templates = templateGoal == 'Lose Weight'
        ? _loseTemplates
        : (templateGoal == 'Gain Muscle' ? _gainTemplates : _maintainTemplates);

    final days = profile.workoutFrequency.clamp(2, restrictions.maxDays);
    final slots = _schedule[days]!;
    final week = List<WorkoutDay?>.filled(7, null);
    // FR-2/FR-3: within the exercises the safety rules allow, the selector ranks by this person's body parameters and answers.
    final selector = ExerciseSelector(BodyProfile.from(profile), variant: variant);
    final weekUsage = <String, int>{};
    final adjusted = <String>{};
    for (var i = 0; i < slots.length; i++) {
      final template = templates[(i + variant) % templates.length];
      week[slots[i]] =
          _withModelEstimate(_buildDay(template, intensity, restrictions, profile.weightKg, selector, weekUsage, tooDifficult, adjusted, extraPool), profile);
    }

    return PersonalizedPlan(
      category: cls.category,
      intensity: intensity,
      variant: variant,
      week: week,
      restrictionNotes: [
        ...restrictions.notes,
        if (adjusted.isNotEmpty) 'Made easier because you marked them as too difficult: ${adjusted.join('; ')}.',
      ],
      nutrition: _nutrition(profile, cls, variant),
      gate: readiness == null ? null : assessment.gate,
      rulesVersion: assessment.rulesVersion,
    );
  }

  // --- FR-3: intensity by health category ---------------------------------

  String _intensity(HealthProfile p, ClassificationResult cls) {
    var level = switch (cls.category) {
      'Cardiac' || 'At-Risk' || 'Obese' => 0,
      _ => 1, // Diabetic, Overweight, Healthy
    };
    if (p.activityLevel == 'Sedentary') level -= 1;
    if ((p.activityLevel == 'Very Active' || p.activityLevel == 'Athlete') &&
        (cls.category == 'Healthy' || cls.category == 'Overweight')) {
      level += 1;
    }
    return _levels[level.clamp(0, 2)];
  }

  // --- FR-1: medical restriction rules -------------------------------------
  // The rules live in the versioned repository `workout_rules/safety_rule_repository.dart` (Module 4) and are evaluated
  // by `SafetyRuleEngine`; `test/workout_rules_test.dart` checks they reproduce the original Module 3 rules exactly.

  // --- FR-2 / FR-5: templates and weekly schedule --------------------------

  WorkoutDay _buildDay(_Template t, String intensity, PlanRestrictions r, double weightKg, ExerciseSelector selector, Map<String, int> weekUsage,
      [Set<String> tooDifficult = const {}, Set<String>? adjusted, List<Exercise> extraPool = const []]) {
    final usedIds = <String>{};
    final main = <PlannedExercise>[];

    for (final slot in t.slots) {
      final pool = [...ExerciseLibrary.all, ...extraPool].where((e) => e.group == slot.group && r.allows(e) && !usedIds.contains(e.id)).toList();
      if (pool.isEmpty) continue;
      for (final picked in selector.rank(pool, weekUsage: weekUsage).take(slot.count)) {
        var e = picked.exercise;
        var lighter = false;
        if (tooDifficult.contains(e.id)) {
          // FR17.4: swap flagged exercise for an easier/equal one of the same group
          final flagged = e;
          final alternative = pool
              .where((a) => !tooDifficult.contains(a.id) && a.level <= flagged.level && !usedIds.contains(a.id))
              .firstOrNull;
          if (alternative != null) {
            e = alternative;
            adjusted?.add('${flagged.name} → ${alternative.name}');
          } else {
            lighter = true;
            adjusted?.add('${flagged.name} (lighter dose)');
          }
        }
        usedIds.add(e.id);
        weekUsage[e.id] = (weekUsage[e.id] ?? 0) + 1;
        final planned = _withRules(_prescribe(e, intensity, maxHold: r.maxHoldSeconds).withReasons(picked.reasons), r);
        main.add(lighter ? _lighter(planned) : planned);
      }
    }

    // Steady-state cardio shares the session's cardio minutes.
    final steady = main.where((p) => p.exercise.group == 'cardio' && p.sets == 1 && p.timed).toList();
    if (steady.isNotEmpty) {
      final totalMin = intensity == 'Low' ? 16 : (intensity == 'Moderate' ? 20 : 24);
      final eachSec = ((totalMin * 60 / steady.length) / 30).round() * 30;
      for (final s in steady) {
        final i = main.indexOf(s);
        main[i] = PlannedExercise(exercise: s.exercise, sets: 1, reps: 0, seconds: eachSec, restSeconds: s.restSeconds, reasons: s.reasons, ruleNotes: s.ruleNotes);
      }
    }

    if (r.includeBalance) {
      final balance = ExerciseLibrary.all.firstWhere((e) => e.id == 'single_leg_balance');
      main.add(_withRules(_prescribe(balance, intensity, maxHold: r.maxHoldSeconds).withReasons(const ['Balance training is recommended from age 65']), r));
    }

    // Cool-down: up to two static stretches for the body regions this session actually worked.
    final stretches = _cooldownStretches(main, r, selector, weekUsage);

    final warm = _withRules(_prescribe(ExerciseLibrary.warmUp, intensity), r);
    final cool = _withRules(_prescribe(ExerciseLibrary.coolDown, intensity), r);

    List<PlannedExercise> all() => [warm, ...main, ...stretches, cool];
    int minutes() => WorkoutDay(name: '', focus: '', exercises: all()).durationMin;
    while (main.length > 3 && minutes() > r.maxSessionMin) {
      main.removeLast();
    }

    return WorkoutDay(name: t.name, focus: t.focus, exercises: all(), kind: t.kind);
  }

  List<PlannedExercise> _cooldownStretches(List<PlannedExercise> main, PlanRestrictions r, ExerciseSelector selector, Map<String, int> weekUsage) {
    final worked = bodyRegions(main.where((p) => p.exercise.group != 'mobility').expand((p) => p.exercise.muscles));
    if (worked.isEmpty) return const [];
    final pool = ExerciseLibrary.all
        .where((e) => e.group == 'mobility' && !e.tags.contains('dynamic') && !e.tags.contains('balance') && r.allows(e))
        .where((e) => !main.any((p) => p.exercise.id == e.id))
        .toList();
    final scored = <(ScoredExercise, Set<String>)>[];
    for (final e in pool) {
      final overlap = bodyRegions(e.muscles).intersection(worked);
      if (overlap.isEmpty) continue;
      scored.add((selector.score(e, weekUsage: weekUsage), overlap));
    }
    // most relevant first (more worked regions stretched), then the person-fit score
    scored.sort((a, b) {
      final byOverlap = b.$2.length.compareTo(a.$2.length);
      return byOverlap != 0 ? byOverlap : b.$1.score.compareTo(a.$1.score);
    });
    final out = <PlannedExercise>[];
    final covered = <String>{};
    for (final (s, overlap) in scored) {
      if (out.length == 2) break;
      if (overlap.every(covered.contains)) continue; // would only repeat a region already stretched
      covered.addAll(overlap);
      weekUsage[s.exercise.id] = (weekUsage[s.exercise.id] ?? 0) + 1;
      out.add(_withRules(_prescribe(s.exercise, 'Low').withReasons(['Stretches what you just worked: ${overlap.map(_regionLabel).join(', ')}']), r));
    }
    return out;
  }

  static String _regionLabel(String r) => const {
        'lowerBack': 'lower back',
        'upperBack': 'upper back',
      }[r] ?? r;

  /// Replaces the MET calorie estimate with the Gradient Boosting prediction when a model is loaded.
  WorkoutDay _withModelEstimate(WorkoutDay day, HealthProfile p) {
    final model = workoutModel;
    if (model == null) return day;
    final experience = switch (p.activityLevel) {
      'Very Active' || 'Athlete' => 3,
      'Lightly Active' || 'Moderately Active' => 2,
      _ => 1,
    };
    final kcal = model.predictKcal(
      age: p.ageForCalc.toDouble(),
      male: p.gender.toLowerCase() == 'male',
      weightKg: p.weightKg,
      heightCm: p.heightCm,
      durationHours: day.durationMin / 60,
      experience: experience,
      workoutType: day.kind,
    );
    return day.withModelKcal(kcal.round());
  }

  PlannedExercise _prescribe(Exercise e, String intensity, {int? maxHold}) {
    final idx = _levels.indexOf(intensity);
    final rest = const [60, 45, 40][idx];
    final sets = const [2, 3, 4][idx];

    if (e.id == ExerciseLibrary.warmUp.id || e.id == ExerciseLibrary.coolDown.id || e.group == 'mobility') {
      return PlannedExercise(exercise: e, sets: 1, reps: 0, seconds: e.baseSeconds, restSeconds: 0);
    }
    if (e.group == 'cardio') {
      final interval = e.tags.contains('hiit') || e.impact == 'high';
      if (e.timed && !interval) {
        return PlannedExercise(exercise: e, sets: 1, reps: 0, seconds: e.baseSeconds, restSeconds: 0);
      }
      if (e.timed) {
        return PlannedExercise(exercise: e, sets: sets, reps: 0, seconds: e.baseSeconds, restSeconds: rest);
      }
    }
    if (e.timed) {
      final scale = const [0.7, 1.0, 1.3][idx];
      var seconds = ((e.baseSeconds * scale) / 5).round() * 5;
      if (maxHold != null && e.tags.contains('isometric') && seconds > maxHold) seconds = maxHold;
      return PlannedExercise(exercise: e, sets: sets, reps: 0, seconds: seconds, restSeconds: rest);
    }
    final scale = const [0.8, 1.0, 1.1][idx];
    return PlannedExercise(exercise: e, sets: sets, reps: (e.baseReps * scale).round(), seconds: 0, restSeconds: rest);
  }

  /// Attaches the safety rules that shaped this exercise for this person (Module 4 explanations).
  PlannedExercise _withRules(PlannedExercise p, PlanRestrictions r) {
    final a = r.assessment;
    if (a == null) return p;
    final d = a.decide(p.exercise);
    return d.notes.isEmpty ? p : p.withRuleNotes(d.notes);
  }

  /// One set fewer and about 30% fewer reps or seconds (never below 1 set).
  PlannedExercise _lighter(PlannedExercise p) => PlannedExercise(
        exercise: p.exercise,
        sets: p.sets > 1 ? p.sets - 1 : 1,
        reps: p.reps == 0 ? 0 : (p.reps * 0.7).round().clamp(1, p.reps),
        seconds: p.seconds == 0 ? 0 : (((p.seconds * 0.7) / 5).round() * 5).clamp(5, p.seconds),
        restSeconds: p.restSeconds,
        reasons: p.reasons,
        ruleNotes: p.ruleNotes,
      );

  // --- FR-4 / FR-6: calories, macros and meals ------------------------------

  NutritionPlan _nutrition(HealthProfile p, ClassificationResult cls, int variant) {
    final targets = p.calorieTargets;
    final ruleKcal = HealthCalc.targetFor(p.primaryGoal, targets);
    final kcal = optimizer.optimize(p, ruleKcal);
    final diabetic = p.hasCondition('Diabetes');
    final hypertension = p.hasCondition('Hypertension');
    final cardiac = cls.isCardiac;

    final macros = HealthCalc.macros(
      kcal: kcal,
      weightKg: p.weightKg,
      goal: p.primaryGoal,
      diabetic: diabetic,
      conservativeProtein: cardiac || diabetic || hypertension,
    );

    final allergies = p.allergies.map((a) => a.toLowerCase()).toList();
    final losing = p.primaryGoal == 'Lose Weight' || cls.category == 'Obese';
    final avoidTags = <String>{'sugary'};
    if (losing || cardiac || hypertension) avoidTags.addAll(['fried', 'processed']);
    if (diabetic) avoidTags.addAll(['highSugar', 'refined']);
    if (cardiac || hypertension) avoidTags.add('highSodium');

    final meals = <String, List<MealItem>>{};
    const shares = {'Breakfast': 0.25, 'Lunch': 0.35, 'Dinner': 0.30, 'Snack': 0.10};
    const recipes = {
      'Breakfast': ['bfast', 'fruit', 'drink'],
      'Lunch': ['main', 'carb', 'veg'],
      'Dinner': ['main', 'carb', 'veg'],
      'Snack': ['fruit', 'snack'],
    };
    for (final meal in shares.keys) {
      meals[meal] = _buildMeal(
        meal: meal,
        roles: recipes[meal]!,
        budget: kcal * shares[meal]!,
        allergies: allergies,
        avoidTags: avoidTags,
        variant: variant,
      );
    }

    final goalLabel = p.primaryGoal == 'Lose Weight'
        ? 'Weight Loss'
        : (p.primaryGoal == 'Gain Muscle' ? 'Muscle Gain' : 'Maintenance');

    return NutritionPlan(
      goalLabel: goalLabel,
      targetKcal: kcal,
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      waterLitres: HealthCalc.waterLitres(p.weightKg),
      meals: meals,
      avoid: _avoidList(p, cls, allergies),
      tips: _tips(p, cls),
      tipPool: tipPoolFor(p, cls),
      calorieNote: p.primaryGoal == 'Lose Weight' ? targets.safetyNote : null,
    );
  }

  List<MealItem> _buildMeal({
    required String meal,
    required List<String> roles,
    required double budget,
    required List<String> allergies,
    required Set<String> avoidTags,
    required int variant,
  }) {
    final mealKey = meal.toLowerCase();
    final chosen = <FoodItem>[];

    for (final role in roles) {
      final pool = foods.items.where((f) {
        if (f.role != role || !f.meals.contains(mealKey)) return false;
        if (f.allergens.any(allergies.contains)) return false;
        if (f.tags.any(avoidTags.contains)) return false;
        return true;
      }).toList();
      if (pool.isEmpty) continue;
      final seed = variant + role.codeUnits.fold<int>(0, (s, c) => s + c) + meal.codeUnits.fold<int>(0, (s, c) => s + c);
      final pick = pool[seed % pool.length];
      if (chosen.every((c) => c.id != pick.id)) chosen.add(pick);
    }

    if (chosen.isEmpty) return const [];

    // Scale the substantial items (main / carb / breakfast dish) to the budget.
    bool scalable(FoodItem f) => f.role == 'main' || f.role == 'carb' || f.role == 'bfast' || f.role == 'snack';
    final fixedKcal = chosen.where((f) => !scalable(f)).fold(0.0, (s, f) => s + f.kcal);
    final scalableKcal = chosen.where(scalable).fold(0.0, (s, f) => s + f.kcal);
    var factor = 1.0;
    if (scalableKcal > 0) {
      final room = budget - fixedKcal;
      factor = room <= 0 ? 0.5 : room / scalableKcal;
    }
    double snap(double v) => ((v * 2).round() / 2).clamp(0.5, 2.5).toDouble();

    return [for (final f in chosen) MealItem(f, scalable(f) ? snap(factor) : 1.0)];
  }

  List<String> _avoidList(HealthProfile p, ClassificationResult cls, List<String> allergies) {
    final avoid = <String>[];
    for (final a in p.allergies) {
      avoid.add('$a products');
    }
    final losing = p.primaryGoal == 'Lose Weight' || cls.category == 'Obese';
    if (losing || p.hasCondition('Diabetes')) {
      avoid.addAll(['Sugary drinks', 'Sweets & desserts']);
    }
    if (losing || cls.isCardiac || p.hasCondition('Hypertension')) {
      avoid.addAll(['Deep-fried foods', 'Processed snacks']);
    }
    if (p.hasCondition('Diabetes')) avoid.addAll(['White bread & refined carbs', 'Fruit juices']);
    if (cls.isCardiac || p.hasCondition('Hypertension')) avoid.add('High-salt foods (pickles, chips, instant noodles)');
    if (avoid.isEmpty) avoid.addAll(['Sugary drinks', 'Highly processed snacks']);
    return avoid.toSet().toList();
  }

  /// Advice that always applies to this person. It does not rotate.
  List<String> _tips(HealthProfile p, ClassificationResult cls) {
    final tips = <String>['Drink about ${HealthCalc.waterLitres(p.weightKg).toStringAsFixed(1)} L of water daily.'];
    if (p.primaryGoal == 'Lose Weight') tips.add('Include protein at every meal to stay full and protect muscle.');
    if (p.primaryGoal == 'Gain Muscle') tips.add('Eat protein within 2 hours after training.');
    if (p.hasCondition('Diabetes')) tips.add('Spread carbohydrates evenly across meals and monitor your blood sugar.');
    if (cls.isCardiac || p.hasCondition('Hypertension')) tips.add('Keep salt under 5 g (about 1 teaspoon) per day.');
    return tips;
  }

  /// General tips that rotate day by day (Module 9, FR26.4). Written by the project team as common healthy-eating practice;
  /// they deliberately contain no figures, so nothing in them needs a source. Some are only for a goal or condition.
  static const _generalTips = <String>[
    'Add vegetables to every main meal for fibre.',
    'Eat dinner a couple of hours before you go to bed.',
    'Sit down and eat slowly. It takes a while for fullness to register.',
    'Plan tomorrow\'s meals tonight so you are not deciding when hungry.',
    'Keep a bottle of water with you and sip through the day.',
    'Choose whole grains such as brown rice, oats or whole-wheat roti more often than refined ones.',
    'Fill half your plate with vegetables or salad before adding the rest.',
    'Read the ingredient list, not just the front of the packet.',
    'Keep fruit where you can see it. Easy snacks get eaten.',
    'Cook at home when you can: you decide the oil, salt and portion.',
    'Grilling, baking or steaming instead of deep frying keeps meals lighter.',
    'Do not skip breakfast if it keeps you from overeating later.',
    'Spread your protein across the day instead of eating most of it at dinner.',
    'Swap sugary drinks for water, unsweetened tea or plain lassi.',
    'Use a smaller plate if you tend to overfill it.',
    'Pause before a second helping and ask whether you are still hungry.',
    'Pulses such as daal, chana and lobia are cheap sources of protein and fibre.',
    'Keep a healthy snack ready, such as nuts, yoghurt or fruit, so a hungry moment does not become a fast-food stop.',
    'Eat the colours: different coloured vegetables bring different nutrients.',
    'Limit treats to a planned portion instead of eating from the packet.',
    'Switch off screens at meals. You will notice when you are full.',
    'Prepare a few meals in advance on a quiet day for busy ones.',
    'Notice liquid calories: juices, shakes and sweet tea add up quickly.',
    'Season with herbs, lemon and spices rather than extra salt.',
    'Keep your food diary honest. It only helps if it includes the small bites too.',
    'A short walk after a meal is a simple habit that many people find helpful.',
    'Shop with a list and not when hungry.',
    'Include some healthy fat, such as nuts, seeds or olive oil, in moderation.',
  ];

  /// Extra tips for a goal or condition, added to the rotation for the people they apply to.
  static const _goalTips = <String, List<String>>{
    'Lose Weight': [
      'A modest, steady calorie deficit is easier to keep than a harsh one.',
      'Protein and fibre together keep you full for longer.',
    ],
    'Gain Muscle': [
      'Eat regularly through the day: three meals plus snacks make it easier to reach your calories.',
      'Pair your training with enough protein and enough sleep. Muscle is built during recovery.',
    ],
    'Diabetes': [
      'Choose carbohydrates that digest slowly, such as whole grains and pulses, and pair them with protein.',
      'Check labels for hidden sugar in sauces, drinks and breakfast cereals.',
    ],
    'Hypertension': [
      'Pickles, chips, instant noodles and many sauces are high in salt; check how often you eat them.',
      'Potassium-rich foods such as bananas, potatoes and leafy greens can help, unless your doctor has told you otherwise.',
    ],
  };

  /// The rotating tips for this person: the general ones plus those for their goal and conditions.
  static List<String> tipPoolFor(HealthProfile p, ClassificationResult cls) {
    final pool = <String>[..._generalTips];
    pool.addAll(_goalTips[p.primaryGoal] ?? const []);
    if (p.hasCondition('Diabetes')) pool.addAll(_goalTips['Diabetes']!);
    if (cls.isCardiac || p.hasCondition('Hypertension')) pool.addAll(_goalTips['Hypertension']!);
    return pool;
  }
}

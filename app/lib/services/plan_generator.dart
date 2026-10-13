import '../models/food.dart';
import '../models/health_profile.dart';
import '../models/plan.dart';
import '../utils/health_calc.dart';
import 'exercise_library.dart';
import 'exercise_selector.dart';
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
  });

  bool allows(Exercise e) {
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

  PersonalizedPlan generate(HealthProfile profile, ClassificationResult cls, {int variant = 0}) {
    final intensity = _intensity(profile, cls);
    final restrictions = _restrictions(profile, cls, intensity);

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
    for (var i = 0; i < slots.length; i++) {
      final template = templates[(i + variant) % templates.length];
      week[slots[i]] = _withModelEstimate(_buildDay(template, intensity, restrictions, profile.weightKg, selector, weekUsage), profile);
    }

    return PersonalizedPlan(
      category: cls.category,
      intensity: intensity,
      variant: variant,
      week: week,
      restrictionNotes: restrictions.notes,
      nutrition: _nutrition(profile, cls, variant),
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

  PlanRestrictions _restrictions(HealthProfile p, ClassificationResult cls, String intensity) {
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
    // Heart disease: no static holds as a precaution (needs clinician review).
    // Hypertension: holds stay but are kept short, with breathing cues.
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
    if (asthma) {
      notes.add('Asthma: high-intensity intervals are removed. Warm up thoroughly and keep your reliever inhaler with you.');
    }
    if (obese && !cardiac) {
      notes.add('BMI ${bmi.toStringAsFixed(1)}: jumping and running-style moves are replaced with low-impact options to protect your knees and ankles.');
    } else if (overweight && !noHighImpact) {
      notes.add('Jump (plyometric) exercises are removed to reduce joint stress at your current weight.');
    }
    if (underweight) {
      notes.add('Underweight BMI: the plan focuses on strength training and limits cardio so you do not burn the energy you need to gain healthy weight.');
    }
    if (senior) {
      notes.add('Age 55+: high-impact moves are removed as a precaution.');
    }
    if (age >= 65) {
      notes.add('Age 65+: balance training is added, as WHO recommends for older adults.');
    }
    if (beginner) {
      notes.add('You are starting from a sedentary baseline, so sessions are shorter and exercises are beginner-friendly. Increase gradually.');
    }
    if (notes.isEmpty) {
      notes.add('No medical restrictions detected. Warm up before every session and stop if something hurts.');
    }

    return PlanRestrictions(
      noHighImpact: noHighImpact,
      noHiit: noHiit,
      noIsometric: noIsometric,
      noPlyo: noPlyo,
      includeBalance: age >= 65,
      strengthFocus: underweight,
      maxLevel: maxLevel,
      maxDays: maxDays,
      maxSessionMin: maxSession,
      maxHoldSeconds: hypertension ? 20 : null,
      notes: notes,
    );
  }

  // --- FR-2 / FR-5: templates and weekly schedule --------------------------

  WorkoutDay _buildDay(_Template t, String intensity, PlanRestrictions r, double weightKg, ExerciseSelector selector, Map<String, int> weekUsage) {
    final usedIds = <String>{};
    final main = <PlannedExercise>[];

    for (final slot in t.slots) {
      final pool = ExerciseLibrary.all.where((e) => e.group == slot.group && r.allows(e) && !usedIds.contains(e.id)).toList();
      if (pool.isEmpty) continue;
      for (final picked in selector.rank(pool, weekUsage: weekUsage).take(slot.count)) {
        usedIds.add(picked.exercise.id);
        weekUsage[picked.exercise.id] = (weekUsage[picked.exercise.id] ?? 0) + 1;
        main.add(_prescribe(picked.exercise, intensity, maxHold: r.maxHoldSeconds).withReasons(picked.reasons));
      }
    }

    // Steady-state cardio shares the session's cardio minutes.
    final steady = main.where((p) => p.exercise.group == 'cardio' && p.sets == 1 && p.timed).toList();
    if (steady.isNotEmpty) {
      final totalMin = intensity == 'Low' ? 16 : (intensity == 'Moderate' ? 20 : 24);
      final eachSec = ((totalMin * 60 / steady.length) / 30).round() * 30;
      for (final s in steady) {
        final i = main.indexOf(s);
        main[i] = PlannedExercise(exercise: s.exercise, sets: 1, reps: 0, seconds: eachSec, restSeconds: s.restSeconds, reasons: s.reasons);
      }
    }

    if (r.includeBalance) {
      final balance = ExerciseLibrary.all.firstWhere((e) => e.id == 'single_leg_balance');
      main.add(_prescribe(balance, intensity, maxHold: r.maxHoldSeconds).withReasons(const ['Balance training is recommended from age 65']));
    }

    // Cool-down: up to two static stretches for the body regions this session actually worked.
    final stretches = _cooldownStretches(main, r, selector, weekUsage);

    final warm = _prescribe(ExerciseLibrary.warmUp, intensity);
    final cool = _prescribe(ExerciseLibrary.coolDown, intensity);

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
      out.add(_prescribe(s.exercise, 'Low').withReasons(['Stretches what you just worked: ${overlap.map(_regionLabel).join(', ')}']));
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

  List<String> _tips(HealthProfile p, ClassificationResult cls) {
    final tips = <String>[
      'Drink about ${HealthCalc.waterLitres(p.weightKg).toStringAsFixed(1)} L of water daily.',
      'Eat dinner at least 2 hours before sleep.',
      'Add vegetables to every main meal for fibre.',
    ];
    if (p.primaryGoal == 'Lose Weight') tips.add('Include protein at every meal to stay full and protect muscle.');
    if (p.primaryGoal == 'Gain Muscle') tips.add('Eat protein within 2 hours after training.');
    if (p.hasCondition('Diabetes')) tips.add('Spread carbohydrates evenly across meals and monitor your blood sugar.');
    if (cls.isCardiac || p.hasCondition('Hypertension')) tips.add('Keep salt under 5 g (about 1 teaspoon) per day.');
    return tips;
  }
}

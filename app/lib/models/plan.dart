import 'food.dart';

/// An exercise in the library (Module 3, FR-2 templates draw from this).
class Exercise {
  final String id;
  final String name;
  final String icon;

  /// cardio | legs | push | back | core | mobility
  final String group;
  final List<String> muscles;

  /// low | high
  final String impact;

  /// 1 beginner … 3 advanced.
  final int level;

  /// Metabolic equivalent, used to estimate calories burned. Values come from
  /// the 2024 Adult Compendium of Physical Activities.
  final double met;

  /// Compendium code the MET value was taken from. A trailing `*` means the
  /// exercise is not listed itself and the closest listed activity was used.
  final String compendium;

  /// True for exercises prescribed by time rather than repetitions.
  final bool timed;
  final int baseReps;
  final int baseSeconds;

  /// Medical-rule tags: hiit, plyo, isometric, balance.
  final List<String> tags;
  final List<String> steps;

  /// Where the technique text and muscle list come from: `free-exercise-db`
  /// (open public-domain dataset, adapted for safe dosing) or `team`
  /// (written by the project team, pending professional review).
  final String techniqueSource;

  /// Entry in the open dataset this exercise was matched to, if any, and how
  /// close the match is (`exact` or `related`).
  final String? referenceId;
  final String? referenceMatch;

  /// Body regions the movement loads: knee, wrist, shoulder, lowerBack, ankle. Team-assigned, pending professional review.
  final List<String> joints;

  /// standing | seated | floor: how hard the movement is to get into and out of.
  final String position;

  /// Coordination demand, 1 (simple) to 3 (complex).
  final int complexity;

  /// compound | isolation | '' (not stated).
  final String mechanic;

  /// What you need besides your body: none, or e.g. "sturdy table, counter or wall".
  final String equipment;

  const Exercise({
    required this.id,
    required this.name,
    required this.icon,
    required this.group,
    required this.muscles,
    required this.impact,
    required this.level,
    required this.met,
    this.compendium = '',
    required this.steps,
    this.timed = false,
    this.baseReps = 10,
    this.baseSeconds = 30,
    this.tags = const [],
    this.techniqueSource = 'team',
    this.referenceId,
    this.referenceMatch,
    this.joints = const [],
    this.position = 'standing',
    this.complexity = 1,
    this.mechanic = '',
    this.equipment = 'none',
  });

  factory Exercise.fromJson(Map<String, dynamic> j) {
    List<String> list(dynamic v) => (v as List? ?? const []).map((e) => e.toString()).toList();
    return Exercise(
      id: j['id'] as String,
      name: j['name'] as String,
      icon: j['icon'] as String? ?? '🏋️',
      group: j['group'] as String,
      muscles: list(j['muscles']),
      impact: j['impact'] as String? ?? 'low',
      level: (j['level'] as num?)?.toInt() ?? 1,
      met: (j['met'] as num).toDouble(),
      compendium: j['compendium'] as String? ?? '',
      timed: j['timed'] as bool? ?? false,
      baseReps: (j['baseReps'] as num?)?.toInt() ?? 10,
      baseSeconds: (j['baseSeconds'] as num?)?.toInt() ?? 30,
      tags: list(j['tags']),
      steps: list(j['steps']),
      techniqueSource: j['techniqueSource'] as String? ?? 'team',
      referenceId: j['referenceId'] as String?,
      referenceMatch: j['referenceMatch'] as String?,
      joints: list(j['joints']),
      position: j['position'] as String? ?? 'standing',
      complexity: (j['complexity'] as num?)?.toInt() ?? 1,
      mechanic: j['mechanic'] as String? ?? '',
      equipment: j['equipment'] as String? ?? 'none',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'group': group,
        'muscles': muscles,
        'impact': impact,
        'level': level,
        'met': met,
        'compendium': compendium,
        'timed': timed,
        'baseReps': baseReps,
        'baseSeconds': baseSeconds,
        'tags': tags,
        'steps': steps,
        'techniqueSource': techniqueSource,
        if (referenceId != null) 'referenceId': referenceId,
        if (referenceMatch != null) 'referenceMatch': referenceMatch,
        'joints': joints,
        'position': position,
        'complexity': complexity,
        'mechanic': mechanic,
        'equipment': equipment,
      };

  String get levelLabel => level == 1 ? 'Low' : (level == 2 ? 'Medium' : 'High');
}

/// An exercise as prescribed in a specific workout.
class PlannedExercise {
  final Exercise exercise;
  final int sets;
  final int reps; // 0 when timed
  final int seconds; // per set when timed, else 0
  final int restSeconds;

  /// Why this exercise was chosen for this person (empty for the fixed warm-up and cool-down).
  final List<String> reasons;

  const PlannedExercise({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.seconds,
    required this.restSeconds,
    this.reasons = const [],
  });

  PlannedExercise withReasons(List<String> r) =>
      PlannedExercise(exercise: exercise, sets: sets, reps: reps, seconds: seconds, restSeconds: restSeconds, reasons: r);

  bool get timed => exercise.timed;

  /// "3×12", "3×45s" or "20 min".
  String get prescription {
    if (!timed) return '$sets×$reps';
    if (sets == 1 && seconds >= 120) return '${(seconds / 60).round()} min';
    return sets == 1 ? '${seconds}s' : '$sets×${seconds}s';
  }

  int get activeSeconds => timed ? sets * seconds : (sets * reps * 3.5).round();
  int get totalSeconds => activeSeconds + (sets > 1 ? (sets - 1) * restSeconds : 0);

  /// Estimated energy use: MET × body weight (kg) × hours of activity.
  double kcal(double weightKg) => exercise.met * weightKg * activeSeconds / 3600;
}

class WorkoutDay {
  final String name;
  final String focus;
  final List<PlannedExercise> exercises;

  /// Cardio, HIIT, Strength or Yoga — the session type the calorie model was trained on.
  final String kind;

  /// Calories from the Gradient Boosting model (Phase 2), or null to use the MET estimate.
  final int? modelKcal;

  const WorkoutDay({required this.name, required this.focus, required this.exercises, this.kind = 'Strength', this.modelKcal});

  WorkoutDay withModelKcal(int kcal) =>
      WorkoutDay(name: name, focus: focus, exercises: exercises, kind: kind, modelKcal: kcal);

  int get durationMin => (exercises.fold<int>(0, (s, e) => s + e.totalSeconds) / 60).ceil();

  /// Calories for the whole session: the trained model's estimate when available, otherwise
  /// MET × weight × time from the Compendium.
  int kcal(double weightKg) => modelKcal ?? metKcal(weightKg);

  int metKcal(double weightKg) => exercises.fold<double>(0, (s, e) => s + e.kcal(weightKg)).round();
}

class MealItem {
  final FoodItem food;
  final double servings;
  const MealItem(this.food, this.servings);

  double get kcal => food.kcal * servings;
  double get protein => food.protein * servings;
  double get carbs => food.carbs * servings;
  double get fat => food.fat * servings;

  String get servingText {
    final s = servings == servings.roundToDouble() ? servings.toStringAsFixed(0) : servings.toStringAsFixed(1);
    return servings == 1 ? food.servingLabel : '$s × ${food.servingLabel}';
  }
}

class NutritionPlan {
  final String goalLabel;
  final int targetKcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final double waterLitres;

  /// Breakfast / Lunch / Dinner / Snack → items.
  final Map<String, List<MealItem>> meals;
  final List<String> avoid;
  final List<String> tips;
  final String? calorieNote;

  const NutritionPlan({
    required this.goalLabel,
    required this.targetKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.waterLitres,
    required this.meals,
    required this.avoid,
    required this.tips,
    this.calorieNote,
  });

  double mealKcal(String meal) => (meals[meal] ?? const []).fold(0.0, (s, i) => s + i.kcal);
}

class PersonalizedPlan {
  final String category;
  final String intensity; // Low / Moderate / High
  final int variant;

  /// Monday … Sunday; null means rest day.
  final List<WorkoutDay?> week;

  /// Medical restriction rules that were applied (Module 3, FR-1).
  final List<String> restrictionNotes;
  final NutritionPlan nutrition;

  const PersonalizedPlan({
    required this.category,
    required this.intensity,
    required this.variant,
    required this.week,
    required this.restrictionNotes,
    required this.nutrition,
  });

  int get workoutDays => week.where((d) => d != null).length;

  /// Today's workout (null on a rest day). `DateTime.weekday`: Mon = 1.
  WorkoutDay? workoutFor(DateTime date) => week[date.weekday - 1];
}

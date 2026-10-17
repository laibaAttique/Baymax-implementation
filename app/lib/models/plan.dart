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

  // --- Module 4 knowledge base (free-exercise-db catalogue). Defaults describe the curated library. ---

  /// `baymax` (curated library, team-reviewed cues) or `free-exercise-db` (catalogue entry, dataset instructions).
  final String source;

  /// The dataset's category (strength, cardio, stretching, plyometrics, …); empty for curated entries.
  final String category;

  /// Normalised equipment the exercise needs, used to match what the user owns: none, dumbbell, barbell, kettlebell,
  /// bands, cable, machine, medicine_ball, exercise_ball, ez_bar, foam_roller, other.
  final String equipmentKey;

  /// Photos of the movement (free-exercise-db, pinned commit). Empty when none are available.
  final List<String> imageUrls;

  /// How [met] was matched to the 2024 Adult Compendium, when stated explicitly (catalogue entries).
  final String? metMatchValue;

  /// How [met] was matched to the 2024 Adult Compendium: exact | approximate | unmatched. For curated entries a
  /// trailing `*` on [compendium] means approximate (closest listed activity).
  String get metMatch =>
      metMatchValue ?? (compendium.isEmpty ? 'unmatched' : (compendium.endsWith('*') ? 'approximate' : 'exact'));

  /// The Compendium activity description behind [compendium], when known.
  final String metDescription;

  /// Review state of the MET mapping and team-derived fields: pending until a qualified reviewer approves them.
  final String reviewStatus;

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
    this.source = 'baymax',
    this.category = '',
    this.equipmentKey = 'none',
    this.imageUrls = const [],
    this.metMatchValue,
    this.metDescription = '',
    this.reviewStatus = 'pending',
  });

  /// A free-exercise-db catalogue entry (`assets/data/exercise_catalog.json`, built by ml/exercise_catalog/build_catalog.py).
  /// Dataset fields are used as they are; planning fields come from the documented derivation rules.
  factory Exercise.fromCatalog(Map<String, dynamic> j) {
    List<String> list(dynamic v) => (v as List? ?? const []).map((e) => e.toString()).toList();
    final data = j['dataset'] as Map<String, dynamic>;
    final derived = j['derived'] as Map<String, dynamic>;
    final met = j['met'] as Map<String, dynamic>;
    final timed = derived['timed'] as bool? ?? false;
    final category = data['category'] as String? ?? '';
    String title(String m) => m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1)}';
    return Exercise(
      id: j['id'] as String,
      name: data['name'] as String,
      icon: derived['icon'] as String? ?? '🏋️',
      group: derived['group'] as String,
      muscles: [...list(data['primaryMuscles']), ...list(data['secondaryMuscles'])].map(title).toList(),
      impact: derived['impact'] as String? ?? 'unknown',
      level: (derived['levelNumber'] as num?)?.toInt() ?? 2,
      met: (met['value'] as num?)?.toDouble() ?? 0,
      compendium: met['code'] == null ? '' : '${met['code']}${met['match'] == 'exact' ? '' : '*'}',
      steps: list(data['instructions']),
      timed: timed,
      baseReps: 10,
      baseSeconds: category == 'cardio' ? 600 : 30,
      tags: list(derived['tags']),
      techniqueSource: 'free-exercise-db',
      referenceId: j['id'] as String,
      referenceMatch: 'exact',
      joints: list(derived['joints']),
      position: '',
      complexity: (derived['complexity'] as num?)?.toInt() ?? 1,
      mechanic: data['mechanic'] as String? ?? '',
      equipment: derived['equipmentKey'] == 'none' ? 'none' : (data['equipment'] as String? ?? 'other'),
      source: 'free-exercise-db',
      category: category,
      equipmentKey: derived['equipmentKey'] as String? ?? 'other',
      imageUrls: list(j['imageUrls']),
      metMatchValue: met['match'] as String? ?? 'unmatched',
      metDescription: met['description'] as String? ?? '',
      reviewStatus: met['reviewStatus'] as String? ?? 'pending',
    );
  }

  /// The same exercise with photos and the Compendium wording attached (used to show the dataset photos for
  /// curated exercises that are an exact match).
  Exercise withCatalogDetails({List<String>? imageUrls, String? metDescription}) => Exercise(
        id: id,
        name: name,
        icon: icon,
        group: group,
        muscles: muscles,
        impact: impact,
        level: level,
        met: met,
        compendium: compendium,
        steps: steps,
        timed: timed,
        baseReps: baseReps,
        baseSeconds: baseSeconds,
        tags: tags,
        techniqueSource: techniqueSource,
        referenceId: referenceId,
        referenceMatch: referenceMatch,
        joints: joints,
        position: position,
        complexity: complexity,
        mechanic: mechanic,
        equipment: equipment,
        source: source,
        category: category,
        equipmentKey: equipmentKey,
        imageUrls: imageUrls ?? this.imageUrls,
        metMatchValue: metMatchValue,
        metDescription: metDescription ?? this.metDescription,
        reviewStatus: reviewStatus,
      );

  /// True when an energy estimate can be made for this exercise.
  bool get hasMet => met > 0 && metMatch != 'unmatched';

  /// Intensity band of the mapped Compendium activity (WHO 2020: light < 3 MET, moderate 3–5.9, vigorous ≥ 6), or null
  /// when no MET value is known. Comes from [met] only, never from the name.
  IntensityBand? get intensityBand => !hasMet ? null : IntensityBand.ofMet(met);

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

  /// Safety rules that shaped this exercise for this person, e.g. "Hold capped at 20 s (MED-HTN, pending review)".
  final List<String> ruleNotes;

  const PlannedExercise({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.seconds,
    required this.restSeconds,
    this.reasons = const [],
    this.ruleNotes = const [],
  });

  PlannedExercise withReasons(List<String> r) => PlannedExercise(
      exercise: exercise, sets: sets, reps: reps, seconds: seconds, restSeconds: restSeconds, reasons: r, ruleNotes: ruleNotes);

  PlannedExercise withRuleNotes(List<String> notes) => PlannedExercise(
      exercise: exercise, sets: sets, reps: reps, seconds: seconds, restSeconds: restSeconds, reasons: reasons, ruleNotes: notes);

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
  /// Advice that always applies to this person (their conditions, goal and water target). Shown as "For your health".
  final List<String> tips;

  /// Everyday nutrition tips that rotate (Module 9, mockup M26 FR26.4): see [tipsFor].
  final List<String> tipPool;
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
    this.tipPool = const [],
    this.calorieNote,
  });

  /// [count] tips for [day], taken in order from [tipPool] and moved on every day, so no tip repeats inside any 7 consecutive days
  /// as long as the pool holds at least 7 x [count] tips.
  List<String> tipsFor(DateTime day, {int count = 3}) {
    if (tipPool.isEmpty) return const [];
    final dayNumber = DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final start = (dayNumber * count) % tipPool.length;
    return [for (var k = 0; k < count && k < tipPool.length; k++) tipPool[(start + k) % tipPool.length]];
  }

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

  /// Module 4 pre-exercise screening. When it is not [WorkoutGateStatus.eligible] the week is empty and [WorkoutGate.reasons]
  /// say what is needed (more answers, or a doctor's clearance). Null when the plan was generated without screening.
  final WorkoutGate? gate;

  /// Version of the safety rule repository the plan was generated with (and of the classification profiles, after a `+`).
  final String rulesVersion;

  /// The week measured against the classification's training profile (Module 4). Null when no week was generated.
  final PlanProfileSummary? profile;

  const PersonalizedPlan({
    required this.category,
    required this.intensity,
    required this.variant,
    required this.week,
    required this.restrictionNotes,
    required this.nutrition,
    this.gate,
    this.rulesVersion = '',
    this.profile,
  });

  /// False when screening stopped the plan from being generated.
  bool get workoutAvailable => gate == null || gate!.status == WorkoutGateStatus.eligible;

  int get workoutDays => week.where((d) => d != null).length;

  /// Today's workout (null on a rest day). `DateTime.weekday`: Mon = 1.
  WorkoutDay? workoutFor(DateTime date) => week[date.weekday - 1];
}

enum WorkoutGateStatus {
  eligible,

  /// Something the rules need is missing (e.g. the readiness questions); the user can answer it in the app.
  needsInfo,

  /// A rule requires a doctor's clearance before any plan is generated.
  needsClearance,
}

/// The plan-level screening result.
class WorkoutGate {
  final WorkoutGateStatus status;

  /// Why, one sentence per rule that applied.
  final List<String> reasons;

  /// Ids of the rules that decided it.
  final List<String> ruleIds;
  const WorkoutGate(this.status, {this.reasons = const [], this.ruleIds = const []});
}

/// Physical-activity intensity by MET (WHO 2020 guidelines on physical activity and sedentary behaviour).
enum IntensityBand {
  light('Light', '< 3 MET'),
  moderate('Moderate', '3–5.9 MET'),
  vigorous('Vigorous', '≥ 6 MET');

  final String label;
  final String range;
  const IntensityBand(this.label, this.range);

  static IntensityBand ofMet(double met) => met < 3 ? light : (met < 6 ? moderate : vigorous);
}

/// How the generated week compares with the training profile of the person's Module 2 classification (Module 4).
class PlanProfileSummary {
  /// e.g. PRF-CARDIAC.
  final String profileId;
  final String category;

  /// What the profile emphasises, in plain words.
  final String emphasis;

  /// Highest intensity scheduled for this profile.
  final IntensityBand maxBand;

  /// Planned aerobic minutes this week, moderate-equivalent (a vigorous minute counts as two, as in WHO 2020).
  final int aerobicMinutes;
  final int aerobicTargetMin;
  final int aerobicTargetMax;

  /// Days with muscle-strengthening work / with stretching.
  final int strengthDays;
  final int strengthTarget;
  final int flexibilityDays;
  final int flexibilityTarget;

  /// Explanations and suggestions, each ending with the id of the profile entry it came from.
  final List<String> notes;
  final List<String> evidence;

  const PlanProfileSummary({
    required this.profileId,
    required this.category,
    required this.emphasis,
    required this.maxBand,
    required this.aerobicMinutes,
    required this.aerobicTargetMin,
    required this.aerobicTargetMax,
    required this.strengthDays,
    required this.strengthTarget,
    required this.flexibilityDays,
    required this.flexibilityTarget,
    this.notes = const [],
    this.evidence = const [],
  });

  bool get aerobicMet => aerobicMinutes >= aerobicTargetMin;
  bool get strengthMet => strengthDays >= strengthTarget;
  bool get flexibilityMet => flexibilityDays >= flexibilityTarget;
}

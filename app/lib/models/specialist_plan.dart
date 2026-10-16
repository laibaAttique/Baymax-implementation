/// Module 14 (FR-5, FR-9, FR-10): what a nutritionist, trainer or doctor set for this member through the specialist portal.
/// Stored at `specialistPlans/{uid}/diet|workout` and `dietReviews/{uid}/{date}`, written only by the portal's server.

class PlanAuthor {
  final String name;
  final String role; // doctor | nutritionist | trainer
  const PlanAuthor(this.name, this.role);

  String get roleLabel => const {'doctor': 'Doctor', 'nutritionist': 'Nutritionist', 'trainer': 'Trainer'}[role] ?? 'Specialist';

  /// "Sara Khan, Nutritionist"
  String get label => '$name, $roleLabel';

  static PlanAuthor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return PlanAuthor(name.trim(), (raw['role'] as String?) ?? '');
  }
}

/// A diet plan set by a specialist: approved as it was, or changed (calorie target, macros, foods to avoid, tips).
class SpecialistDietPlan {
  final bool approvedAsIs;
  final String note;
  final int? targetKcal;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;
  final List<String> avoid;
  final List<String> tips;
  final PlanAuthor by;
  final DateTime at;

  const SpecialistDietPlan({
    required this.approvedAsIs,
    this.note = '',
    this.targetKcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.avoid = const [],
    this.tips = const [],
    required this.by,
    required this.at,
  });

  bool get hasMacros => proteinG != null && carbsG != null && fatG != null;

  static SpecialistDietPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'];
    final by = PlanAuthor.fromJson(raw['by']);
    if ((status != 'approved' && status != 'modified') || by == null) return null;
    int? n(Object? v, int lo, int hi) => v is num && v >= lo && v <= hi ? v.toInt() : null;
    List<String> list(Object? v) => v is List ? [for (final x in v) if (x is String && x.trim().isNotEmpty) x.trim()] : const [];
    final protein = n(raw['proteinG'], 0, 500), carbs = n(raw['carbsG'], 0, 1000), fat = n(raw['fatG'], 0, 300);
    final allMacros = protein != null && carbs != null && fat != null;
    return SpecialistDietPlan(
      approvedAsIs: status == 'approved',
      note: (raw['note'] as String?) ?? '',
      targetKcal: n(raw['targetKcal'], 800, 5000),
      // Macros only count as a set; a partial set is ignored rather than half applied.
      proteinG: allMacros ? protein : null,
      carbsG: allMacros ? carbs : null,
      fatG: allMacros ? fat : null,
      avoid: list(raw['avoid']),
      tips: list(raw['tips']),
      by: by,
      at: DateTime.fromMillisecondsSinceEpoch(((raw['at'] as num?) ?? 0).toInt()),
    );
  }
}

class SpecialistExercise {
  final String exerciseId;
  final int sets;
  final int reps; // 0 when timed
  final int seconds; // 0 when counted
  final String note;
  const SpecialistExercise({required this.exerciseId, required this.sets, this.reps = 0, this.seconds = 0, this.note = ''});
}

class SpecialistWorkoutDay {
  /// ISO weekday, Monday = 1.
  final int day;
  final bool rest;
  final List<SpecialistExercise> items;
  const SpecialistWorkoutDay({required this.day, required this.rest, this.items = const []});
}

/// A workout plan set by a specialist: approved as it was, or a full weekly schedule built from the exercise library.
class SpecialistWorkoutPlan {
  final bool approvedAsIs;
  final String note;
  final List<SpecialistWorkoutDay> schedule;
  final PlanAuthor by;
  final DateTime at;

  const SpecialistWorkoutPlan({required this.approvedAsIs, this.note = '', this.schedule = const [], required this.by, required this.at});

  static SpecialistWorkoutPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'];
    final by = PlanAuthor.fromJson(raw['by']);
    if ((status != 'approved' && status != 'modified') || by == null) return null;
    final days = <SpecialistWorkoutDay>[];
    final rawDays = raw['schedule'];
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is! Map || d['day'] is! num) continue;
        final day = (d['day'] as num).toInt();
        if (day < 1 || day > 7) continue;
        final items = <SpecialistExercise>[];
        if (d['items'] is List) {
          for (final it in d['items'] as List) {
            if (it is! Map || it['exerciseId'] is! String || it['sets'] is! num) continue;
            items.add(SpecialistExercise(
              exerciseId: it['exerciseId'] as String,
              sets: (it['sets'] as num).toInt().clamp(1, 8),
              reps: ((it['reps'] as num?) ?? 0).toInt(),
              seconds: ((it['seconds'] as num?) ?? 0).toInt(),
              note: (it['note'] as String?) ?? '',
            ));
          }
        }
        days.add(SpecialistWorkoutDay(day: day, rest: d['rest'] == true || items.isEmpty, items: items));
      }
    }
    final modified = status == 'modified';
    // A "modified" plan without a usable schedule is ignored rather than leaving the member with an empty week.
    if (modified && (days.length != 7 || days.every((d) => d.rest))) return null;
    return SpecialistWorkoutPlan(
      approvedAsIs: !modified,
      note: (raw['note'] as String?) ?? '',
      schedule: modified ? (days..sort((a, b) => a.day.compareTo(b.day))) : const [],
      by: by,
      at: DateTime.fromMillisecondsSinceEpoch(((raw['at'] as num?) ?? 0).toInt()),
    );
  }
}

class SpecialistPlans {
  final SpecialistDietPlan? diet;
  final SpecialistWorkoutPlan? workout;
  const SpecialistPlans({this.diet, this.workout});

  static const none = SpecialistPlans();

  bool get isEmpty => diet == null && workout == null;

  static SpecialistPlans fromJson(Object? raw) =>
      raw is Map ? SpecialistPlans(diet: SpecialistDietPlan.fromJson(raw['diet']), workout: SpecialistWorkoutPlan.fromJson(raw['workout'])) : none;
}

/// Whether the member follows their specialist's plan or Baymax's own (their choice, kept in `users/{uid}/planChoice`).
class PlanChoices {
  final bool specialistDiet;
  final bool specialistWorkout;
  const PlanChoices({this.specialistDiet = true, this.specialistWorkout = true});

  static const defaults = PlanChoices();

  static PlanChoices fromJson(Object? raw) => raw is Map
      ? PlanChoices(specialistDiet: raw['diet'] != 'baymax', specialistWorkout: raw['workout'] != 'baymax')
      : defaults;

  PlanChoices copyWith({bool? diet, bool? workout}) => PlanChoices(specialistDiet: diet ?? specialistDiet, specialistWorkout: workout ?? specialistWorkout);
}

/// A nutritionist's verdict on one day of the member's food log (FR-9).
class DietReview {
  final String date; // yyyy-mm-dd
  final bool approved;
  final String note;
  final String reviewer;
  final DateTime at;
  const DietReview({required this.date, required this.approved, this.note = '', required this.reviewer, required this.at});

  static DietReview? fromJson(String date, Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'];
    if (status != 'approved' && status != 'flagged') return null;
    return DietReview(
      date: date,
      approved: status == 'approved',
      note: (raw['note'] as String?) ?? '',
      reviewer: (raw['by'] is Map ? (raw['by']['name'] as String?) : null) ?? 'Your nutritionist',
      at: DateTime.fromMillisecondsSinceEpoch(((raw['at'] as num?) ?? 0).toInt()),
    );
  }
}

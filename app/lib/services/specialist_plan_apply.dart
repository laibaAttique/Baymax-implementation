import '../models/plan.dart';
import '../models/specialist_plan.dart';

/// Puts a specialist's plan over the Baymax plan (Module 14, FR-5 / FR-10). Pure: no database, no screens.
///
/// * Diet: the calorie target and macros are replaced when the specialist set them; their foods to avoid and tips are added in front
///   of Baymax's own. The meal suggestions are left as they are (they were built for Baymax's target), and the plan says so.
/// * Workout: the specialist's weekly schedule replaces the generated week, with the usual warm-up and cool-down around each day.
/// * "Approved as is" changes nothing in the plan; it only shows that a specialist reviewed it.
///
/// Nothing here weakens a safety rule silently: a specialist's plan is labelled with who set it, and the member can switch back to
/// Baymax's plan at any time.
PersonalizedPlan applySpecialistPlans(
  PersonalizedPlan base,
  SpecialistPlans plans,
  PlanChoices choices, {
  required Exercise? Function(String id) exercise,
  required Exercise warmUp,
  required Exercise coolDown,
}) {
  var nutrition = base.nutrition;
  var week = base.week;

  final diet = plans.diet;
  if (diet != null && choices.specialistDiet && !diet.approvedAsIs) nutrition = _applyDiet(nutrition, diet);

  final workout = plans.workout;
  if (workout != null && choices.specialistWorkout && !workout.approvedAsIs) {
    final built = _buildWeek(workout, exercise, warmUp, coolDown);
    if (built != null) week = built;
  }
  if (identical(nutrition, base.nutrition) && identical(week, base.week)) return base;
  return PersonalizedPlan(
    category: base.category,
    intensity: base.intensity,
    variant: base.variant,
    week: week,
    restrictionNotes: base.restrictionNotes,
    nutrition: nutrition,
  );
}

NutritionPlan _applyDiet(NutritionPlan n, SpecialistDietPlan d) {
  final by = d.by.name;
  final target = d.targetKcal ?? n.targetKcal;
  return NutritionPlan(
    goalLabel: n.goalLabel,
    targetKcal: target,
    proteinG: d.hasMacros ? d.proteinG! : n.proteinG,
    carbsG: d.hasMacros ? d.carbsG! : n.carbsG,
    fatG: d.hasMacros ? d.fatG! : n.fatG,
    waterLitres: n.waterLitres,
    meals: n.meals,
    avoid: [...d.avoid.where((a) => !n.avoid.contains(a)), ...n.avoid],
    tips: [if (d.note.isNotEmpty) '$by: ${d.note}', for (final t in d.tips) '$by: $t', ...n.tips],
    tipPool: n.tipPool,
    calorieNote: d.targetKcal != null || d.hasMacros
        ? 'Target set by ${d.by.label}. The meal suggestions below were built for Baymax\'s own target of ${n.targetKcal} kcal, so use them as ideas rather than exact amounts.'
        : n.calorieNote,
  );
}

List<WorkoutDay?>? _buildWeek(SpecialistWorkoutPlan w, Exercise? Function(String) lookup, Exercise warmUp, Exercise coolDown) {
  PlannedExercise fixed(Exercise e) => PlannedExercise(exercise: e, sets: 1, reps: 0, seconds: e.baseSeconds, restSeconds: 0);
  final week = List<WorkoutDay?>.filled(7, null);
  var any = false;
  for (final d in w.schedule) {
    if (d.rest) continue;
    final items = <PlannedExercise>[];
    for (final it in d.items) {
      final e = lookup(it.exerciseId);
      if (e == null) continue; // an exercise this copy of the library does not have is skipped, not guessed
      final timed = e.timed;
      items.add(PlannedExercise(
        exercise: e,
        sets: it.sets,
        reps: timed ? 0 : (it.reps > 0 ? it.reps : e.baseReps),
        seconds: timed ? (it.seconds > 0 ? it.seconds : e.baseSeconds) : 0,
        restSeconds: timed && it.sets == 1 ? 0 : 45,
        reasons: ['Set by ${w.by.label}', if (it.note.isNotEmpty) it.note],
      ));
    }
    if (items.isEmpty) continue;
    final cardio = items.every((i) => i.exercise.group == 'cardio');
    week[d.day - 1] = WorkoutDay(
      name: 'Plan from ${w.by.name}',
      focus: w.note.isNotEmpty ? w.note : 'Set by your ${w.by.roleLabel.toLowerCase()}',
      exercises: [fixed(warmUp), ...items, fixed(coolDown)],
      kind: cardio ? 'Cardio' : 'Strength',
    );
    any = true;
  }
  return any ? week : null;
}

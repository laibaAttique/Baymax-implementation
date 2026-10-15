import '../models/food.dart';

/// Pure rules behind the Daily Summary screen (Module 8, FR-13; mockup M25). No Firebase: every rule is unit-tested.

/// Share of calories from protein, carbs and fat, as whole percentages that add up to exactly 100.
/// Protein and carbohydrate count 4 kcal per gram and fat 9 kcal per gram (Atwater factors).
class MacroShare {
  final int protein;
  final int carbs;
  final int fat;
  const MacroShare(this.protein, this.carbs, this.fat);

  bool get isEmpty => protein + carbs + fat == 0;

  /// Largest-remainder rounding so the three labels always sum to 100.
  factory MacroShare.fromGrams({required double protein, required double carbs, required double fat}) {
    final kcal = [protein * 4, carbs * 4, fat * 9];
    final total = kcal.fold(0.0, (s, v) => s + v);
    if (total <= 0) return const MacroShare(0, 0, 0);
    final exact = [for (final k in kcal) k * 100 / total];
    final floors = [for (final e in exact) e.floor()];
    var left = 100 - floors.fold(0, (s, v) => s + v);
    final order = List.generate(3, (i) => i)..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
    for (final i in order) {
      if (left <= 0) break;
      floors[i]++;
      left--;
    }
    return MacroShare(floors[0], floors[1], floors[2]);
  }
}

/// Calories logged in each meal slot.
Map<String, double> kcalByMeal(List<FoodEntry> entries) {
  const meals = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
  return {for (final m in meals) m: entries.where((e) => e.meal == m).fold(0.0, (s, e) => s + e.kcal)};
}

/// Net calories = consumed − burned. Negative means the day ended below what was eaten minus the workout (shown green); positive is shown amber.
int netKcal({required double consumed, required double burned}) => (consumed - burned).round();

/// The one-line message under the summary, worded for the user's goal (FR25.4). It never praises a very low intake: below 80% of the
/// resting energy (BMR) it asks the user to eat enough instead. The 80% line and the ±10% "on target" band are team choices.
String dailyVerdict({required String goal, required double consumed, required int target, required double bmr}) {
  if (consumed <= 0) return 'Nothing is logged for this day yet. Add your meals to see how the day went.';
  final diff = consumed - target;
  final within = diff.abs() <= target * 0.10;
  final lowIntake = bmr > 0 && consumed < bmr * 0.8;
  if (lowIntake) {
    return 'That is a very low intake for you. If you skipped meals or did not log them, add them; if not, eat enough to fuel your body.';
  }
  if (within) return 'You are right on your daily target. Nicely balanced.';
  if (diff < 0) {
    switch (goal) {
      case 'Lose Weight':
        return 'You are under your daily target by ${(-diff).round()} kcal. Great progress for your weight-loss goal.';
      case 'Gain Muscle':
        return 'You are ${(-diff).round()} kcal short of your target. To gain muscle you need to eat enough, so add a meal or snack.';
      default:
        return 'You are ${(-diff).round()} kcal under your target. A small snack would bring you back to maintenance.';
    }
  }
  switch (goal) {
    case 'Lose Weight':
      return 'You are ${diff.round()} kcal over your daily target. Keep your next meal light and you will be back on track.';
    case 'Gain Muscle':
      return 'You are ${diff.round()} kcal above your target, which supports muscle gain. Keep protein high.';
    default:
      return 'You are ${diff.round()} kcal over your target. One day does not change much; aim to balance it tomorrow.';
  }
}

import 'calorie_optimizer.dart';

/// A straight-line extrapolation of the user's OWN recent weigh-ins. It is not a prediction model (the project scope names a
/// Gradient Boosting forecaster for that, which is not built): it only says where the current trend leads if nothing changes.
class WeightProjection {
  final bool reliable;
  final String note;
  final double? currentKg; // value of the fitted line at the last weigh-in
  final double? kgPerWeek;
  final double? in30DaysKg;
  final double? weeksToTarget; // null when there is no target, the trend is flat, or it leads away from the target

  const WeightProjection({required this.reliable, required this.note, this.currentKg, this.kgPerWeek, this.in30DaysKg, this.weeksToTarget});
}

const projectionMinWeighIns = 4;
const projectionMinSpanDays = 14;
const projectionWindowDays = 28;

WeightProjection projectWeight({required List<WeightPoint> weights, required DateTime today, double? targetKg}) {
  final t = DateTime(today.year, today.month, today.day);
  final from = t.subtract(const Duration(days: projectionWindowDays - 1));
  final w = [for (final p in weights) if (!p.date.isBefore(from) && !p.date.isAfter(t)) p]..sort((a, b) => a.date.compareTo(b.date));
  if (w.length < projectionMinWeighIns) {
    return WeightProjection(reliable: false, note: 'Log your weight at least $projectionMinWeighIns times over $projectionMinSpanDays or more days to see a projection (so far ${w.length}).');
  }
  if (w.last.date.difference(w.first.date).inDays < projectionMinSpanDays) {
    return const WeightProjection(reliable: false, note: 'Your weigh-ins cover less than two weeks. Keep logging, so real change can be told apart from daily ups and downs.');
  }
  final fit = fitWeights(w);
  if (fit == null) return const WeightProjection(reliable: false, note: 'Not enough variation in the weigh-in dates yet.');
  final perWeek = fit.slopePerDay * 7;
  double? weeks;
  if (targetKg != null && perWeek.abs() > 0.05) {
    final toGo = targetKg - fit.lastFitKg;
    if (toGo * perWeek > 0) weeks = toGo / perWeek;
  }
  final flat = perWeek.abs() <= 0.05;
  return WeightProjection(
    reliable: true,
    note: flat
        ? 'Your weight has been steady over the last weeks.'
        : 'If the last ${w.last.date.difference(w.first.date).inDays} days continue unchanged, this is where you would be. Real progress is rarely a straight line.',
    currentKg: fit.lastFitKg,
    kgPerWeek: perWeek,
    in30DaysKg: fit.lastFitKg + fit.slopePerDay * 30,
    weeksToTarget: weeks,
  );
}

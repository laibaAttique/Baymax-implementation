/// Energy estimates from MET values (Module 4).
///
/// Baymax uses ONE method everywhere: the Compendium convention that 1 MET ≈ 1 kcal per kg of body weight per hour,
///
///   kcal ≈ MET × weight (kg) × active duration (hours)            ([kcalCompendium], used by the app)
///
/// The oxygen-based form, with 1 MET = 3.5 ml O2/kg/min and ≈ 5 kcal per litre of O2,
///
///   kcal ≈ MET × 3.5 × weight (kg) × duration (min) / 200         ([kcalOxygen])
///
/// gives a value 5% higher (3.5 × 60 / 200 = 1.05). It is provided for comparison only.
///
/// Both are approximate GROSS expenditure (resting energy included) for an average adult. Duration is ACTIVE time:
/// rest between sets is not counted, so a session's estimate is lower than "MET × total session time".
class MetCalculator {
  MetCalculator._();

  /// Null when there is no MET value (unmatched activity): nothing is estimated rather than guessed.
  static double? kcalCompendium({required double? met, required double weightKg, required Duration active}) {
    if (met == null || met <= 0 || weightKg <= 0 || active.isNegative) return null;
    return met * weightKg * active.inMilliseconds / Duration.millisecondsPerHour;
  }

  static double? kcalOxygen({required double? met, required double weightKg, required Duration active}) {
    if (met == null || met <= 0 || weightKg <= 0 || active.isNegative) return null;
    return met * 3.5 * weightKg * (active.inMilliseconds / Duration.millisecondsPerMinute) / 200;
  }
}

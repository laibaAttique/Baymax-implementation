import 'package:firebase_database/firebase_database.dart';
import '../models/health_profile.dart';
import 'realtime_db.dart';

/// What a member chose about their own nutrition plan (Module 9): which set of meals is shown ("Regenerate meals" moves [variant] on)
/// and, if they want, their own daily calorie target. Stored at `users/{uid}/mealPlan`.
class MealPlanPrefs {
  final int variant;

  /// The member's own daily target, or null to use the one Baymax works out.
  final int? customKcal;
  const MealPlanPrefs({this.variant = 0, this.customKcal});

  static const none = MealPlanPrefs();

  MealPlanPrefs copyWith({int? variant, int? customKcal, bool clearKcal = false}) =>
      MealPlanPrefs(variant: variant ?? this.variant, customKcal: clearKcal ? null : (customKcal ?? this.customKcal));

  Map<String, Object?> toJson() => {'variant': variant, if (customKcal != null) 'customKcal': customKcal, 'updatedAt': ServerValue.timestamp};

  static MealPlanPrefs fromJson(Object? raw) {
    if (raw is! Map) return none;
    final v = raw['variant'], k = raw['customKcal'];
    return MealPlanPrefs(variant: v is num ? v.toInt().clamp(0, 100000) : 0, customKcal: k is num && k >= minKcal && k <= maxKcal ? k.toInt() : null);
  }

  /// The limits the database rules also enforce.
  static const minKcal = 800;
  static const maxKcal = 6000;

  /// The calories a member may choose: not below the safe minimum for them (the larger of their BMR and 1,500 kcal for men or 1,200 for
  /// women, the same floor as the recommended target) and not more than 1,000 below or 500 above what keeps their weight steady, the
  /// same limits as the body forecast.
  static (int min, int max) range(HealthProfile p) {
    final floor = [p.bmr, p.gender.toLowerCase() == 'male' ? 1500.0 : 1200.0].reduce((a, b) => a > b ? a : b);
    final lo = [floor, p.tdee - 1000].reduce((a, b) => a > b ? a : b).ceil();
    final hi = (p.tdee + 500).floor();
    return (lo, hi < lo ? lo : hi);
  }

  /// Why [text] cannot be used as a daily target, or null when it is fine.
  static String? problem(String text, HealthProfile p) {
    final n = int.tryParse(text.trim());
    if (n == null) return 'Enter a whole number of calories.';
    final (lo, hi) = range(p);
    if (n < lo) return 'That is below the minimum of $lo kcal that is safe for you. Eating less is not recommended without a doctor.';
    if (n > hi) return 'That is more than $hi kcal, which is 500 above what keeps your weight steady.';
    return null;
  }
}

class MealPlanPrefsStore {
  MealPlanPrefsStore._();
  static final MealPlanPrefsStore instance = MealPlanPrefsStore._();

  Future<MealPlanPrefs> load() => RealtimeDb.guard(() async => MealPlanPrefs.fromJson(RealtimeDb.plain((await RealtimeDb.userRef('mealPlan').get()).value)));

  Future<void> save(MealPlanPrefs p) => RealtimeDb.guard(() => RealtimeDb.userRef('mealPlan').set(p.toJson()));
}

import '../models/specialist_plan.dart';
import 'realtime_db.dart';

/// Module 14: reads what specialists set for the signed-in member, and keeps the member's own choice between a specialist's plan and
/// Baymax's. Specialists write through the portal's server; the member can only read their plans and write the choice.
class SpecialistPlanService {
  SpecialistPlanService._();
  static final SpecialistPlanService instance = SpecialistPlanService._();

  Future<SpecialistPlans> load() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.db.ref('specialistPlans/${RealtimeDb.uid}').get();
      return snap.exists ? SpecialistPlans.fromJson(RealtimeDb.plain(snap.value)) : SpecialistPlans.none;
    });
  }

  Future<PlanChoices> loadChoices() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('planChoice').get();
      return snap.exists ? PlanChoices.fromJson(RealtimeDb.plain(snap.value)) : PlanChoices.defaults;
    });
  }

  Future<void> saveChoice({required bool diet, required bool useSpecialist}) {
    return RealtimeDb.guard(() => RealtimeDb.userRef('planChoice/${diet ? 'diet' : 'workout'}').set(useSpecialist ? 'specialist' : 'baymax'));
  }

  /// Verdicts on the member's food log for dates from [from] to [to] (yyyy-mm-dd, inclusive), keyed by date.
  Future<Map<String, DietReview>> loadReviews(String from, String to) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.db.ref('dietReviews/${RealtimeDb.uid}').orderByKey().startAt(from).endAt(to).get();
      if (!snap.exists) return <String, DietReview>{};
      final raw = RealtimeDb.plain(snap.value);
      if (raw is! Map) return <String, DietReview>{};
      return {
        for (final e in raw.entries)
          if (DietReview.fromJson(e.key.toString(), e.value) case final r?) e.key.toString(): r,
      };
    });
  }
}

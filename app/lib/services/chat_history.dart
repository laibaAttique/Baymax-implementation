import '../models/food.dart';
import '../models/plan.dart';
import 'calorie_optimizer.dart';
import 'food_log_service.dart';
import 'gamification.dart';
import 'progress_service.dart';
import 'user_session.dart';
import 'weight_service.dart';

/// What the chatbot knows about the user's own past, so it can answer from their data instead of generic advice.
///
/// Each part is null when it could not be read (offline, signed out) and empty/zero when it was read and there was nothing.
/// The chatbot says which of the two it is, so it never claims "you ate nothing" when it simply cannot see the log.
/// Everything stays on the phone: it is read from the user's own account and used to write the replies locally.
class ChatHistory {
  /// Logged meals for the last [foodDays] days (today included), keyed by `YYYY-MM-DD`.
  final Map<String, List<FoodEntry>>? entriesByDate;

  /// Workouts done, food logging, streaks, badges, weekly score, level and calories per day over the last 28 days.
  final ProgressSnapshot? progress;

  /// Weigh-ins over the last 28 days, oldest first.
  final List<WeightPoint>? weights;

  /// How the calorie target was worked out (formula or adjusted from the user's own logs).
  final CalorieEstimate? estimate;

  const ChatHistory({this.entriesByDate, this.progress, this.weights, this.estimate});

  static const none = ChatHistory();
  static const foodDays = 7;

  List<FoodEntry>? entriesOn(DateTime day) => entriesByDate?[FoodLogService.dateKey(day)];

  /// Reads the history from the user's account. Every part is loaded independently, so one failure leaves the others usable.
  static Future<ChatHistory> load(PersonalizedPlan? plan, {DateTime? today}) async {
    final t = Gamification.dateOnly(today ?? DateTime.now());

    Future<T?> attempt<T>(Future<T> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      attempt(() async {
        final days = [for (var i = 0; i < foodDays; i++) t.subtract(Duration(days: i))];
        final lists = await Future.wait([for (final d in days) FoodLogService.instance.forDate(FoodLogService.dateKey(d))]);
        return <String, List<FoodEntry>>{for (var i = 0; i < days.length; i++) FoodLogService.dateKey(days[i]): lists[i]};
      }),
      plan == null ? Future<ProgressSnapshot?>.value(null) : attempt(() => ProgressService.instance.load(plan, today: t)),
      attempt(() => WeightService.instance.range(
            FoodLogService.dateKey(t.subtract(const Duration(days: ProgressSnapshot.windowDays - 1))),
            FoodLogService.dateKey(t),
          )),
    ]);
    return ChatHistory(
      entriesByDate: results[0] as Map<String, List<FoodEntry>>?,
      progress: results[1] as ProgressSnapshot?,
      weights: results[2] as List<WeightPoint>?,
      estimate: UserSession.instance.calorieEstimate,
    );
  }
}

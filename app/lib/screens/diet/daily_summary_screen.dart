import 'package:flutter/material.dart';
import '../../models/food.dart';
import '../../services/activity_service.dart';
import '../../services/api_client.dart';
import '../../services/diet_summary.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';

class DailySummaryData {
  final DateTime date;
  final List<FoodEntry> entries;

  /// Calories burned by the workout the user marked as done that day (0 when none).
  final int burnedKcal;

  /// Calories logged on each of the 7 days ending on [date] (oldest first; null = nothing logged).
  final List<double?> weekKcal;
  final int targetKcal;
  final int proteinTarget;
  final int carbsTarget;
  final int fatTarget;
  final String goal;
  final double bmr;
  const DailySummaryData({
    required this.date,
    required this.entries,
    required this.burnedKcal,
    required this.weekKcal,
    required this.targetKcal,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    required this.goal,
    required this.bmr,
  });
}

/// Module 8, FR-13 (mockup M25): calories by meal against the daily target, consumed / burned / net, macro shares, a 7-day chart and
/// a verdict worded for the user's goal.
class DailySummaryScreen extends StatefulWidget {
  final DateTime date;
  final Future<DailySummaryData> Function(DateTime date)? loader;
  const DailySummaryScreen({Key? key, required this.date, this.loader}) : super(key: key);

  static Future<DailySummaryData> defaultLoader(DateTime date) async {
    final plan = UserSession.instance.plan;
    final profile = UserSession.instance.profile;
    if (plan == null || profile == null) throw const ApiException('Complete your health profile first.');
    final d = DateTime(date.year, date.month, date.day);
    final key = FoodLogService.dateKey(d);
    final from = d.subtract(const Duration(days: 6));
    final results = await Future.wait<Object?>([
      FoodLogService.instance.forDate(key),
      ActivityService.instance.range(key, key),
      FoodLogService.instance.kcalByDate(FoodLogService.dateKey(from), key),
    ]);
    final activity = results[1] as Map<String, ActivityEntry>;
    final byDay = results[2] as Map<String, double>;
    return DailySummaryData(
      date: d,
      entries: results[0] as List<FoodEntry>,
      burnedKcal: activity[key]?.kcal ?? 0,
      weekKcal: [for (var i = 0; i < 7; i++) byDay[FoodLogService.dateKey(from.add(Duration(days: i)))]],
      targetKcal: plan.nutrition.targetKcal,
      proteinTarget: plan.nutrition.proteinG,
      carbsTarget: plan.nutrition.carbsG,
      fatTarget: plan.nutrition.fatG,
      goal: profile.primaryGoal,
      bmr: profile.bmr,
    );
  }

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  DailySummaryData? _data;
  String? _error;
  bool _loading = true;
  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await (widget.loader ?? DailySummaryScreen.defaultLoader)(widget.date);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your daily summary.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _card(String title, Widget child, {String? sub, int index = 0}) => Reveal(
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35))),
                const SizedBox(height: 14),
                child,
              ]),
            ),
          ),
        ),
      );

  Widget _stat(String label, String value, Color color, IconData icon) => Expanded(
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4))),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Daily summary')),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? MessageState(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: _content(d!))),
    );
  }

  List<Widget> _content(DailySummaryData d) {
    final consumed = FoodLogService.totalKcal(d.entries);
    final net = netKcal(consumed: consumed, burned: d.burnedKcal.toDouble());
    final protein = d.entries.fold(0.0, (s, e) => s + e.protein);
    final carbs = d.entries.fold(0.0, (s, e) => s + e.carbs);
    final fat = d.entries.fold(0.0, (s, e) => s + e.fat);
    final share = MacroShare.fromGrams(protein: protein, carbs: carbs, fat: fat);
    final byMeal = kcalByMeal(d.entries);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${d.date.day} ${months[d.date.month - 1]}';
    final verdict = dailyVerdict(goal: d.goal, consumed: consumed, target: d.targetKcal, bmr: d.bmr);
    final netColor = net < 0 ? AppTheme.success : AppTheme.warning;

    return [
      Reveal(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)))),
      Reveal(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            _stat('Consumed', '${consumed.round()}', AppTheme.primary, Icons.restaurant_rounded),
            const SizedBox(width: 10),
            _stat('Burned', '${d.burnedKcal}', AppTheme.teal, Icons.local_fire_department_rounded),
            const SizedBox(width: 10),
            // negative net = green, positive = amber (mockup rule); 0 counts as balanced
            _stat('Net', '${net > 0 ? '+' : ''}$net', netColor, Icons.balance_rounded),
          ]),
        ),
      ),
      Reveal(
        index: 1,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            tint: AppTheme.tint(AppTheme.primary, 0.10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const IconWell(icon: Icons.insights_rounded, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(verdict, style: const TextStyle(fontSize: 14, height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
      _card(
        'Calories by meal',
        BarChart(
          target: d.targetKcal.toDouble(),
          barColor: AppTheme.primary,
          bars: [for (final m in byMeal.entries) BarDatum(m.key.substring(0, 1), m.value, '${m.key}: ${m.value.round()} kilocalories')],
        ),
        sub: 'Dashed line: your daily target of ${d.targetKcal} kcal. B = Breakfast, L = Lunch, D = Dinner, S = Snack.',
        index: 2,
      ),
      _card(
        'Macronutrients',
        share.isEmpty
            ? const Text('Log food to see your protein, carbs and fat split.', style: TextStyle(color: AppTheme.textSecondary))
            : Row(children: [
                DonutChart(
                  semanticLabel: 'Protein ${share.protein} percent, carbs ${share.carbs} percent, fat ${share.fat} percent',
                  slices: [DonutSlice('Protein', protein * 4, AppTheme.macroProtein), DonutSlice('Carbs', carbs * 4, AppTheme.macroCarbs), DonutSlice('Fat', fat * 9, AppTheme.macroFat)],
                  center: Text('${consumed.round()}\nkcal', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.15, color: AppTheme.textPrimary)),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(children: [
                    _legend('Protein', '${share.protein}%', '${protein.round()} g', AppTheme.macroProtein),
                    _legend('Carbs', '${share.carbs}%', '${carbs.round()} g', AppTheme.macroCarbs),
                    _legend('Fat', '${share.fat}%', '${fat.round()} g', AppTheme.macroFat),
                  ]),
                ),
              ]),
        sub: 'Share of calories (protein and carbs 4 kcal per gram, fat 9 kcal per gram).',
        index: 3,
      ),
      _card(
        'Last 7 days',
        BarChart(
          target: d.targetKcal.toDouble(),
          bars: [
            for (var i = 0; i < 7; i++)
              () {
                final day = d.date.subtract(Duration(days: 6 - i));
                final v = d.weekKcal[i];
                return BarDatum(_dayLetters[day.weekday - 1], v ?? 0, '${_dayLetters[day.weekday - 1]}: ${v == null ? 'nothing logged' : '${v.round()} kilocalories'}');
              }(),
          ],
        ),
        sub: 'Dashed line: your daily target. Days with no bar have nothing logged.',
        index: 4,
      ),
    ];
  }

  Widget _legend(String name, String pct, String grams, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 13.5))),
          const SizedBox(width: 6),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('$pct  ·  $grams', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textSecondary, fontSize: 12.5)))),
        ]),
      );
}

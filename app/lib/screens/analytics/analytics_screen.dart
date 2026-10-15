import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/calorie_optimizer.dart';
import '../../services/food_log_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';
import '../nutrition/calorie_target_screen.dart';
import '../community/community_screen.dart';

class AnalyticsData {
  final ProgressSnapshot progress;
  final List<WeightPoint> weights;
  const AnalyticsData(this.progress, this.weights);
}

/// Module 15 (part): charts built from what the app already records. Weight trend, calories against target with a moving average,
/// and the weekly fitness score. The injury-risk trend (FR-5) needs Module 9 and is not available.
class AnalyticsScreen extends StatefulWidget {
  final Future<AnalyticsData> Function()? loader;
  const AnalyticsScreen({Key? key, this.loader}) : super(key: key);

  static Future<AnalyticsData> defaultLoader() async {
    final plan = UserSession.instance.plan;
    if (plan == null) throw const ApiException('Complete your health profile to see your analytics.');
    final today = DateTime.now();
    final progress = await ProgressService.instance.load(plan, today: today);
    final from = FoodLogService.dateKey(today.subtract(const Duration(days: ProgressSnapshot.windowDays - 1)));
    final weights = await WeightService.instance.range(from, FoodLogService.dateKey(today));
    return AnalyticsData(progress, weights);
  }

  /// Average of the logged values in a window of [n] days ending at each index (null when none logged).
  static List<double?> movingAverage(List<double?> values, {int n = 3}) {
    return [
      for (var i = 0; i < values.length; i++)
        () {
          final window = [for (var j = (i - n + 1).clamp(0, i); j <= i; j++) if (values[j] != null) values[j]!];
          return window.isEmpty ? null : window.reduce((a, b) => a + b) / window.length;
        }()
    ];
  }

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsData? _data;
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
      final d = await (widget.loader ?? AnalyticsScreen.defaultLoader)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your analytics.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _tile(IconData icon, String value, String label) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        radius: AppTheme.rLarge,
        child: Row(children: [
          IconWell(icon: icon, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5))),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, height: 1.2)),
            ]),
          ),
        ]),
      );

  Widget _section(String title, String? sub, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35))),
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: GlassCard(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off_rounded, size: 40, color: AppTheme.primary),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        GlowButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _load),
                      ]),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
                    children: _content(d!),
                  ),
                ),
    );
  }

  List<Widget> _content(AnalyticsData d) {
    final p = d.progress;
    final last7 = p.days.sublist(p.days.length - 7);
    final kcal = [for (final day in last7) day.kcal];
    final logged = kcal.whereType<double>().toList();
    final avg = logged.isEmpty ? null : logged.reduce((a, b) => a + b) / logged.length;
    final target = last7.last.targetKcal?.toDouble();
    final weeks = p.weeks.length > 4 ? p.weeks.sublist(p.weeks.length - 4) : p.weeks;
    return [
      Reveal(
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _tile(Icons.bolt_rounded, '${p.week.total.round()}', 'Score this week')),
                const SizedBox(width: 10),
                Expanded(child: _tile(Icons.fitness_center_rounded, '${p.week.workoutsDone}/${p.week.workoutsPlanned}', 'Workouts done')),
              ]),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _tile(Icons.local_fire_department_rounded, avg == null ? '—' : '${avg.round()}', 'Avg kcal / day')),
                const SizedBox(width: 10),
                Expanded(child: _tile(Icons.whatshot_rounded, '${p.workoutStreak}', 'Workout streak')),
              ]),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _section(
        'Calories vs your target',
        'Last 7 days${target == null ? '' : ' · dashed line = ${target.round()} kcal target'} · dark line = 3-day average',
        logged.isEmpty
            ? const Text('Log your meals to see this chart.', style: TextStyle(color: AppTheme.textSecondary))
            : BarChart(
                target: target,
                movingAverage: AnalyticsScreen.movingAverage(kcal),
                bars: [
                  for (final day in last7)
                    BarDatum(_dayLetters[day.date.weekday - 1], day.kcal ?? 0, '${_dayLetters[day.date.weekday - 1]}: ${day.kcal == null ? 'nothing logged' : '${day.kcal!.round()} kilocalories'}'),
                ],
              ),
      ),
      _section(
        'Weekly fitness score',
        'Last ${weeks.length} week${weeks.length == 1 ? '' : 's'} · out of 100',
        weeks.isEmpty
            ? const Text('Complete workouts and log meals to build your score.', style: TextStyle(color: AppTheme.textSecondary))
            : BarChart(
                bars: [
                  for (var i = 0; i < weeks.length; i++)
                    BarDatum(i == weeks.length - 1 ? 'Now' : 'W-${weeks.length - 1 - i}', weeks[i].total, '${weeks[i].total.round()} out of 100'),
                ],
              ),
      ),
      _section(
        'Weight trend',
        d.weights.length >= 2 ? 'Dots = weigh-ins · line = smoothed trend' : null,
        d.weights.length >= 2
            ? SizedBox(height: 130, width: double.infinity, child: WeightTrendChart(points: d.weights))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Log your weight at least twice to see your trend.', style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                GlowButton(
                  label: 'Log my weight',
                  icon: Icons.monitor_weight_rounded,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalorieTargetScreen())),
                ),
              ]),
      ),
      GlassCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen())),
        child: const Row(children: [
          IconWell(icon: Icons.emoji_events_rounded, color: AppTheme.warning, size: 40),
          SizedBox(width: 14),
          Expanded(child: Text('Badges, level and leaderboard', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary))),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('The injury-risk trend needs the injury-risk module, which is not part of this version.', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ),
    ];
  }
}

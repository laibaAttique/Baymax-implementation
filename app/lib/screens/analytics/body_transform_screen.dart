import 'package:flutter/material.dart';
import '../../models/health_profile.dart';
import '../../services/api_client.dart';
import '../../services/calorie_optimizer.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_projection.dart';
import '../../services/weight_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/health_calc.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';
import '../nutrition/calorie_target_screen.dart';

class BodyTransformData {
  final WeightProjection projection;
  final List<WeightPoint> weights;
  final double? targetKg;
  final double? profileKg;
  const BodyTransformData(this.projection, this.weights, this.targetKg, this.profileKg);
}

/// Where the user's own weight trend is heading. A straight-line extrapolation, clearly labelled: it is not the
/// body-transformation forecasting model named in the project scope (Module 10), which is not built.
class BodyTransformScreen extends StatefulWidget {
  final Future<BodyTransformData> Function()? loader;
  const BodyTransformScreen({Key? key, this.loader}) : super(key: key);

  static Future<BodyTransformData> defaultLoader() async {
    final HealthProfile? p = UserSession.instance.profile;
    if (p == null) throw const ApiException('Complete your health profile first.');
    final today = DateTime.now();
    final from = FoodLogService.dateKey(today.subtract(const Duration(days: projectionWindowDays - 1)));
    final weights = await WeightService.instance.range(from, FoodLogService.dateKey(today));
    final target = p.targetWeightValue > 0 ? HealthCalc.toKg(p.targetWeightValue, p.targetWeightUnit) : null;
    return BodyTransformData(projectWeight(weights: weights, today: today, targetKg: target), weights, target, p.weightKg);
  }

  @override
  State<BodyTransformScreen> createState() => _BodyTransformScreenState();
}

class _BodyTransformScreenState extends State<BodyTransformScreen> {
  BodyTransformData? _data;
  String? _error;
  bool _loading = true;

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
      final d = await (widget.loader ?? BodyTransformScreen.defaultLoader)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your weight trend.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _stat(String value, String label) => Expanded(
        child: GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(children: [
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: -0.4))),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Body transformation')),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? MessageState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    if (d!.projection.reliable) ...[
                      Row(children: [
                        _stat('${d.projection.currentKg!.toStringAsFixed(1)} kg', 'Trend weight now'),
                        _stat('${d.projection.kgPerWeek! >= 0 ? '+' : ''}${d.projection.kgPerWeek!.toStringAsFixed(2)} kg', 'Change per week'),
                        _stat('${d.projection.in30DaysKg!.toStringAsFixed(1)} kg', 'In 30 days at this pace'),
                      ]),
                      const SizedBox(height: 14),
                    ],
                    GlassCard(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Your trend', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text(d.projection.note, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
                        if (d.weights.length >= 2) ...[
                          const SizedBox(height: 14),
                          SizedBox(height: 140, width: double.infinity, child: WeightTrendChart(points: d.weights, targetKg: d.targetKg)),
                          if (d.targetKg != null)
                            Text('Dashed line: your target of ${d.targetKg!.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                        if (d.projection.reliable && d.targetKg != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              d.projection.weeksToTarget == null
                                  ? 'At this pace you are not moving toward your target of ${d.targetKg!.toStringAsFixed(1)} kg.'
                                  : (d.projection.weeksToTarget! > 52
                                      ? 'At this pace your target is more than a year away.'
                                      : 'At this pace you would reach ${d.targetKg!.toStringAsFixed(1)} kg in about ${d.projection.weeksToTarget!.ceil()} weeks.'),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                            ),
                          ),
                      ]),
                    ),
                    GlowButton(
                      label: 'Log today\'s weight',
                      icon: Icons.monitor_weight_rounded,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalorieTargetScreen())).then((_) => _load()),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'This is a straight line drawn through your own recent weigh-ins, not a prediction model. Weight moves up and down with water, food and sleep. '
                      'The forecasting model named in the project scope is not part of this version. This is decision support, not medical advice.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ],
                ),
    );
  }
}

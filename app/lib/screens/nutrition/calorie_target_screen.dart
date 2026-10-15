import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/calorie_optimizer.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';

class CalorieTargetData {
  final CalorieEstimate? estimate;
  final List<WeightPoint> weights;
  final int targetKcal;
  final int formulaKcal;
  const CalorieTargetData({required this.estimate, required this.weights, required this.targetKcal, required this.formulaKcal});
}

/// Module 3, FR-4: shows how the calorie target is worked out and lets the user log their weight so it can be personalised.
class CalorieTargetScreen extends StatefulWidget {
  final Future<CalorieTargetData> Function()? loader;
  final Future<void> Function(double kg)? onSave;
  const CalorieTargetScreen({Key? key, this.loader, this.onSave}) : super(key: key);

  static Future<CalorieTargetData> defaultLoader() async {
    final s = UserSession.instance;
    final p = s.profile, plan = s.plan;
    if (p == null || plan == null) throw const ApiException('Complete your health profile first.');
    final today = DateTime.now();
    final from = FoodLogService.dateKey(today.subtract(const Duration(days: CalorieOptimizerRules.windowDays - 1)));
    final weights = await WeightService.instance.range(from, FoodLogService.dateKey(today));
    if (s.calorieEstimate == null) await s.refreshCalorieEstimate();
    return CalorieTargetData(estimate: s.calorieEstimate, weights: weights, targetKcal: s.plan?.nutrition.targetKcal ?? plan.nutrition.targetKcal, formulaKcal: p.dailyCalorieTarget);
  }

  @override
  State<CalorieTargetScreen> createState() => _CalorieTargetScreenState();
}

class _CalorieTargetScreenState extends State<CalorieTargetScreen> {
  CalorieTargetData? _data;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  final _kg = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await (widget.loader ?? CalorieTargetScreen.defaultLoader)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your calorie target.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final kg = double.tryParse(_kg.text.trim().replaceAll(',', '.'));
    if (kg == null || kg < WeightService.minKg || kg > WeightService.maxKg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter your weight in kg, between ${WeightService.minKg.round()} and ${WeightService.maxKg.round()}.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await (widget.onSave ?? UserSession.instance.logWeight)(kg);
      _kg.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight saved.')));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card({required Widget child, int index = 0}) => Reveal(
        index: index,
        child: Padding(padding: const EdgeInsets.only(bottom: 12), child: SizedBox(width: double.infinity, child: GlassCard(child: child))),
      );

  String _badge(CalorieEstimate? e) {
    switch (e?.status) {
      case EstimateStatus.adapted:
        final a = e!.adjustment.round();
        return 'Personalised to you (${a >= 0 ? '+' : ''}$a kcal a day vs the formula)';
      case EstimateStatus.confirmsFormula:
        return 'Formula, confirmed by your logs';
      case EstimateStatus.disabled:
        return 'Formula (automatic adjustment is off for you)';
      default:
        return 'Formula (not enough of your data yet)';
    }
  }

  Widget _step(String label, bool done, String detail) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: done ? AppTheme.success : AppTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$label  ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 13.5)),
                TextSpan(text: detail, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
              ])),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final e = d?.estimate;
    return Scaffold(
      appBar: AppBar(title: const Text('Your calorie target')),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? MessageState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DAILY TARGET', style: AppTheme.overline),
                            const SizedBox(height: 2),
                            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('${d!.targetKcal}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: -1.5, height: 1.1)),
                                const SizedBox(width: 6),
                                const Text('kcal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                              ],
                            )),
                            const SizedBox(height: 10),
                            InfoChip(_badge(e), icon: e?.status == EstimateStatus.adapted ? Icons.auto_awesome_rounded : Icons.functions_rounded),
                            if (e != null && d.formulaKcal != d.targetKcal)
                              Text('The formula alone would give ${d.formulaKcal} kcal.', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      _card(
                        index: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('How it is worked out', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                            const SizedBox(height: 6),
                            Text(e?.reason ?? 'Your target comes from the Mifflin–St Jeor formula and your activity level.',
                                style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary)),
                            if (e != null && e.status != EstimateStatus.disabled) ...[
                              const SizedBox(height: 6),
                              _step('Weigh-ins', e.weighIns >= CalorieOptimizerRules.minWeighIns, '${e.weighIns} of ${CalorieOptimizerRules.minWeighIns} needed, over at least ${CalorieOptimizerRules.minSpanDays} days'),
                              _step('Fully logged days', e.completeDays >= CalorieOptimizerRules.minCompleteDays, '${e.completeDays} of ${CalorieOptimizerRules.minCompleteDays} needed (log everything you eat)'),
                              if (e.trendKgPerWeek != null)
                                _step('Weight trend', true, '${e.trendKgPerWeek! >= 0 ? '+' : ''}${e.trendKgPerWeek!.toStringAsFixed(2)} kg per week'),
                            ],
                          ],
                        ),
                      ),
                      _card(
                        index: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Log today\'s weight', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                            const SizedBox(height: 4),
                            const Text('Weigh yourself at a similar time each day, ideally in the morning. Two or three times a week is enough.',
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _kg,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'Weight (kg)'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(96, 52)), onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
                              ],
                            ),
                            if (d.weights.length >= 2) ...[
                              const SizedBox(height: 14),
                              SizedBox(height: 120, width: double.infinity, child: WeightTrendChart(points: d.weights)),
                              const SizedBox(height: 4),
                              const Text('Dots: your weigh-ins. Line: your smoothed trend.', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                      const Text(
                        'This is an adaptive estimate based on energy balance (roughly 7,700 kcal per kg of body weight change), mixed with the formula according to how reliable your data is. '
                        'It never counts for more than 70% of the result, can raise the formula estimate by at most 15% and lower it by at most 10%, and is switched off for under-18s and for anyone who reported heart disease or diabetes. '
                        'It is not the Gradient Boosting model named in the project scope, which needs measured energy-expenditure data we do not have yet. It is decision support, not medical advice.',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45),
                      ),
                    ],
                  ),
                ),
    );
  }
}

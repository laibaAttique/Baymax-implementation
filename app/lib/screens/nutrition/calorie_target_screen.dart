import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/calorie_optimizer.dart';
import '../../services/food_log_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_service.dart';
import '../../theme/app_theme.dart';

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

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: child,
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
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(done ? '✅' : '⬜', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$label  ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13)),
                TextSpan(text: detail, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
      appBar: AppBar(title: const Text('Your calorie target', style: TextStyle(fontSize: 16))),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d!.targetKcal} kcal', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            const Text('daily target', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            const SizedBox(height: 8),
                            Text(_badge(e), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            if (e != null && d.formulaKcal != d.targetKcal)
                              Text('The formula alone would give ${d.formulaKcal} kcal.', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('How it is worked out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Log today\'s weight', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
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
                                ElevatedButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
                              ],
                            ),
                            if (d.weights.length >= 2) ...[
                              const SizedBox(height: 14),
                              SizedBox(height: 110, width: double.infinity, child: CustomPaint(painter: _WeightChart(d.weights))),
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
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
    );
  }
}

class _WeightChart extends CustomPainter {
  final List<WeightPoint> pts;
  _WeightChart(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final trend = trendWeights(pts);
    final all = [...pts.map((p) => p.kg), ...trend.map((p) => p.kg)];
    var lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    final t0 = pts.first.date.millisecondsSinceEpoch.toDouble();
    final span = (pts.last.date.millisecondsSinceEpoch - pts.first.date.millisecondsSinceEpoch).toDouble().clamp(1, double.infinity);
    Offset at(WeightPoint p) => Offset(
          8 + (size.width - 16) * (p.date.millisecondsSinceEpoch - t0) / span,
          size.height - 8 - (size.height - 16) * (p.kg - lo) / (hi - lo),
        );
    final line = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(trend.first).dx, at(trend.first).dy);
    for (final p in trend.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = AppTheme.textSecondary;
    for (final p in pts) {
      canvas.drawCircle(at(p), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChart old) => old.pts != pts;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/health_profile.dart';
import '../../services/body_forecast.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';

/// What the forecast starts from: the person's body, maintenance energy and usual activity, and the plan the app already gave them.
class ForecastSeed {
  final ForecastInputs base;
  final String goalLabel;
  const ForecastSeed(this.base, this.goalLabel);

  /// [latestKg] is the most recent weigh-in; the profile weight is used when there is none.
  factory ForecastSeed.fromProfile(HealthProfile p, {double? latestKg}) {
    final tdee = p.tdee;
    final planned = (tdee - p.dailyCalorieTarget);
    final target = p.targetWeightValue > 0 ? p.targetWeightKg : null;
    return ForecastSeed(
      ForecastInputs(
        weightKg: latestKg ?? p.weightKg,
        heightCm: p.heightCm,
        age: p.ageForCalc,
        isMale: p.gender.toLowerCase() == 'male',
        tdee: tdee,
        bmr: p.bmr,
        deficitKcal: planned.roundToDouble(),
        workoutsPerWeek: p.workoutFrequency.clamp(2, 5),
        usualWorkoutsPerWeek: p.workoutFrequency,
        targetKg: target,
      ),
      p.primaryGoal,
    );
  }
}

String _kg(double v) => v.toStringAsFixed(1);
String _signed(double v, [int digits = 1]) => '${v > 0.04 ? '+' : v < -0.04 ? '-' : ''}${v.abs().toStringAsFixed(digits)}';

String _inDays(int days) {
  if (days <= 0) return 'today';
  if (days < 14) return 'in $days days';
  if (days < 120) return 'in about ${(days / 7).round()} weeks';
  if (days <= 365) return 'in about ${(days / 30.4).round()} months';
  return 'in more than a year';
}

/// FR30: the inputs of the forecast. A calorie deficit (or surplus), workouts a week and, if the person wants, a goal in words.
class TransformInputScreen extends StatefulWidget {
  final ForecastSeed seed;
  const TransformInputScreen({Key? key, required this.seed}) : super(key: key);

  @override
  State<TransformInputScreen> createState() => _TransformInputScreenState();
}

class _TransformInputScreenState extends State<TransformInputScreen> {
  late bool _eatLess = widget.seed.base.deficitKcal >= 0;
  late final _kcal = TextEditingController(text: widget.seed.base.deficitKcal.abs().round().toString());
  late int _workouts = widget.seed.base.workoutsPerWeek;
  final _goal = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _kcal.dispose();
    _goal.dispose();
    super.dispose();
  }

  int get _max => (_eatLess ? BodyForecaster.maxDeficit : BodyForecaster.maxSurplus).round();

  void _predict() {
    final n = int.tryParse(_kcal.text.trim());
    if (n == null || n < 0 || n > _max) {
      setState(() => _problem = 'Enter a whole number of calories from 0 to $_max.');
      return;
    }
    setState(() => _problem = null);
    var base = widget.seed.base.copyWith(deficitKcal: (_eatLess ? n : -n).toDouble(), workoutsPerWeek: _workouts);
    final goalTarget = BodyForecaster.targetFromGoalText(_goal.text, base.weightKg);
    if (goalTarget != null) base = base.copyWith(targetKg: goalTarget);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TransformResultScreen(inputs: base, goalLabel: widget.seed.goalLabel, goalText: _goal.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.seed.base;
    return Scaffold(
      appBar: AppBar(title: const Text('Predict my results')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
        children: [
          GlassCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Starting from ${_kg(b.weightKg)} kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('Your body needs about ${b.tdee.round()} calories a day to stay where you are. Choose how far below (or above) that you plan to eat.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            ]),
          ),
          const SectionHeader('Daily calorie change', padding: EdgeInsets.fromLTRB(2, 6, 0, 8)),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Eat less (deficit)'), selected: _eatLess, onSelected: (_) => setState(() => _eatLess = true)),
            ChoiceChip(label: const Text('Eat more (surplus)'), selected: !_eatLess, onSelected: (_) => setState(() => _eatLess = false)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _kcal,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(labelText: _eatLess ? 'Calorie deficit (kcal a day)' : 'Calorie surplus (kcal a day)', errorText: _problem),
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
          ),
          const SectionHeader('Workouts a week', padding: EdgeInsets.fromLTRB(2, 18, 0, 8)),
          Wrap(spacing: 8, children: [
            for (final n in const [2, 3, 4, 5]) ChoiceChip(label: Text('$n days'), selected: _workouts == n, onSelected: (_) => setState(() => _workouts = n)),
          ]),
          const SectionHeader('Your goal (optional)', padding: EdgeInsets.fromLTRB(2, 18, 0, 8)),
          TextField(
            controller: _goal,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'For example: Lose 7 kg', counterText: ''),
          ),
          const SizedBox(height: 6),
          const Text('Higher consistency leads to better predictions: the forecast assumes you follow the plan every day.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
          const SizedBox(height: 18),
          GlowButton(label: 'Predict My Results', icon: Icons.auto_graph_rounded, onPressed: _predict),
        ],
      ),
    );
  }
}

/// FR31: the forecast. Summary cards you can change, the 30-day result, the chart with goal line and milestones, and the method.
class TransformResultScreen extends StatefulWidget {
  final ForecastInputs inputs;
  final String goalLabel;
  final String goalText;
  const TransformResultScreen({Key? key, required this.inputs, this.goalLabel = '', this.goalText = ''}) : super(key: key);

  @override
  State<TransformResultScreen> createState() => _TransformResultScreenState();
}

class _TransformResultScreenState extends State<TransformResultScreen> {
  late ForecastInputs _in = widget.inputs;
  bool _adjust = false;

  BodyForecast get _f => BodyForecaster.forecast(_in);

  Widget _summaryCard(String value, String label) => Expanded(
        child: GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          onTap: () => setState(() => _adjust = true),
          semanticLabel: '$label $value, tap to change',
          child: Column(children: [
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.primary))),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ]),
        ),
      );

  Widget _result(String value, String label, {String? sub}) => Expanded(
        child: GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(children: [
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: -0.4))),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
          ]),
        ),
      );

  String _share(BodyForecast f) {
    final i = f.inputs;
    final goal = _goalSentence(f);
    return 'My Baymax 30-day forecast (an estimate, not medical advice)\n'
        'Start: ${_kg(i.weightKg)} kg. Plan: ${i.deficitKcal >= 0 ? '${i.deficitKcal.round()} kcal a day less' : '${(-i.deficitKcal).round()} kcal a day more'}, ${i.workoutsPerWeek} workouts a week.\n'
        'In 30 days: about ${_kg(f.weightIn30)} kg (${_signed(f.changeIn30)} kg), body fat ${_signed(f.fatChange30)} kg.\n'
        '${goal ?? ''}';
  }

  String? _goalSentence(BodyForecast f) {
    final t = f.inputs.targetKg;
    if (t == null) return null;
    if (f.targetMovesAway) return 'At this plan your weight moves away from ${_kg(t)} kg.';
    if (f.daysToTarget != null) return 'Goal ${_kg(t)} kg: ${_inDays(f.daysToTarget!)}.';
    if ((t - f.inputs.weightKg).abs() < 0.1) return 'You are at your goal weight.';
    return 'At this plan your weight levels off near ${_kg(f.plateauKg)} kg, short of ${_kg(t)} kg.';
  }

  Future<void> _copy(BodyForecast f) async {
    await Clipboard.setData(ClipboardData(text: _share(f)));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forecast copied. Paste it into a message to share it.')));
  }

  Widget _adjustPanel() {
    final eatLess = _in.deficitKcal >= 0;
    final amount = _in.deficitKcal.abs().round();
    final max = (eatLess ? BodyForecaster.maxDeficit : BodyForecaster.maxSurplus).round();
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ChoiceChip(label: const Text('Eat less'), selected: eatLess, onSelected: (_) => setState(() => _in = _in.copyWith(deficitKcal: amount.clamp(0, 1000).toDouble()))),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Eat more'), selected: !eatLess, onSelected: (_) => setState(() => _in = _in.copyWith(deficitKcal: -amount.clamp(0, 500).toDouble()))),
        ]),
        const SizedBox(height: 8),
        Text('${eatLess ? 'Deficit' : 'Surplus'}: $amount kcal a day', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        Slider(
          value: amount.clamp(0, max).toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max ~/ 50,
          label: '$amount kcal',
          onChanged: (v) => setState(() => _in = _in.copyWith(deficitKcal: eatLess ? v : -v)),
        ),
        Text('Workouts a week: ${_in.workoutsPerWeek}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        Wrap(spacing: 8, children: [
          for (final n in const [2, 3, 4, 5]) ChoiceChip(label: Text('$n'), selected: _in.workoutsPerWeek == n, onSelected: (_) => setState(() => _in = _in.copyWith(workoutsPerWeek: n))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final i = f.inputs;
    final goal = _goalSentence(f);
    return Scaffold(
      appBar: AppBar(title: const Text('Your forecast')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, AppTheme.navSpace(context)),
        children: [
          Row(children: [
            _summaryCard('${_kg(i.weightKg)} kg', 'Current weight'),
            _summaryCard('${i.deficitKcal >= 0 ? '-' : '+'}${i.deficitKcal.abs().round()} kcal', i.deficitKcal >= 0 ? 'Daily deficit' : 'Daily surplus'),
            _summaryCard('${i.workoutsPerWeek} / week', 'Workouts'),
          ]),
          const SizedBox(height: 8),
          GlowButton(label: _adjust ? 'Hide adjust inputs' : 'Adjust inputs', icon: Icons.tune_rounded, onPressed: () => setState(() => _adjust = !_adjust)),
          const SizedBox(height: 10),
          if (_adjust) _adjustPanel(),
          Row(children: [
            _result('${_kg(f.weightIn30)} kg', 'Weight in 30 days', sub: '${_signed(f.changeIn30)} kg'),
            _result('${_signed(f.fatChange30)} kg', 'Body fat', sub: '${f.bodyFatPct0.toStringAsFixed(0)}% to ${f.bodyFatPct30.toStringAsFixed(0)}% (estimate)'),
          ]),
          const SizedBox(height: 12),
          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weight over 30 days', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              SizedBox(height: 190, width: double.infinity, child: ForecastChart(forecast: f)),
              const SizedBox(height: 8),
              const Text('Solid line: if you follow the plan every day. Grey line: if you manage about 60% of it. Dots: milestones. Dashed green line: your goal.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4)),
              if (goal != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(goal, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary))),
              if (widget.goalText.isNotEmpty && BodyForecaster.targetFromGoalText(widget.goalText, i.weightKg) == null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Your goal "${widget.goalText}" was kept as a note: the forecast only reads goals such as "Lose 7 kg".', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
            ]),
          ),
          if (f.milestones.isNotEmpty)
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Milestones', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
                for (final m in f.milestones)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      const Icon(Icons.flag_rounded, size: 18, color: AppTheme.teal),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                      const SizedBox(width: 8),
                      Flexible(child: Text('${_kg(m.kg)} kg, ${_inDays(m.day)}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
                    ]),
                  ),
              ]),
            ),
          if (f.notes.isNotEmpty)
            GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final n in f.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                      const SizedBox(width: 10),
                      Expanded(child: Text(n, style: const TextStyle(height: 1.4, color: AppTheme.textPrimary, fontSize: 13))),
                    ]),
                  ),
              ]),
            ),
          GlowButton(label: 'Copy My Forecast', icon: Icons.ios_share_rounded, onPressed: () => _copy(f)),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('How this is worked out', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text(
                'Method: an energy-balance model, not a trained or machine-learning model. Each day your intake (maintenance minus your deficit, never below the safe minimum) is compared with what your body burns, which falls as you get lighter (about 24 kcal a day for each kg lost, Hall et al., Lancet 2011). '
                'The difference becomes fat and lean mass in the proportions Forbes described (Hall, Br J Nutr 2007), starting from body fat estimated from your BMI, age and sex (Deurenberg et al., Br J Nutr 1991, accurate to about 4 percentage points).\n\n'
                'Not included: water and glycogen (the first week often drops more), how closely you follow the plan, medicines and medical conditions. This is decision support, not medical advice: talk to a doctor before a large change in how you eat, especially with a health condition.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.45),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

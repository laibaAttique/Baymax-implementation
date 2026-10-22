import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/activity_reports.dart';
import '../../services/activity_service.dart';
import '../../services/api_client.dart';
import '../../services/calorie_optimizer.dart';
import '../../services/food_log_service.dart';
import '../../services/gamification.dart';
import '../../services/measurement_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/weight_service.dart';
import '../../services/workout_session/workout_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/health_calc.dart';
import '../../widgets/charts.dart';
import '../../widgets/glass.dart';
import '../nutrition/calorie_target_screen.dart';

/// Everything the Weekly Report and the Workout History read, loaded once.
class ActivityInputs {
  final DateTime today;
  final Map<String, ActivityEntry> activity;
  final Map<String, double> kcalByDate;
  final List<WorkoutLogEntry> sessions;
  final List<WeightPoint> weights;
  final Set<int> plannedWeekdays;
  final int? targetKcal;
  const ActivityInputs({required this.today, required this.activity, required this.kcalByDate, required this.sessions, required this.weights, required this.plannedWeekdays, required this.targetKcal});

  static const loadDays = 90;

  static Future<ActivityInputs> load() async {
    final plan = UserSession.instance.plan;
    if (plan == null) throw const ApiException('Complete your health profile to see your reports.');
    final today = Gamification.dateOnly(DateTime.now());
    final from = today.subtract(const Duration(days: loadDays - 1));
    final fk = FoodLogService.dateKey(from), tk = FoodLogService.dateKey(today);
    final results = await Future.wait([
      ActivityService.instance.range(fk, tk),
      FoodLogService.instance.kcalByDate(fk, tk),
      FirebaseWorkoutLog.instance.since(from).catchError((_) => <WorkoutLogEntry>[]),
      WeightService.instance.range(fk, tk),
    ]);
    return ActivityInputs(
      today: today,
      activity: results[0] as Map<String, ActivityEntry>,
      kcalByDate: results[1] as Map<String, double>,
      sessions: results[2] as List<WorkoutLogEntry>,
      weights: results[3] as List<WeightPoint>,
      plannedWeekdays: ProgressService.plannedWeekdays(plan),
      targetKcal: plan.nutrition.targetKcal,
    );
  }
}

Widget _stateScaffold(String title, {required bool loading, required String? error, required VoidCallback retry, required Widget Function() body}) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? MessageState(message: error, onRetry: retry) : body(),
  );
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

// ======================================================================================================================================
// FR-7 and FE-10: Weekly Report, with weekly and monthly figures
// ======================================================================================================================================

class WeeklyReportScreen extends StatefulWidget {
  final Future<ActivityInputs> Function()? loader;
  const WeeklyReportScreen({Key? key, this.loader}) : super(key: key);

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  ActivityInputs? _in;
  String? _error;
  bool _loading = true;
  int _choice = 0; // 0 this week, 1 last week, 2 last 30 days

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
      final d = await (widget.loader ?? ActivityInputs.load)();
      if (mounted) setState(() => _in = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your report.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  PeriodReport _report(ActivityInputs d, ReportPeriod p, {double? previousScore}) => ActivityReports.build(
        period: p, today: d.today, activity: d.activity, kcalByDate: d.kcalByDate, plannedWeekdays: d.plannedWeekdays, targetKcal: d.targetKcal,
        sessions: d.sessions, weights: d.weights, previousScore: previousScore,
      );

  PeriodReport _current(ActivityInputs d) {
    final thisWeek = ReportPeriod.weekOf(d.today, label: 'This week');
    final lastWeek = ReportPeriod.weekOf(d.today.subtract(const Duration(days: 7)), label: 'Last week');
    final beforeLast = ReportPeriod.weekOf(d.today.subtract(const Duration(days: 14)));
    switch (_choice) {
      case 0:
        return _report(d, thisWeek, previousScore: _report(d, lastWeek).score);
      case 1:
        return _report(d, lastWeek, previousScore: _report(d, beforeLast).score);
      default:
        return _report(d, ReportPeriod.lastDays(30, d.today, label: 'Last 30 days'));
    }
  }

  String _plain(PeriodReport r) =>
      '${r.period.label} (${r.workoutsDone} workouts, ${r.activeMinutes} active minutes)\n${r.summary.join('\n')}\n${r.focus}\nWritten by the Baymax app from my own logs.';

  @override
  Widget build(BuildContext context) {
    return _stateScaffold('Weekly report', loading: _loading && _in == null, error: _error != null && _in == null ? _error : null, retry: _load, body: () {
      final r = _current(_in!);
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
        children: [
          Wrap(spacing: 8, children: [
            for (final (i, label) in const ['This week', 'Last week', 'Last 30 days'].indexed)
              ChoiceChip(label: Text(label), selected: _choice == i, onSelected: (_) => setState(() => _choice = i)),
          ]),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(Icons.fitness_center_rounded, r.workoutsPlanned > 0 ? '${r.workoutsDone}/${r.workoutsPlanned}' : '${r.workoutsDone}', 'Workouts done')),
              const SizedBox(width: 10),
              Expanded(child: _tile(Icons.timer_rounded, '${r.activeMinutes}', 'Active minutes')),
            ]),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(Icons.local_fire_department_rounded, r.avgKcal == null ? '—' : '${r.avgKcal!.round()}', 'Avg kcal eaten / day')),
              const SizedBox(width: 10),
              Expanded(child: _tile(r.score != null ? Icons.bolt_rounded : Icons.restaurant_rounded, r.score != null ? '${r.score!.round()}' : '${r.daysLogged}/${r.daysElapsed}', r.score != null ? 'Fitness score' : 'Days logged')),
            ]),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(Icons.verified_rounded, r.avgPosture == null ? '—' : '${r.avgPosture!.round()}%', 'Form score (camera)')),
              const SizedBox(width: 10),
              Expanded(child: _tile(Icons.monitor_weight_rounded, r.weightChangeKg == null ? '—' : '${r.weightChangeKg! > 0 ? '+' : ''}${r.weightChangeKg!.toStringAsFixed(1)} kg', 'Weight change')),
            ]),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.period.label}: summary', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              for (final line in r.summary) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line, style: const TextStyle(height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
              const SizedBox(height: 4),
              Text(r.focus, style: const TextStyle(height: 1.45, color: AppTheme.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('Written by the app from your own logs using fixed rules, not by an AI model. It only says what your numbers show. Decision support, not medical advice.', style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 12),
          GlowButton(
            label: 'Copy this report',
            icon: Icons.ios_share_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _plain(r)));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied.')));
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutHistoryScreen(loader: widget.loader))),
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('Workout history'),
          ),
        ],
      );
    });
  }
}

// ======================================================================================================================================
// FR-9: Workout History (calendar heatmap and session cards)
// ======================================================================================================================================

class WorkoutHistoryScreen extends StatefulWidget {
  final Future<ActivityInputs> Function()? loader;
  const WorkoutHistoryScreen({Key? key, this.loader}) : super(key: key);

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  ActivityInputs? _in;
  String? _error;
  bool _loading = true;
  DateTime? _picked;

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
      final d = await (widget.loader ?? ActivityInputs.load)();
      if (mounted) setState(() => _in = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your workout history.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _dateLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  Color _shade(int level) => level == 0 ? AppTheme.border.withOpacity(0.55) : AppTheme.primary.withOpacity(0.3 + 0.17 * level);

  Widget _heatmap(List<List<HeatCell>> weeks) {
    return LayoutBuilder(builder: (context, c) {
      const labelW = 30.0, gap = 3.0;
      final cell = ((c.maxWidth - labelW - gap * weeks.length) / weeks.length).clamp(8.0, 26.0);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: labelW,
          child: Column(children: [
            for (final (i, l) in _weekdays.indexed) SizedBox(height: cell + gap, child: Align(alignment: Alignment.centerLeft, child: Text(i.isEven ? l : '', style: const TextStyle(fontSize: 9.5, color: AppTheme.textSecondary)))),
          ]),
        ),
        for (final w in weeks)
          Padding(
            padding: const EdgeInsets.only(right: gap),
            child: Column(children: [
              for (final cellData in w)
                Padding(
                  padding: const EdgeInsets.only(bottom: gap),
                  child: Semantics(
                    label: '${_dateLabel(cellData.date)}: ${cellData.future ? 'not yet' : cellData.level == 0 ? 'no workout' : '${cellData.minutes} minutes'}',
                    button: !cellData.future,
                    child: GestureDetector(
                      onTap: cellData.future ? null : () => setState(() => _picked = cellData.date),
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: cellData.future ? Colors.transparent : _shade(cellData.level),
                          borderRadius: BorderRadius.circular(3),
                          border: _picked != null && Gamification.dateOnly(_picked!) == cellData.date ? Border.all(color: AppTheme.textPrimary, width: 1.5) : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]);
    });
  }

  Widget _dayCard(HistoryDay d) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_dateLabel(d.date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary))),
          Flexible(child: Text('${d.minutes} min${d.kcal > 0 ? ' · ${d.kcal} kcal' : ''}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13))),
        ]),
        if (d.entries.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Workout marked as done (no exercise detail was recorded).', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
        for (final e in d.entries)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(e.exerciseName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Flexible(child: Text('${e.reps} reps · ${(e.duration.inSeconds / 60).round()} min${e.postureScore == null ? '' : ' · form ${e.postureScore}%'}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))),
            ]),
          ),
        if (d.avgPosture != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Average form score ${d.avgPosture!.round()}%', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _stateScaffold('Workout history', loading: _loading && _in == null, error: _error != null && _in == null ? _error : null, retry: _load, body: () {
      final d = _in!;
      final heat = ActivityReports.heatmap(today: d.today, activity: d.activity);
      final from = heat.first.first.date;
      final history = ActivityReports.history(from: from, to: d.today, activity: d.activity, sessions: d.sessions);
      final (days, minutes) = ActivityReports.totals(history);
      final picked = _picked == null ? null : history.where((h) => h.date == Gamification.dateOnly(_picked!)).firstOrNull;
      final shown = _picked == null ? history.take(30).toList() : (picked == null ? <HistoryDay>[] : [picked]);
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
        children: [
          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Last ${heat.length} weeks', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
              Text('$days workout day${days == 1 ? '' : 's'}, $minutes active minutes', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              _heatmap(heat),
              const SizedBox(height: 10),
              Row(children: [
                const Text('Fewer', style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
                const SizedBox(width: 6),
                for (var l = 0; l <= 4; l++) Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 3), decoration: BoxDecoration(color: _shade(l), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 3),
                const Text('longer workouts', style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
              ]),
              const SizedBox(height: 6),
              const Text('Shades: no workout, under 20, 20 to 39, 40 to 59, 60 or more minutes. Tap a day to see it.', style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
            ]),
          ),
          if (_picked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(_dateLabel(_picked!), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary))),
                TextButton(onPressed: () => setState(() => _picked = null), child: const Text('Show all')),
              ]),
            ),
          if (shown.isEmpty)
            GlassCard(child: Text(_picked == null ? 'No workouts in the last ${heat.length} weeks yet. Finish a workout and it will appear here.' : 'No workout was recorded on ${_dateLabel(_picked!)}.', style: const TextStyle(color: AppTheme.textSecondary, height: 1.4))),
          for (final h in shown) _dayCard(h),
        ],
      );
    });
  }
}

// ======================================================================================================================================
// FR-8: Progress Tracker (weight chart and body measurements)
// ======================================================================================================================================

class ProgressTrackerData {
  final List<WeightPoint> weights;
  final List<BodyMeasurement> measurements;
  final double? targetKg;
  const ProgressTrackerData(this.weights, this.measurements, this.targetKg);

  static Future<ProgressTrackerData> load() async {
    final p = UserSession.instance.profile;
    if (p == null) throw const ApiException('Complete your health profile first.');
    final today = DateTime.now();
    final from = FoodLogService.dateKey(today.subtract(const Duration(days: 364)));
    final to = FoodLogService.dateKey(today);
    final results = await Future.wait([WeightService.instance.range(from, to), MeasurementService.instance.range(from, to)]);
    final target = p.targetWeightValue > 0 ? HealthCalc.toKg(p.targetWeightValue, p.targetWeightUnit) : null;
    return ProgressTrackerData(results[0] as List<WeightPoint>, results[1] as List<BodyMeasurement>, target);
  }
}

class ProgressTrackerScreen extends StatefulWidget {
  final Future<ProgressTrackerData> Function()? loader;

  /// Saves one entry; replaceable so the screen can be tested without Firebase.
  final Future<void> Function(BodyMeasurement)? onSave;
  const ProgressTrackerScreen({Key? key, this.loader, this.onSave}) : super(key: key);

  @override
  State<ProgressTrackerScreen> createState() => _ProgressTrackerScreenState();
}

class _ProgressTrackerScreenState extends State<ProgressTrackerScreen> {
  ProgressTrackerData? _data;
  String? _error;
  bool _loading = true;
  final _controllers = {for (final s in BodyMeasurement.sites) s: TextEditingController()};
  final _problems = <String, String?>{};
  bool _saving = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await (widget.loader ?? ProgressTrackerData.load)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your progress.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final problems = {for (final s in BodyMeasurement.sites) s: MeasurementService.problem(_controllers[s]!.text, s)};
    final values = {for (final s in BodyMeasurement.sites) s: MeasurementService.parse(_controllers[s]!.text)};
    final empty = values.values.every((v) => v == null);
    setState(() => _problems
      ..clear()
      ..addAll(problems));
    if (problems.values.any((p) => p != null)) return;
    if (empty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one measurement.')));
      return;
    }
    final entry = BodyMeasurement(Gamification.dateOnly(DateTime.now()), waistCm: values['Waist'], chestCm: values['Chest'], hipsCm: values['Hips'], armCm: values['Arm'], thighCm: values['Thigh']);
    setState(() => _saving = true);
    try {
      await (widget.onSave ?? MeasurementService.instance.set)(entry);
      for (final c in _controllers.values) {
        c.clear();
      }
      if (mounted) setState(() => _adding = false);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Measurements saved.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    return _stateScaffold('Progress tracker', loading: _loading && _data == null, error: _error != null && _data == null ? _error : null, retry: _load, body: () {
      final d = _data!;
      final w = d.weights;
      final latest = w.isEmpty ? null : w.last.kg;
      final change = w.length >= 2 ? w.last.kg - w.first.kg : null;
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
        children: [
          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weight', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
              if (latest != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${latest.toStringAsFixed(1)} kg now${change == null ? '' : ' · ${change > 0 ? '+' : change < 0 ? '-' : ''}${change.abs().toStringAsFixed(1)} kg since ${_months[w.first.date.month - 1]} ${w.first.date.day}'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ),
              const SizedBox(height: 12),
              if (w.length >= 2)
                SizedBox(height: 150, width: double.infinity, child: WeightTrendChart(points: w, targetKg: d.targetKg))
              else
                const Text('Log your weight at least twice to see a chart.', style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalorieTargetScreen())).then((_) => _load()),
                icon: const Icon(Icons.monitor_weight_rounded),
                label: const Text('Log my weight'),
              ),
            ]),
          ),
          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Body measurements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(d.measurements.isEmpty ? 'Measure the same places, in the same way, about once a month. Entries are in centimetres.' : 'Change from your first to your latest entry.', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.35)),
              for (final site in BodyMeasurement.sites)
                if (d.measurements.any((m) => m.valueOf(site) != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      Expanded(child: Text(site, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                      Text('${d.measurements.lastWhere((m) => m.valueOf(site) != null).valueOf(site)!.toStringAsFixed(1)} cm', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
                      SizedBox(
                        width: 84,
                        child: Text(
                          MeasurementService.change(d.measurements, site) == null ? '' : '${MeasurementService.change(d.measurements, site)! > 0 ? '+' : ''}${MeasurementService.change(d.measurements, site)!.toStringAsFixed(1)} cm',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                        ),
                      ),
                    ]),
                  ),
              const SizedBox(height: 12),
              if (!_adding)
                GlowButton(label: 'Add measurements', icon: Icons.straighten_rounded, onPressed: () => setState(() => _adding = true))
              else ...[
                for (final site in BodyMeasurement.sites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _controllers[site],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: '$site (cm), optional', errorText: _problems[site]),
                    ),
                  ),
                Row(children: [
                  Expanded(child: GlowButton(label: 'Save', icon: Icons.check_rounded, onPressed: _save, loading: _saving)),
                  const SizedBox(width: 10),
                  TextButton(onPressed: _saving ? null : () => setState(() => _adding = false), child: const Text('Cancel')),
                ]),
              ],
            ]),
          ),
          const GlassCard(
            child: Text('Progress photos are not part of this version: storing photos needs a storage service that has not been set up. Measurements and weight are kept in your own account only.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
          ),
        ],
      );
    });
  }
}

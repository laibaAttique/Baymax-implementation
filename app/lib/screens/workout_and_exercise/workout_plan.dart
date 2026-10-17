import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/plan.dart';
import '../../services/activity_service.dart';
import '../../services/api_client.dart';
import '../../services/exercise_catalog.dart';
import '../../services/exercise_library.dart';
import '../../services/food_log_service.dart';
import '../../services/gamification.dart';
import '../../services/notification_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/exercise_photo.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/glass.dart';
import '../health_profiling/health_classification.dart';
import '../nutrition/nutrition_plan_screen.dart';
import 'exercise_detail.dart';
import 'workout_readiness_screen.dart';

/// Module 3: the generated weekly workout schedule (FR-5) with the medical
/// rules that shaped it (FR-1) and a Regenerate button (FE-7).
class WorkoutPlan extends StatefulWidget {
  const WorkoutPlan({Key? key}) : super(key: key);

  @override
  State<WorkoutPlan> createState() => _WorkoutPlanState();
}

class _WorkoutPlanState extends State<WorkoutPlan> {
  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  int? _selectedDay;
  bool _regenerating = false;

  /// Dates (YYYY-MM-DD) of this week's completed workouts (Module 11/14 activity log).
  Set<String> _done = {};
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _loadDone();
  }

  Future<void> _loadDone() async {
    try {
      final today = Gamification.dateOnly(DateTime.now());
      final entries = await ActivityService.instance.range(FoodLogService.dateKey(Gamification.weekStart(today)), FoodLogService.dateKey(today));
      if (mounted) setState(() => _done = entries.keys.toSet());
    } catch (_) {
      // Not signed in or offline: the button simply starts unticked.
    }
  }

  Future<void> _toggleDone(DateTime date, WorkoutDay day, double weightKg, PersonalizedPlan plan, bool wasDone) async {
    setState(() => _marking = true);
    try {
      if (wasDone) {
        await ActivityService.instance.undo(date);
      } else {
        await ActivityService.instance.markDone(date, minutes: day.durationMin, kcal: day.kcal(weightKg));
      }
      await _loadDone();
      NotificationService.instance.refreshFromAccount(plan);
      if (!wasDone) {
        final progress = await ProgressService.instance.load(plan);
        if (mounted && progress.newBadges.isNotEmpty) {
          final names = Gamification.catalogue.where((b) => progress.newBadges.contains(b.id)).map((b) => b.title).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New badge: $names')));
        }
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Widget _completionCard(int selected, WorkoutDay day, double weightKg, PersonalizedPlan plan) {
    final today = Gamification.dateOnly(DateTime.now());
    final date = Gamification.weekStart(today).add(Duration(days: selected));
    final done = _done.contains(FoodLogService.dateKey(date));
    final future = date.isAfter(today);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.glass(radius: AppTheme.rMedium, tint: done ? AppTheme.tint(AppTheme.success, 0.16) : null),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: IconWell(
              key: ValueKey(done),
              icon: done ? Icons.check_circle_rounded : Icons.flag_rounded,
              color: done ? AppTheme.success : AppTheme.primary,
              size: 38,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              done ? 'Workout completed' : (future ? 'You can tick this off on the day' : 'Finished this workout?'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 13.5),
            ),
          ),
          if (!future)
            _marking
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(
                    onPressed: () => _toggleDone(date, day, weightKg, plan, done),
                    child: Text(done ? 'Undo' : 'Mark done'),
                  ),
        ],
      ),
    );
  }

  Future<void> _openReadiness() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const WorkoutReadinessScreen()));
    if (changed == true && mounted) setState(() => _selectedDay = null);
  }

  /// Shown instead of the plan when the safety rules require more information or a doctor's clearance first.
  Widget _gateScaffold(PersonalizedPlan plan) {
    final gate = plan.gate!;
    final clearance = gate.status == WorkoutGateStatus.needsClearance;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout'), actions: const [NotificationBell(), SizedBox(width: 8)]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, AppTheme.navSpace(context) + 16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconWell(icon: clearance ? Icons.medical_services_rounded : Icons.fact_check_rounded, color: clearance ? AppTheme.error : AppTheme.primary, size: 52),
                const SizedBox(height: 14),
                Text(clearance ? 'A doctor\'s clearance comes first' : 'A few answers are needed first',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                for (final r in gate.reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(r, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.45, fontWeight: FontWeight.w500)),
                  ),
                const SizedBox(height: 10),
                Text('Rules: ${gate.ruleIds.join(', ')} (${plan.rulesVersion}, pending professional review). Baymax does not give medical clearance.',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlowButton(
            icon: Icons.fact_check_rounded,
            label: UserSession.instance.readiness.answered ? 'Update my answers' : 'Answer the safety questions',
            onPressed: _openReadiness,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
            icon: const Icon(Icons.set_meal_rounded, size: 18),
            label: const Text('View nutrition plan'),
          ),
        ],
      ),
    );
  }

  int _defaultDay(PersonalizedPlan plan) {
    final today = DateTime.now().weekday - 1;
    if (plan.week[today] != null) return today;
    final next = List.generate(7, (i) => i).firstWhere((i) => plan.week[i] != null, orElse: () => today);
    return next;
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate plan?'),
        content: const Text('You\'ll get a new set of exercises and meals. Your health restrictions still apply.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Regenerate')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _regenerating = true);
    final saved = await UserSession.instance.regeneratePlan();
    if (!mounted) return;
    setState(() {
      _regenerating = false;
      _selectedDay = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? 'New plan generated.' : 'New plan generated, but it could not be saved to the server.')),
    );
  }

  Widget _stat(IconData icon, String val, String lbl) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(height: 6),
          Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3)),
          const SizedBox(height: 1),
          Text(lbl, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildExerciseCard(PlannedExercise p, List<String> notes, int index, List<PlannedExercise> queue) {
    final e = p.exercise;
    final color = e.level == 1 ? AppTheme.success : (e.level == 2 ? AppTheme.warning : AppTheme.error);
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          radius: AppTheme.rMedium + 2,
          semanticLabel: '${e.name}, ${p.prescription}. Open details',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseDetail(planned: p, safetyNotes: notes, queue: queue))),
          child: Row(
            children: [
              ExerciseCatalog.imagesFor(e).isEmpty
                  ? IconWell(icon: AppIcons.exercise(e.group), size: 50)
                  : SizedBox(
                      width: 50,
                      child: ExercisePhoto(urls: ExerciseCatalog.imagesFor(e), group: e.group, height: 50, radius: 14, animate: false),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.prescription, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                        InfoChip(e.levelLabel, color: color),
                        if (p.ruleNotes.isNotEmpty) const InfoChip('Adapted for you', color: AppTheme.teal),
                      ],
                    ),
                    if (p.reasons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(p.reasons.first, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppTheme.primary, height: 1.35, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Seven equal columns (letter + date) that stretch to the screen width. Rest days are muted; completed days carry a tick.
  Widget _dayStrip(PersonalizedPlan plan, int selected) {
    final today = Gamification.dateOnly(DateTime.now());
    final monday = Gamification.weekStart(today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: List.generate(7, (index) {
          final isSelected = selected == index;
          final isRest = plan.week[index] == null;
          final date = monday.add(Duration(days: index));
          final isDone = _done.contains(FoodLogService.dateKey(date));
          final isToday = date == today;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                button: true,
                selected: isSelected,
                label: '${_dayNames[index]}${isRest ? ', rest day' : ''}${isDone ? ', completed' : ''}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedDay = index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSelected ? AppTheme.buttonGradient : null,
                      color: isSelected ? null : (isRest ? AppTheme.background : AppTheme.card),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isSelected ? Colors.transparent : (isToday ? AppTheme.primary : Colors.white), width: isToday && !isSelected ? 1.6 : 1.2),
                      boxShadow: isSelected ? AppTheme.glowShadow(blur: 16, opacity: 0.34, offset: const Offset(0, 6)) : const [],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_dayLetters[index], style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: isSelected ? Colors.white.withOpacity(0.9) : AppTheme.textSecondary)),
                        const SizedBox(height: 3),
                        Text('${date.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : (isRest ? AppTheme.textSecondary : AppTheme.textPrimary))),
                        const SizedBox(height: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone ? (isSelected ? Colors.white : AppTheme.success) : (isRest ? Colors.transparent : (isSelected ? Colors.white.withOpacity(0.5) : AppTheme.primary.withOpacity(0.35))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserSession.instance,
      builder: (context, _) {
        final session = UserSession.instance;
        final plan = session.plan;
        final profile = session.profile;
        final cls = session.classification;

        if (plan == null || profile == null || cls == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workout')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Complete your health profile to get a personalised workout plan.', textAlign: TextAlign.center),
              ),
            ),
          );
        }

        if (!plan.workoutAvailable) return _gateScaffold(plan);

        final selected = _selectedDay ?? _defaultDay(plan);
        final day = plan.week[selected];
        final main = day?.exercises.where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown').toList() ?? const <PlannedExercise>[];
        final riskColor = HealthClassification.colorFor(cls.riskLevel);
        final isToday = selected == DateTime.now().weekday - 1;
        final bottomSpace = AppTheme.navSpace(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Workout'),
            actions: [
              const NotificationBell(),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomSpace + (day != null && main.isNotEmpty ? 76 : 0)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Reveal(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: Text('Your workout plan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.8, height: 1.15)),
                                ),
                                const SizedBox(width: 8),
                                Padding(padding: const EdgeInsets.only(top: 6), child: InfoChip(cls.category, color: riskColor)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${plan.intensity} intensity · ${plan.workoutDays} days a week',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),

                    if (!session.readiness.answered)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: GlassCard(
                          tint: AppTheme.tint(AppTheme.primary, 0.10),
                          onTap: _openReadiness,
                          semanticLabel: 'Answer the exercise readiness questions',
                          child: const Row(children: [
                            IconWell(icon: Icons.fact_check_rounded, size: 40),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Answer 4 quick safety questions to tailor this plan to your injuries and equipment. '
                                'Until then it uses body-weight exercises only.',
                                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                          ]),
                        ),
                      ),

                    Reveal(index: 1, child: _dayStrip(plan, selected)),

                    if (day == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: GlassCard(
                          padding: const EdgeInsets.all(24),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              children: [
                                const IconWell(icon: Icons.bedtime_rounded, size: 56),
                                const SizedBox(height: 14),
                                Text('${_dayNames[selected]} is a rest day',
                                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                                const SizedBox(height: 6),
                                const Text(
                                  'Recovery is when your body adapts. A relaxed walk, light stretching and good sleep are all you need.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppTheme.textSecondary, height: 1.45, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                        child: Text('${day.name} · ${day.focus}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              _stat(Icons.timer_rounded, '${day.durationMin} min', 'Duration'),
                              Container(width: 1, height: 44, color: AppTheme.border),
                              _stat(Icons.local_fire_department_rounded, '${day.kcal(profile.weightKg)}', day.modelKcal != null ? 'kcal (AI)' : 'kcal'),
                              Container(width: 1, height: 44, color: AppTheme.border),
                              _stat(Icons.fitness_center_rounded, '${main.length}', 'Exercises'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _completionCard(selected, day, profile.weightKg, plan),
                      const SectionHeader('Exercises', padding: EdgeInsets.fromLTRB(20, 18, 20, 10)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [for (var i = 0; i < day.exercises.length; i++) _buildExerciseCard(day.exercises[i], plan.restrictionNotes, i, day.exercises)],
                        ),
                      ),
                    ],

                    // Medical rules applied (FR-1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                IconWell(icon: Icons.shield_rounded, color: AppTheme.teal, size: 36),
                                SizedBox(width: 12),
                                Expanded(child: Text('How this plan protects you', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            for (final note in plan.restrictionNotes)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 5, color: AppTheme.teal)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(note, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: OutlinedButton.icon(
                        onPressed: _regenerating ? null : _regenerate,
                        icon: _regenerating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh_rounded),
                        label: const Text('Regenerate plan'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
                        icon: const Icon(Icons.set_meal_rounded, size: 18),
                        label: const Text('View nutrition plan'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextButton.icon(
                        onPressed: _openReadiness,
                        icon: const Icon(Icons.fact_check_rounded, size: 18),
                        label: Text(session.readiness.answered ? 'Update safety & equipment answers' : 'Answer safety & equipment questions'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Text(
                        '${ExerciseLibrary.originLabel}'
                        '${ExerciseCatalog.isLoaded ? ', plus ${ExerciseCatalog.all.length} free-exercise-db exercises for the equipment you have' : ''}. '
                        'Energy values: 2024 Compendium of Physical Activities. Safety rules ${plan.rulesVersion} (pending professional review). '
                        'See Profile → Sources & methodology.',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),

              if (day != null && main.isNotEmpty)
                Positioned(
                  bottom: bottomSpace - 28 + 8, // sits just above the floating navigation bar (or the screen edge when pushed)
                  left: 20,
                  right: 20,
                  child: GlowButton(
                    icon: isToday ? Icons.play_arrow_rounded : Icons.visibility_rounded,
                    label: isToday ? "Start today's workout" : 'Preview workout',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ExerciseDetail(planned: day.exercises.first, safetyNotes: plan.restrictionNotes, queue: day.exercises)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/plan.dart';
import '../../services/exercise_library.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../health_profiling/health_classification.dart';
import '../nutrition/nutrition_plan_screen.dart';
import 'exercise_detail.dart';

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

  Widget _buildMetaChip(String val, String lbl) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(lbl, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(PlannedExercise p, List<String> notes) {
    final e = p.exercise;
    final color = e.level == 1 ? AppTheme.success : (e.level == 2 ? AppTheme.warning : AppTheme.error);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseDetail(planned: p, safetyNotes: notes))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppTheme.background, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(e.icon, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${p.prescription} · ', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: Text(e.levelLabel.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.play_circle_fill, color: AppTheme.primary, size: 28),
          ],
        ),
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
            appBar: AppBar(title: const Text('Baymax', style: TextStyle(fontSize: 16))),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Complete your health profile to get a personalised workout plan.', textAlign: TextAlign.center),
              ),
            ),
          );
        }

        final selected = _selectedDay ?? _defaultDay(plan);
        final day = plan.week[selected];
        final main = day?.exercises.where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown').toList() ?? const <PlannedExercise>[];
        final riskColor = HealthClassification.colorFor(cls.riskLevel);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Baymax', style: TextStyle(fontSize: 16)),
            centerTitle: true,
            actions: [
              IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryLight,
                  child: Text(
                    profile.fullName.isEmpty ? '?' : profile.fullName[0].toUpperCase(),
                    style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text('Your Workout Plan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: riskColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text(cls.category.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: riskColor)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('${plan.intensity} intensity · ${plan.workoutDays} days/week',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ),

                    // Day chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: List.generate(7, (index) {
                          final isSelected = selected == index;
                          final isRest = plan.week[index] == null;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedDay = index),
                            child: Container(
                              width: 42,
                              height: 42,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary : (isRest ? AppTheme.background : AppTheme.card),
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? AppTheme.primary : (isRest ? AppTheme.border : Colors.transparent), width: 2),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _dayLetters[index],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : (isRest ? AppTheme.textSecondary.withOpacity(0.6) : AppTheme.textPrimary),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    if (day == null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text('🛌', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            Text('${_dayNames[selected]} is a rest day',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            const SizedBox(height: 4),
                            const Text(
                              'Recovery is when your body adapts. A relaxed walk, light stretching and good sleep are all you need.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('${day.name} · ${day.focus}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            _buildMetaChip('${day.durationMin}m', 'Duration'),
                            _buildMetaChip('${day.kcal(profile.weightKg)}', day.modelKcal != null ? 'Calories (AI)' : 'Calories'),
                            _buildMetaChip('${main.length}', 'Exercises'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [for (final p in day.exercises) _buildExerciseCard(p, plan.restrictionNotes)],
                        ),
                      ),
                    ],

                    // Medical rules applied (FR-1)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text('🛡️', style: TextStyle(fontSize: 20)),
                              SizedBox(width: 8),
                              Expanded(child: Text('How this plan protects you', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final note in plan.restrictionNotes)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('• $note', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
                            ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: OutlinedButton.icon(
                        onPressed: _regenerating ? null : _regenerate,
                        icon: _regenerating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        label: const Text('Regenerate plan'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionPlanScreen())),
                        child: const Text('View Nutrition Plan →'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        '${ExerciseLibrary.originLabel}. Energy values: 2024 Compendium of Physical Activities. See Profile → Sources & methodology.',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),

              if (day != null && main.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppTheme.background, AppTheme.background.withOpacity(0.0)],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ExerciseDetail(planned: main.first, safetyNotes: plan.restrictionNotes)),
                      ),
                      child: Text(selected == DateTime.now().weekday - 1 ? 'Start Today\'s Workout 🔥' : 'Preview Workout →'),
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

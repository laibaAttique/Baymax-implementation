import 'package:flutter/material.dart';

import '../../models/health_profile.dart';
import '../../models/plan.dart';
import '../../models/workout_session.dart';
import '../../services/exercise_catalog.dart';
import '../../services/exercise_repository.dart';
import '../../services/posture/movement_patterns.dart';
import '../../services/user_session.dart';
import '../../services/workout_session/plan_progress.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/exercise_photo.dart';
import '../../widgets/glass.dart';
import '../health_profiling/step1_personal_info.dart';
import '../workout_and_exercise/workout_readiness_screen.dart';
import 'exercise_picker.dart';
import 'posture_mode.dart';

/// Module 5 entry point from the Home Dashboard: the user's own plan first, the generic library as well.
///
/// * Today's workout — the exercises of today's plan day, with their dose, difficulty, camera capability and whether
///   they were completed today.
/// * My plan — the whole week; rest days shown as such.
/// * Exercise library — the generic curated library, unchanged.
///
/// Exercises are started with their plan link (plan fingerprint, day, entry), so a session that reaches its target
/// completes that planned exercise in Module 4. Nothing here generates or alters a plan, and only exercises the
/// Module 4 safety rules already scheduled are shown.
class PostureDetectionHome extends StatefulWidget {
  const PostureDetectionHome({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<PostureDetectionHome> createState() => _PostureDetectionHomeState();
}

class _PostureDetectionHomeState extends State<PostureDetectionHome> {
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late int _planDay = PlanProgress.instance.todayIndex;

  @override
  void initState() {
    super.initState();
    PlanProgress.instance.loadToday();
  }

  void _start(int weekday, WorkoutDay day, int index) {
    final planned = day.exercises[index];
    final request = WorkoutSessionRequest.fromPlanned(
      planned,
      upNext: day.exercises.sublist(index + 1),
      plan: PlanProgress.instance.linkFor(weekday, index),
    );
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostureModeSelection(request: request)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Posture Detection', style: TextStyle(fontSize: 16)),
          centerTitle: true,
          bottom: const TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: [
              Tab(key: ValueKey('tab-today'), text: "Today's workout"),
              Tab(key: ValueKey('tab-plan'), text: 'My plan'),
              Tab(key: ValueKey('tab-library'), text: 'Exercise library'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([UserSession.instance, PlanProgress.instance]),
          builder: (context, _) => TabBarView(
            children: [
              _planTab(today: true),
              _planTab(today: false),
              const ExerciseLibraryList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planTab({required bool today}) {
    final session = UserSession.instance;
    if (session.loading) {
      return const _Message(
          key: ValueKey('plan-loading'), icon: Icons.hourglass_top_rounded, title: 'Loading your plan…', busy: true);
    }
    final plan = session.plan;
    if (plan == null) {
      return _Message(
        key: const ValueKey('plan-empty'),
        icon: Icons.assignment_ind_rounded,
        title: 'No personalised plan yet',
        detail: 'Complete your health profile and Baymax will build a workout plan for you. '
            'You can still use the exercise library meanwhile.',
        action: 'Create my health profile',
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Step1PersonalInfo(profile: HealthProfile()))),
      );
    }
    if (!plan.workoutAvailable) {
      return _Message(
        key: const ValueKey('plan-gated'),
        icon: Icons.fact_check_rounded,
        title: plan.gate!.status == WorkoutGateStatus.needsClearance ? "A doctor's clearance comes first" : 'A few answers are needed first',
        detail: plan.gate!.reasons.join('\n'),
        action: 'Answer the safety questions',
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutReadinessScreen())),
      );
    }
    final weekday = today ? PlanProgress.instance.todayIndex : _planDay;
    final day = plan.week[weekday];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (!today) _dayChips(plan),
        if (day == null)
          _Message(
            key: const ValueKey('rest-day'),
            icon: Icons.bedtime_rounded,
            title: '${today ? 'Today' : _dayNames[weekday]} is a rest day',
            detail: today ? 'Recover, stretch and hydrate. Open "My plan" to look at another day.' : 'No exercises are scheduled for this day.',
            compact: true,
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Text('${today ? 'Today' : _dayNames[weekday]} · ${day.name} · ${day.durationMin} min',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          ),
          if (!today && weekday != PlanProgress.instance.todayIndex)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text("Sessions for another day are saved, but only today's plan day can be ticked off as completed.",
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
            ),
          for (var i = 0; i < day.exercises.length; i++) _entryTile(weekday, day, i),
        ],
      ],
    );
  }

  Widget _dayChips(PersonalizedPlan plan) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    key: ValueKey('day-$i'),
                    label: Text(_dayLetters[i]),
                    selected: _planDay == i,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                        color: plan.week[i] == null ? AppTheme.textSecondary : (_planDay == i ? Colors.white : AppTheme.textPrimary),
                        fontWeight: FontWeight.w700),
                    selectedColor: AppTheme.primary,
                    onSelected: (_) => setState(() => _planDay = i),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _entryTile(int weekday, WorkoutDay day, int index) {
    final p = day.exercises[index];
    final e = p.exercise;
    final posture = ExerciseRepository.postureFor(e);
    final done = weekday == PlanProgress.instance.todayIndex && PlanProgress.instance.isDoneToday(weekday, index);
    final photos = ExerciseCatalog.imagesFor(e);
    return Padding(
      key: ValueKey('entry-$weekday-$index'),
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: AppTheme.rMedium + 2,
        onTap: () => _start(weekday, day, index),
        semanticLabel: '${e.name}, ${p.prescription}${done ? ', done today' : ''}. Start',
        child: Row(
          children: [
            photos.isEmpty
                ? IconWell(icon: AppIcons.exercise(e.group), size: 50)
                : SizedBox(width: 50, child: ExercisePhoto(urls: photos, group: e.group, height: 50, radius: 14, animate: false)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(p.prescription, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                      InfoChip(e.levelLabel, color: e.level == 1 ? AppTheme.success : (e.level == 2 ? AppTheme.warning : AppTheme.error)),
                      if (done) const InfoChip('Done today', icon: Icons.check_rounded, color: AppTheme.success),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_capability(posture),
                      key: ValueKey('capability-$weekday-$index'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: posture.supportsCameraTracking ? AppTheme.primary : AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(posture.supportsCameraTracking ? Icons.videocam_rounded : Icons.list_alt_rounded, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  static String _capability(ExercisePostureConfig c) => switch (c.level) {
        CameraSupportLevel.validatedForm || CameraSupportLevel.experimentalForm => 'Camera: posture score and corrections',
        CameraSupportLevel.basicTracking => c.supportsHoldTiming ? 'Camera: hold timer' : 'Camera: rep counting',
        CameraSupportLevel.notSupported => 'Manual Guidance',
      };
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;
  final bool compact;
  const _Message({super.key, required this.icon, required this.title, this.detail = '', this.action, this.onAction, this.busy = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        busy ? const CircularProgressIndicator() : IconWell(icon: icon, size: 52),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        if (detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.45)),
          ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 16), child: FilledButton(onPressed: onAction, child: Text(action!))),
      ],
    );
    return compact ? Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: body) : Center(child: Padding(padding: const EdgeInsets.all(32), child: body));
  }
}

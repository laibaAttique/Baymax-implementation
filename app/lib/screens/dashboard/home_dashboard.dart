import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/plan.dart';
import '../../services/activity_service.dart';
import '../../services/inbox_service.dart';
import '../../services/mood_service.dart';
import '../../services/user_settings_service.dart';
import '../../services/notification_service.dart';
import '../../services/progress_service.dart';
import '../../services/food_log_service.dart';
import '../../services/gamification.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/glass.dart';
import '../../widgets/progress_ring.dart';
import '../allergy/allergy_scanner.dart';
import '../chatbot/chatbot_screen.dart';
import '../posture_detection/exercise_picker.dart';
import '../community/community_screen.dart';
import '../analytics/body_transform_screen.dart';
import '../specialists/specialists_screen.dart';

class HomeDashboard extends StatefulWidget {
  final Function(int) onNavigateTab;
  final VoidCallback? onOpenMenu;
  const HomeDashboard({Key? key, required this.onNavigateTab, this.onOpenMenu}) : super(key: key);

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  double _eatenToday = 0;
  ProgressSnapshot? _progress;

  /// Today's completed workout (Module 3 FR-2): calories burned and active minutes come from what the user marked as done.
  ActivityEntry? _todayActivity;
  Mood? _mood;

  @override
  void initState() {
    super.initState();
    _loadIntake();
    _loadProgress();
    _loadToday();
    InboxService.instance.refreshUnread();
    ActivityService.instance.changes.addListener(_loadToday);
    FoodLogService.instance.changes.addListener(_loadIntake);
    FoodLogService.instance.changes.addListener(_loadProgress);
    ActivityService.instance.changes.addListener(_loadProgress);
    // Rebuild the scheduled reminders from the saved settings (only does anything if the user turned them on).
    NotificationService.instance.refreshFromAccount(UserSession.instance.plan);
  }

  @override
  void dispose() {
    FoodLogService.instance.changes.removeListener(_loadIntake);
    FoodLogService.instance.changes.removeListener(_loadProgress);
    ActivityService.instance.changes.removeListener(_loadProgress);
    ActivityService.instance.changes.removeListener(_loadToday);
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final plan = UserSession.instance.plan;
    if (plan == null) return;
    try {
      final p = await ProgressService.instance.load(plan);
      if (mounted) setState(() => _progress = p);
      // Reminders that came due while the app was closed become items in the Notifications list (Module 16).
      final settings = await UserSettingsService.instance.load();
      await InboxService.instance.syncDue(now: DateTime.now(), progress: p, settings: settings);
    } catch (_) {
      // Offline or signed out: the cards below simply stay hidden.
    }
  }

  Future<void> _loadToday() async {
    try {
      final key = FoodLogService.dateKey(DateTime.now());
      final entries = await ActivityService.instance.range(key, key);
      final mood = await MoodService.instance.forDate(DateTime.now());
      if (mounted) {
        setState(() {
          _todayActivity = entries[key];
          _mood = mood;
        });
      }
    } catch (_) {
      // Offline or signed out: the cards show zero.
    }
  }

  Future<void> _pickMood(Mood m) async {
    final next = _mood == m ? null : m;
    setState(() => _mood = next);
    try {
      await MoodService.instance.set(DateTime.now(), next);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your mood. Check your connection.')));
    }
  }

  void _openCommunity() => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen()));

  Widget _progressCard(ProgressSnapshot p) {
    final inactive = p.inactivity;
    return Column(
      children: [
        if (inactive != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: GlassCard(
              tint: AppTheme.tint(AppTheme.warning, 0.16),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconWell(icon: Icons.waving_hand_rounded, color: AppTheme.warning, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "It's been ${inactive.daysSinceWorkout} days since your last workout and you missed ${inactive.missedPlannedDays} planned "
                      "${inactive.missedPlannedDays == 1 ? 'session' : 'sessions'}. A short one still counts.",
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: GlassCard(
            onTap: _openCommunity,
            semanticLabel: 'Open progress and leaderboard',
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _ScoreRing(score: p.week.total),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('THIS WEEK', style: AppTheme.overline),
                      const SizedBox(height: 2),
                      Text('${p.level.label} level', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        InfoChip('${p.workoutStreak} workout streak', icon: Icons.local_fire_department_rounded, color: AppTheme.warning),
                        InfoChip('${p.earned.length} badges', icon: Icons.military_tech_rounded),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadIntake() async {
    try {
      final entries = await FoodLogService.instance.forDate(FoodLogService.dateKey(DateTime.now()));
      if (mounted) setState(() => _eatenToday = FoodLogService.totalKcal(entries));
    } catch (_) {
      // Leave the last known value; the Diet tab shows the error details.
    }
  }

  /// A short motivational line that changes with the time of day (Module 3 FR-1).
  String _motivation() {
    final h = DateTime.now().hour;
    if (h < 12) return 'A good start to the day makes the rest easier.';
    if (h < 17) return 'Keep the momentum going. Small steps add up.';
    return 'Finish strong. Log your meals and wind down well.';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
  }


  Widget _buildStatCard(IconData icon, Color color, String value, String label, ) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconWell(icon: icon, color: color, size: 38),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTile(IconData icon, String label, {required VoidCallback onTap, Color color = AppTheme.primary}) {
    return Pressable(
      radius: AppTheme.rMedium,
      onTap: onTap,
      semanticLabel: label.replaceAll('\n', ' '),
      child: Container(
        decoration: AppTheme.glass(radius: AppTheme.rMedium),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconWell(icon: icon, color: color, size: 40),
            const SizedBox(height: 8),
            Text(label, maxLines: 2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2, color: AppTheme.textPrimary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _workoutCard(PersonalizedPlan? plan, double weightKg) {
    final today = plan?.workoutFor(DateTime.now());
    final String title;
    final String subtitle;
    final IconData? subIcon;
    if (plan == null) {
      title = 'No plan yet';
      subtitle = 'Complete your health profile';
      subIcon = null;
    } else if (today == null) {
      title = 'Rest day';
      subtitle = 'Recover, stretch and hydrate';
      subIcon = Icons.bedtime_rounded;
    } else {
      title = today.name;
      subtitle = '${today.durationMin} min  ·  ${today.kcal(weightKg)} kcal';
      subIcon = Icons.timer_rounded;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient,
          borderRadius: BorderRadius.circular(AppTheme.rHero),
          boxShadow: AppTheme.glowShadow(blur: 30, opacity: 0.34, offset: const Offset(0, 14)),
        ),
        child: Stack(
          children: [
            // a soft highlight in the corner gives the hero card its glass-glow depth
            Positioned(
              right: -30,
              top: -40,
              child: IgnorePointer(
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withOpacity(0.22), Colors.white.withOpacity(0)])),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("TODAY'S WORKOUT", style: AppTheme.overline.copyWith(color: Colors.white.withOpacity(0.82))),
                        const SizedBox(height: 6),
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21, color: Colors.white, height: 1.15, letterSpacing: -0.4)),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (subIcon != null) ...[Icon(subIcon, size: 15, color: Colors.white.withOpacity(0.9)), const SizedBox(width: 5)],
                          Flexible(child: Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.92), fontWeight: FontWeight.w600))),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Pressable(
                    radius: 18,
                    semanticLabel: 'Open the workout plan',
                    onTap: () => widget.onNavigateTab(2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Open', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: AppTheme.primary),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('How are you feeling today?', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary, fontSize: 14.5))),
              if (_mood != null) Text(_mood!.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final m in Mood.values)
                  Semantics(
                    button: true,
                    selected: _mood == m,
                    label: m.label,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _pickMood(m);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: _mood == m ? AppTheme.buttonGradient : null,
                          color: _mood == m ? null : AppTheme.background,
                          shape: BoxShape.circle,
                          border: Border.all(color: _mood == m ? Colors.transparent : Colors.white, width: 1.2),
                          boxShadow: _mood == m ? AppTheme.glowShadow(blur: 14, opacity: 0.36, offset: const Offset(0, 5)) : const [],
                        ),
                        child: Icon(m.icon, size: 27, color: _mood == m ? Colors.white : AppTheme.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _mood == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_mood!.suggestion, style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserSession.instance,
      builder: (context, _) {
        final session = UserSession.instance;
        final profile = session.profile;
        final plan = session.plan;
        final firstName = (profile?.fullName.trim().isNotEmpty ?? false) ? profile!.fullName.trim().split(' ').first : '';
        final target = plan?.nutrition.targetKcal;

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: IconButton(icon: const Icon(Icons.menu_rounded), tooltip: 'Open menu', onPressed: widget.onOpenMenu),
            ),
            title: const Text('Baymax', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            actions: [
              const NotificationBell(),
              Padding(
                padding: const EdgeInsets.only(right: 16, left: 4),
                child: Semantics(
                  button: true,
                  label: 'Open your profile',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => widget.onNavigateTab(4),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 12, opacity: 0.3, offset: const Offset(0, 4))),
                      alignment: Alignment.center,
                      child: Text(firstName.isEmpty ? 'B' : firstName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: AppTheme.navSpace(context) + 72), // 72: room for the floating chat button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Reveal(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                        const SizedBox(height: 2),
                        Text(firstName.isEmpty ? 'Welcome back' : firstName,
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.9, height: 1.15)),
                        const SizedBox(height: 4),
                        Text(_motivation(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),

                Reveal(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(
                      children: [
                        _buildStatCard(Icons.local_fire_department_rounded, AppTheme.warning, '${_todayActivity?.kcal ?? 0}', 'Calories burned'),
                        const SizedBox(width: 10),
                        _buildStatCard(Icons.timer_rounded, AppTheme.primary, '${_todayActivity?.minutes ?? 0}', 'Active minutes'),
                        const SizedBox(width: 10),
                        _buildStatCard(Icons.directions_walk_rounded, AppTheme.teal, '—', 'Steps (no sensor)'),
                      ],
                    ),
                  ),
                ),

                Reveal(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: GlassCard(
                      onTap: () => widget.onNavigateTab(1),
                      semanticLabel: 'Calories eaten today. Open the diet tracker',
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        const IconWell(icon: Icons.restaurant_rounded, color: AppTheme.teal, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(target == null ? '${_eatenToday.round()} kcal eaten' : '${_eatenToday.round()} of $target kcal eaten', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: LinearProgressIndicator(value: target == null || target == 0 ? 0 : (_eatenToday / target).clamp(0.0, 1.0), minHeight: 7, backgroundColor: const Color(0xFFDDE0F5), color: AppTheme.teal),
                            ),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                      ]),
                    ),
                  ),
                ),
                Reveal(index: 2, child: _workoutCard(plan, profile?.weightKg ?? 70)),
                if (_progress != null) Reveal(index: 3, child: _progressCard(_progress!)),
                Reveal(index: 4, child: _moodCard()),

                const SectionHeader('Quick access'),
                Reveal(
                  index: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth >= 520 ? 6 : 4;
                      // tile height = padding + icon + gap + two label lines, so it grows with the user's text size
                      final extent = 20 + 40 + 8 + 2 * 1.25 * MediaQuery.textScalerOf(context).scale(11.5) + 4;
                      return GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: extent),
                        children: [
                          _buildQuickTile(Icons.fitness_center_rounded, 'Workout\nplan', onTap: () => widget.onNavigateTab(2)),
                          _buildQuickTile(Icons.restaurant_menu_rounded, 'Diet\ntracker', onTap: () => widget.onNavigateTab(1), color: AppTheme.teal),
                          _buildQuickTile(Icons.self_improvement_rounded, 'Posture\ncheck', onTap: () => _push(const ExercisePickerScreen())),
                          _buildQuickTile(Icons.trending_up_rounded, 'Body\ntransform', onTap: () => _push(const BodyTransformScreen()), color: AppTheme.macroFat),
                          _buildQuickTile(Icons.emoji_events_rounded, 'Leader-\nboard', onTap: _openCommunity, color: AppTheme.warning),
                          _buildQuickTile(Icons.shield_rounded, 'Allergy\nscanner', onTap: () => _push(const AllergyScanner()), color: AppTheme.teal),
                          _buildQuickTile(Icons.auto_awesome_rounded, 'AI\nchatbot', onTap: () => _push(const ChatbotScreen())),
                          _buildQuickTile(Icons.medical_services_rounded, 'Find a\nspecialist', onTap: () => _push(const SpecialistsScreen()), color: AppTheme.macroFat),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The weekly fitness score as a ring with the number in the middle.
class _ScoreRing extends StatelessWidget {
  final double score;
  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    return ProgressRing(
      value: score / 100,
      semanticLabel: 'Weekly fitness score ${score.round()} out of 100',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${score.round()}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, height: 1, letterSpacing: -0.5)),
          const Text('/100', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

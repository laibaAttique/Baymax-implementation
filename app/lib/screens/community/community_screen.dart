import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/community_service.dart';
import '../../services/gamification.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/user_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/progress_ring.dart';
import '../profile/settings_screen.dart';
import 'my_badges_screen.dart';

/// What the screen shows; loaded by [CommunityScreen.defaultLoader] or supplied by a test.
class CommunityData {
  final ProgressSnapshot progress;
  final UserSettings settings;
  final List<LeaderboardEntry> entries;
  final CohortLevels? cohort;
  final String? leaderboardError;
  final String? myUid;
  const CommunityData({required this.progress, required this.settings, this.entries = const [], this.cohort, this.leaderboardError, this.myUid});
}

/// Module 11: weekly fitness score (FR-1), leaderboard (FR-2), badges (FR-3) and fitness level (FR-4, FE-5).
class CommunityScreen extends StatefulWidget {
  final Future<CommunityData> Function()? loader;
  const CommunityScreen({Key? key, this.loader}) : super(key: key);

  static Future<CommunityData> defaultLoader() async {
    final plan = UserSession.instance.plan;
    if (plan == null) throw const ApiException('Complete your health profile first.');
    final progress = await ProgressService.instance.load(plan);
    final settings = await UserSettingsService.instance.load();
    var entries = <LeaderboardEntry>[];
    CohortLevels? cohort;
    String? error;
    if (settings.leaderboardOptIn) {
      try {
        await CommunityService.instance.publish(progress, settings.displayName);
        entries = await CommunityService.instance.top(progress.today);
        cohort = CommunityService.instance.levels(entries);
      } on ApiException catch (e) {
        error = e.message;
      }
    }
    return CommunityData(progress: progress, settings: settings, entries: entries, cohort: cohort, leaderboardError: error, myUid: AuthService.instance.currentUser?.uid);
  }

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  CommunityData? _data;
  String? _error;
  bool _loading = true;

  /// Leaderboard filter tab: null shows everyone (Module 12, mockup M32).
  FitnessLevel? _filter;

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
      final d = await (widget.loader ?? CommunityScreen.defaultLoader)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your progress.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final d = _data;
    if (d == null) return;
    final first = (UserSession.instance.profile?.fullName.trim().split(' ').first ?? '');
    final controller = TextEditingController(text: d.settings.displayName.isNotEmpty ? d.settings.displayName : first);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join the leaderboard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Other signed-in users will see this name, your weekly score and your workout and logging counts. Nothing else. You can leave at any time.',
                style: TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(controller: controller, maxLength: 30, decoration: const InputDecoration(labelText: 'Display name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Join')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await UserSettingsService.instance.save(d.settings.copyWith(leaderboardOptIn: true, displayName: name));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _leave() async {
    final d = _data;
    if (d == null) return;
    try {
      await UserSettingsService.instance.save(d.settings.copyWith(leaderboardOptIn: false));
      await CommunityService.instance.withdraw(d.progress.today);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _levelColor(FitnessLevel l) => l == FitnessLevel.advanced ? AppTheme.success : (l == FitnessLevel.intermediate ? AppTheme.warning : AppTheme.textSecondary);

  Widget _card({required Widget child, int index = 0}) => Reveal(
        index: index,
        child: Padding(padding: const EdgeInsets.only(bottom: 12), child: SizedBox(width: double.infinity, child: GlassCard(child: child))),
      );

  Widget _bar(String label, double? value, String detail) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
              Flexible(child: Text(detail, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value ?? 0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: const Color(0xFFDDE0F5), color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(ProgressSnapshot p) {
    final w = p.week;
    final level = p.level;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                size: 92,
                stroke: 10,
                value: w.total / 100,
                semanticLabel: 'Fitness score ${w.total.round()} out of 100',
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(w.total.round().toString(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, height: 1, letterSpacing: -0.8)),
                  const Text('/ 100', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('THIS WEEK', style: AppTheme.overline),
                    const SizedBox(height: 2),
                    const Text('Your fitness score', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textPrimary, letterSpacing: -0.3)),
                    const SizedBox(height: 8),
                    InfoChip(level.label, icon: Icons.stars_rounded, color: _levelColor(level)),
                  ],
                ),
              ),
            ],
          ),
          _bar('Workouts', w.training, w.training == null ? 'no planned day yet' : '${w.workoutsDone} of ${w.workoutsPlanned} done'),
          _bar('Food logging', w.logging, '${w.daysLogged} of ${w.daysElapsed} days'),
          _bar('Calorie target', w.adherence, w.daysLogged == 0 ? 'nothing logged' : '${w.daysOnTarget} of ${w.daysLogged} logged days within 15%'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip('${p.workoutStreak}-workout streak', icon: Icons.local_fire_department_rounded, color: AppTheme.warning),
              InfoChip('${p.loggingStreak}-day logging streak', icon: Icons.menu_book_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgesCard(ProgressSnapshot p) {
    final list = p.badges;
    final earned = list.where((b) => b.earned).length;
    return _card(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const IconWell(icon: Icons.military_tech_rounded, color: AppTheme.warning, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Text('Badges and streak', style: Theme.of(context).textTheme.titleMedium)),
            InfoChip('$earned of ${list.length}', icon: Icons.military_tech_rounded),
          ]),
          const SizedBox(height: 12),
          Text(
            p.activeStreak > 0
                ? 'You are on a ${p.activeStreak}-day streak: a workout or a logged meal every day.'
                : 'Log a workout or a meal today to start a streak.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBadgesScreen())),
            icon: const Icon(Icons.military_tech_rounded),
            label: const Text('View my badges'),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, {double size = 40, bool mine = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: mine ? AppTheme.buttonGradient : null,
        color: mine ? null : AppTheme.primaryLight,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: mine ? Colors.white : AppTheme.primary)),
    );
  }

  /// The top three as a podium (1st in the middle and tallest). It always shows ranks 1 to 3, whatever the user's own rank is.
  Widget _podium(List<LeaderboardEntry> top3, CommunityData d) {
    const medal = [Color(0xFFB7791F), Color(0xFF64748B), Color(0xFF9A5B2E)];
    Widget place(int rank, LeaderboardEntry? e, double height) {
      final mine = e != null && e.uid == d.myUid;
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (e != null) ...[
              Icon(Icons.workspace_premium_rounded, size: 26, color: medal[rank - 1], semanticLabel: 'Rank $rank'),
              const SizedBox(height: 4),
              _avatar(e.name, size: rank == 1 ? 52 : 44, mine: mine),
              const SizedBox(height: 6),
              Text(mine ? '${e.name} (you)' : e.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              Text('${e.score.round()} pts', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ],
            const SizedBox(height: 8),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [medal[rank - 1].withOpacity(e == null ? 0.12 : 0.28), medal[rank - 1].withOpacity(0.06)]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 8),
              child: Text('$rank', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: medal[rank - 1])),
            ),
          ],
        ),
      );
    }

    LeaderboardEntry? at(int i) => i < top3.length ? top3[i] : null;
    return SizedBox(
      height: 214,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [place(2, at(1), 56), place(1, at(0), 80), place(3, at(2), 40)]),
    );
  }

  Widget _leaderboardCard(CommunityData d) {
    final now = d.progress.today;
    final title = Row(children: [
      const IconWell(icon: Icons.leaderboard_rounded, color: AppTheme.warning, size: 36),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Weekly leaderboard', style: Theme.of(context).textTheme.titleMedium),
          Text('Week ${CommunityService.weekNumber(now)} · ${CommunityService.weekId(now)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ]),
      ),
      const _ResetCountdown(),
    ]);
    if (!d.settings.leaderboardOptIn) {
      return _card(
        index: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 12),
            const Text('Compare your weekly score with other Baymax users. It is optional: you choose a display name, and only that name, your score and your workout and logging counts are shared.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            GlowButton(icon: Icons.group_add_rounded, label: 'Join the leaderboard', onPressed: _join),
          ],
        ),
      );
    }

    final levels = d.cohort?.levels ?? const <String, FitnessLevel>{};
    final shown = [for (final e in d.entries) if (_filter == null || levels[e.uid] == _filter) e];
    final podium = shown.take(3).toList();
    final rest = shown.skip(3).toList();
    // the user's own row must stay visible even when they are not among the entries loaded
    final mineInList = shown.any((e) => e.uid == d.myUid);
    final myLevel = d.myUid == null ? null : levels[d.myUid];
    final showMineExtra = !mineInList && (_filter == null || myLevel == _filter);
    final mine = LeaderboardEntry(d.myUid ?? '', d.settings.displayName.isEmpty ? 'You' : d.settings.displayName, d.progress.week.total, d.progress.week.workoutsDone, d.progress.week.daysLogged);

    return _card(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in <(String, FitnessLevel?)>[('All', null), ('Beginner', FitnessLevel.beginner), ('Intermediate', FitnessLevel.intermediate), ('Advanced', FitnessLevel.advanced)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$1),
                      selected: _filter == f.$2,
                      showCheckmark: false,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.card,
                      side: BorderSide(color: _filter == f.$2 ? AppTheme.primary : AppTheme.border),
                      labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _filter == f.$2 ? Colors.white : AppTheme.textPrimary),
                      onSelected: (_) => setState(() => _filter = f.$2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (d.leaderboardError != null)
            Text(d.leaderboardError!, style: const TextStyle(color: AppTheme.error, fontSize: 13.5, fontWeight: FontWeight.w600))
          else if (shown.isEmpty && !showMineExtra)
            Text(_filter == null ? 'No one has joined this week yet.' : 'No one in this level yet.', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5))
          else ...[
            if (shown.isNotEmpty) _podium(podium, d),
            const SizedBox(height: 8),
            for (var i = 0; i < rest.length; i++) _row(i + 4, rest[i], d),
            if (showMineExtra) ...[
              if (shown.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Center(child: Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary, size: 18))),
              _row(null, mine, CommunityData(progress: d.progress, settings: d.settings, entries: d.entries, cohort: d.cohort, myUid: mine.uid)),
            ],
          ],
          if (d.cohort != null) ...[
            const SizedBox(height: 8),
            Text('Levels by ${d.cohort!.method}.', style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 8),
          const Text('Scores are calculated on each phone, so they are on trust. The ranking is a motivation tool, not a verified result.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45)),
          TextButton(onPressed: _leave, child: const Text('Leave the leaderboard')),
          const SizedBox(height: 4),
          GlowButton(icon: Icons.military_tech_rounded, label: 'View my badges', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBadgesScreen()))),
        ],
      ),
    );
  }

  /// One list row; [rank] is null for the pinned row of a user who is not among the loaded entries.
  Widget _row(int? rank, LeaderboardEntry e, CommunityData d) {
    final mine = e.uid == d.myUid;
    final level = d.cohort?.levels[e.uid];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppTheme.primaryLight : AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mine ? AppTheme.primary.withOpacity(0.6) : Colors.white, width: mine ? 1.6 : 1.2),
      ),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(rank == null ? '–' : '$rank', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textSecondary))),
          _avatar(e.name, size: 34, mine: mine),
          const SizedBox(width: 10),
          Expanded(child: Text(mine ? '${e.name} (you)' : e.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
          if (level != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(level.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _levelColor(level)))),
          Text('${e.score.round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.primary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community & progress'),
        actions: [
          IconButton(
            tooltip: 'Reminders & community settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _load()),
          ),
        ],
      ),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? MessageState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: [
                      _scoreCard(d!.progress),
                      _badgesCard(d.progress),
                      _leaderboardCard(d),
                      const Text(
                        'The score is 50% workouts completed, 25% days you logged food and 25% logged days within 15% of your calorie target. '
                        'These weights and the level thresholds (Beginner below 40, Advanced from 70) are choices made by the project team. See Profile → Sources & methodology.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.45),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// "Resets in 3d 5h": counts down to the Monday-00:00 reset, refreshed every 30 seconds.
class _ResetCountdown extends StatefulWidget {
  const _ResetCountdown();

  @override
  State<_ResetCountdown> createState() => _ResetCountdownState();
}

class _ResetCountdownState extends State<_ResetCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InfoChip(CommunityService.resetsIn(DateTime.now()), icon: Icons.timer_outlined);
}

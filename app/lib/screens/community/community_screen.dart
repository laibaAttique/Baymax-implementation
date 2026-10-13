import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/community_service.dart';
import '../../services/gamification.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/user_settings_service.dart';
import '../../theme/app_theme.dart';
import '../profile/settings_screen.dart';

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

  Widget _card({required Widget child, EdgeInsets margin = const EdgeInsets.only(bottom: 14)}) => Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _bar(String label, double? value, String detail) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
              Flexible(child: Text(detail, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: value ?? 0, minHeight: 8, backgroundColor: AppTheme.background, color: AppTheme.primary),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(w.total.round().toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppTheme.primary, height: 1)),
              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('/ 100', style: TextStyle(color: AppTheme.textSecondary))),
              const Spacer(),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _levelColor(level).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(level.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: _levelColor(level), fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Your fitness score this week', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          _bar('Workouts', w.training, w.training == null ? 'no planned day yet' : '${w.workoutsDone} of ${w.workoutsPlanned} done'),
          _bar('Food logging', w.logging, '${w.daysLogged} of ${w.daysElapsed} days'),
          _bar('Calorie target', w.adherence, w.daysLogged == 0 ? 'nothing logged' : '${w.daysOnTarget} of ${w.daysLogged} logged days within 15%'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('🔥 ${p.workoutStreak}-workout streak'),
              _chip('📒 ${p.loggingStreak}-day logging streak'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
      );

  Widget _badgesCard(ProgressSnapshot p) {
    final list = p.badges;
    final earned = list.where((b) => b.earned).length;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Badges · $earned of ${list.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final b in list)
                GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${b.title}: ${b.description}'))),
                  child: SizedBox(
                    width: 74,
                    child: Column(
                      children: [
                        Opacity(
                          opacity: b.earned ? 1 : 0.3,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle, border: Border.all(color: b.earned ? AppTheme.primary : AppTheme.border, width: 2)),
                            alignment: Alignment.center,
                            child: Text(b.emoji, style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(b.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: b.earned ? AppTheme.textPrimary : AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderboardCard(CommunityData d) {
    final title = Text('Weekly leaderboard · ${CommunityService.weekId(d.progress.today)}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary));
    if (!d.settings.leaderboardOptIn) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 8),
            const Text('Compare your weekly score with other Baymax users. It is optional: you choose a display name, and only that name, your score and your workout and logging counts are shared.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _join, child: const Text('Join the leaderboard')),
          ],
        ),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 8),
          if (d.leaderboardError != null)
            Text(d.leaderboardError!, style: const TextStyle(color: AppTheme.error, fontSize: 13))
          else if (d.entries.isEmpty)
            const Text('No one has joined this week yet.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))
          else
            for (var i = 0; i < d.entries.length; i++) _row(i + 1, d.entries[i], d),
          if (d.cohort != null) ...[
            const SizedBox(height: 8),
            Text('Levels by ${d.cohort!.method}.', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 6),
          const Text('Scores are calculated on each phone, so they are on trust. The ranking is a motivation tool, not a verified result.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
          TextButton(onPressed: _leave, child: const Text('Leave the leaderboard')),
        ],
      ),
    );
  }

  Widget _row(int rank, LeaderboardEntry e, CommunityData d) {
    final mine = e.uid == d.myUid;
    final level = d.cohort?.levels[e.uid];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: mine ? AppTheme.primaryLight : AppTheme.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(rank <= 3 ? const ['🥇', '🥈', '🥉'][rank - 1] : '$rank', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(mine ? '${e.name} (you)' : e.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
          if (level != null)
            Padding(padding: const EdgeInsets.only(right: 8), child: Text(level.label, style: TextStyle(fontSize: 11, color: _levelColor(level)))),
          Text('${e.score.round()}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community & progress', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Reminders & community settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _load()),
          ),
        ],
      ),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _scoreCard(d!.progress),
                      _badgesCard(d.progress),
                      _leaderboardCard(d),
                      const Text(
                        'The score is 50% workouts completed, 25% days you logged food and 25% logged days within 15% of your calorie target. '
                        'These weights and the level thresholds (Beginner below 40, Advanced from 70) are choices made by the project team. See Profile → Sources & methodology.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
    );
  }
}

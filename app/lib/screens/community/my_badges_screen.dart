import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/community_service.dart';
import '../../services/gamification.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/xp_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

class MyBadgesData {
  final ProgressSnapshot progress;
  final XpSnapshot xp;
  const MyBadgesData(this.progress, this.xp);
}

/// Module 12 (FR-6 to FR-9, mockup M33): XP and level, the active streak, badges earned (newest first, with the week earned) and
/// badges still locked, each with what unlocks it.
class MyBadgesScreen extends StatefulWidget {
  final Future<MyBadgesData> Function()? loader;
  const MyBadgesScreen({Key? key, this.loader}) : super(key: key);

  static Future<MyBadgesData> defaultLoader() async {
    final plan = UserSession.instance.plan;
    if (plan == null) throw const ApiException('Complete your health profile first.');
    final progress = await ProgressService.instance.load(plan);
    XpSnapshot xp;
    try {
      xp = await XpService.instance.load();
    } catch (_) {
      xp = XpSnapshot(badges: progress.earned.length);
    }
    return MyBadgesData(progress, xp);
  }

  @override
  State<MyBadgesScreen> createState() => _MyBadgesScreenState();
}

class _MyBadgesScreenState extends State<MyBadgesScreen> {
  MyBadgesData? _data;
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
      final d = await (widget.loader ?? MyBadgesScreen.defaultLoader)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your badges.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// "Week 42" for the week a badge was earned (the stored time, or today for a badge earned in this very load).
  String _weekEarned(AppBadge b, ProgressSnapshot p) {
    final ms = p.earnedAt[b.id];
    final when = ms == null || ms == 0 ? p.today : DateTime.fromMillisecondsSinceEpoch(ms);
    return 'Week ${CommunityService.weekNumber(when)}';
  }

  Widget _xpCard(XpSnapshot x) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 14, opacity: 0.32, offset: const Offset(0, 5))),
              alignment: Alignment.center,
              child: Text('${x.level}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LEVEL', style: AppTheme.overline),
                Text('Level ${x.level}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
                Text('${x.xp} XP in total', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: x.progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 10, backgroundColor: const Color(0xFFDDE0F5), color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text('${x.toNext} XP to reach level ${x.level + 1}', style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('You earn 50 XP for each day you complete a workout, 10 XP for each day you log food and 100 XP for each badge.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45)),
        ],
      ),
    );
  }

  Widget _streakCard(ProgressSnapshot p) {
    final n = p.activeStreak;
    final String message;
    if (n == 0) {
      message = 'Log a workout or a meal today to start a streak.';
    } else if (n < 7) {
      message = '${7 - n} more ${7 - n == 1 ? 'day' : 'days'} for the 7-Day Streak badge. Keep it up!';
    } else if (n < 30) {
      message = '${30 - n} more ${30 - n == 1 ? 'day' : 'days'} for the 30-Day Streak badge. Keep it up!';
    } else {
      message = 'Both streak badges are yours. Keep the streak alive.';
    }
    return GlassCard(
      tint: AppTheme.tint(AppTheme.warning, 0.14),
      child: Row(children: [
        const IconWell(icon: Icons.local_fire_department_rounded, color: AppTheme.warning, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n == 0 ? 'No active streak' : '$n-Day Streak!', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(message, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  Widget _earnedBadge(AppBadge b, ProgressSnapshot p) {
    return Pressable(
      radius: 14,
      semanticLabel: '${b.title}, earned ${_weekEarned(b, p)}. ${b.description}',
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${b.title}: ${b.description}'))),
      child: SizedBox(
        width: 96,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle, boxShadow: AppTheme.glowShadow(blur: 14, opacity: 0.32, offset: const Offset(0, 5))),
              alignment: Alignment.center,
              child: Icon(AppIcons.badge(b.id), size: 28, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(b.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            Text(_weekEarned(b, p), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _lockedBadge(AppBadge b) {
    return Semantics(
      label: '${b.title}, locked. To unlock: ${b.description}',
      child: SizedBox(
        width: 96,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(color: Color(0xFFE3E6F6), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_outline_rounded, size: 26, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(b.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w800, color: AppTheme.textSecondary)),
            // what unlocks it, so the user knows what to aim for next (Module 12 FR-9)
            Text(b.description, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, height: 1.25, color: AppTheme.textSecondary)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('My badges')),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? MessageState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: _content(d!),
                  ),
                ),
    );
  }

  List<Widget> _content(MyBadgesData d) {
    final all = d.progress.badges;
    // newest first: the stored time when there is one, then badges earned only just now
    final earned = all.where((b) => b.earned).toList()
      ..sort((a, b) => (d.progress.earnedAt[b.id] ?? 1 << 50).compareTo(d.progress.earnedAt[a.id] ?? 1 << 50));
    final locked = all.where((b) => !b.earned).toList();
    return [
      Reveal(child: _xpCard(d.xp)),
      const SizedBox(height: 12),
      Reveal(index: 1, child: _streakCard(d.progress)),
      SectionHeader('Earned (${earned.length})', padding: const EdgeInsets.fromLTRB(0, 22, 0, 8)),
      if (earned.isEmpty)
        const Text('You have not earned a badge yet. Your first workout or a few days of logging will get you started.', style: TextStyle(color: AppTheme.textSecondary, height: 1.45))
      else
        Wrap(spacing: 4, runSpacing: 6, children: [for (final b in earned) _earnedBadge(b, d.progress)]),
      SectionHeader('Locked (${locked.length})', padding: const EdgeInsets.fromLTRB(0, 22, 0, 8)),
      if (locked.isEmpty)
        const Text('Every badge is yours.', style: TextStyle(color: AppTheme.textSecondary))
      else
        Wrap(spacing: 4, runSpacing: 6, children: [for (final b in locked) _lockedBadge(b)]),
    ];
  }
}

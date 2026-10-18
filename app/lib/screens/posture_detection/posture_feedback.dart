import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../services/workout_session/workout_session_controller.dart';
import '../../theme/app_theme.dart';
import '../dashboard/main_navigation.dart';

/// S-15: session summary (Module 5, FR-12). Everything shown comes from the
/// [SessionSummary] recorded when the session ended.
class PostureFeedbackScreen extends StatefulWidget {
  final SessionSummary summary;

  /// Source of the save status; defaults to the shared session controller.
  final WorkoutSessionController? session;
  const PostureFeedbackScreen({super.key, required this.summary, this.session});

  @override
  State<PostureFeedbackScreen> createState() => _PostureFeedbackScreenState();
}

class _PostureFeedbackScreenState extends State<PostureFeedbackScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  SessionSummary get _summary => widget.summary;
  WorkoutSessionController get _session => widget.session ?? WorkoutSessionController.instance;

  Widget _buildSaveStatus() {
    // Only the session that just finished has a live save status.
    if (!identical(_session.lastSummary, _summary) || _session.store == null) return const SizedBox.shrink();
    return ValueListenableBuilder<SaveState>(
      valueListenable: _session.saveState,
      builder: (context, state, _) {
        switch (state) {
          case SaveState.idle:
            return const SizedBox.shrink();
          case SaveState.saving:
            return _buildNotice('☁️', 'Saving to your workout history…');
          case SaveState.saved:
            return _buildNotice('✅', 'Saved to your workout history.');
          case SaveState.failed:
            return Column(
              children: [
                _buildNotice('⚠️', 'Not saved: ${_session.saveError ?? 'unknown error'}'),
                TextButton(onPressed: _session.retrySave, child: const Text('Try saving again')),
              ],
            );
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _animation = Tween<double>(begin: 0, end: (_summary.postureScore ?? 0) / 100)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _duration {
    final d = _summary.duration;
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String get _completedLabel {
    final s = _summary;
    if (s.skipped) return 'Exercise skipped';
    if (s.exercise.timed) return 'Completed ${s.setsCompleted} of ${s.exercise.sets} sets';
    final reps = '${s.reps} rep${s.reps == 1 ? '' : 's'}';
    return s.postureAnalysed ? 'Completed $reps' : 'Confirmed $reps';
  }

  Widget _buildStatCard(String val, String lbl) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(lbl, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackItem(FormFeedbackItem item) {
    final Color color;
    final IconData icon;
    switch (item.verdict) {
      case FeedbackVerdict.passed:
        color = AppTheme.success;
        icon = Icons.check;
      case FeedbackVerdict.failed:
        color = AppTheme.error;
        icon = Icons.close;
      case FeedbackVerdict.notAssessed:
        color = AppTheme.textSecondary;
        icon = Icons.remove;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item.text, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildScore() {
    final score = _summary.postureScore;
    if (!_summary.postureAnalysed) {
      return _buildNoScore(Icons.accessibility_new, 'Posture not analysed',
          'This was a Manual Guidance session, so there is no posture score.');
    }
    if (score == null) {
      return _buildNoScore(Icons.hourglass_empty, 'Not enough data',
          'No complete repetition was detected, so a posture score could not be calculated.');
    }
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) => CircularProgressIndicator(
                    value: _animation.value,
                    strokeWidth: 10,
                    backgroundColor: AppTheme.border,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) => Text('${(_animation.value * 100).round()}%',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ),
            ],
          ),
        ),
        Text(
          _summary.formScored ? 'Posture Score' : (_summary.formChecked ? 'Posture Score (experimental)' : 'Range Score'),
          key: const ValueKey('score-label'),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildNoScore(IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.border, width: 10)),
            alignment: Alignment.center,
            child: Icon(icon, size: 40, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildNotice(String emoji, String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final accuracy = s.accuracy;
    final fps = s.averageFps;

    return Scaffold(
      appBar: AppBar(title: const Text('Session Summary', style: TextStyle(fontSize: 16)), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                children: [
                  Text(s.skipped ? 'Session Ended' : 'Session Complete! 🎉',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    s.skipped ? '${s.exercise.name} was skipped' : 'Great job finishing ${s.exercise.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            _buildScore(),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
              child: Text('${s.skipped ? '⏭️' : '✅'} $_completedLabel',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  s.holdSeconds != null
                      ? _buildStatCard('${s.holdSeconds} s', 'Held')
                      : _buildStatCard('${s.reps}', s.postureAnalysed ? 'Total Reps' : 'Reps (confirmed)'),
                  _buildStatCard(_duration, 'Duration'),
                  _buildStatCard(accuracy == null ? '—' : '$accuracy%', 'Accuracy'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Form Feedback',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  if (s.postureAnalysed)
                    for (final item in s.feedback) _buildFeedbackItem(item)
                  else
                    _buildFeedbackItem(const FormFeedbackItem(
                      id: 'manual',
                      verdict: FeedbackVerdict.notAssessed,
                      text: 'Form was not assessed. Use Camera Detection for form feedback.',
                    )),
                  if (s.partialReps > 0)
                    _buildFeedbackItem(FormFeedbackItem(
                      id: 'partial',
                      verdict: FeedbackVerdict.notAssessed,
                      text: '${s.partialReps} shallow attempt${s.partialReps == 1 ? ' was' : 's were'} not counted as reps',
                    )),
                  if (s.tooDifficult)
                    _buildFeedbackItem(const FormFeedbackItem(
                      id: 'difficulty',
                      verdict: FeedbackVerdict.notAssessed,
                      text: 'You marked this exercise as too difficult',
                    )),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (s.postureAnalysed)
              _buildNotice('ℹ️',
                  'The posture score is the share of your attempted reps done with acceptable form. It is software-generated fitness feedback, not a medical assessment.'),
            _buildSaveStatus(),
            _buildNotice('🛡️', 'An injury-risk update is not shown because the Injury Risk module is not connected yet.'),
            if (fps != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Pose processing averaged ${fps.toStringAsFixed(1)} FPS on this device',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 2)), // 2 = Workout tab
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                child: const Text('Back to Workout Plan'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 3)), // 3 = Analytics tab
                    (route) => false,
                  );
                },
                child: const Text('View Analytics →', style: TextStyle(color: AppTheme.primary, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

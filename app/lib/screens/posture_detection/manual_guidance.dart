import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/plan.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/progress_ring.dart';
import '../workout_and_exercise/workout_plan.dart';
import 'posture_feedback.dart';
import 'session_queue.dart';

/// A guided session through the user's own exercises: the technique cues, a countdown for timed exercises or a set counter for
/// rep-based ones, and Done / Skip / Too difficult. Everything shown comes from the plan; nothing is simulated.
class ManualGuidance extends StatefulWidget {
  final List<PlannedExercise> queue;
  final int startIndex;
  const ManualGuidance({Key? key, required this.queue, this.startIndex = 0}) : super(key: key);

  @override
  State<ManualGuidance> createState() => _ManualGuidanceState();
}

class _ManualGuidanceState extends State<ManualGuidance> {
  late int _index = widget.startIndex.clamp(0, widget.queue.length - 1);
  final Stopwatch _session = Stopwatch()..start();
  Timer? _ticker;

  int _completed = 0;
  int _skipped = 0;
  int _setsDone = 0;

  // per-exercise state
  int _setsThisExercise = 0;
  int _secondsLeft = 0;
  bool _running = false;

  PlannedExercise get _current => widget.queue[_index];
  bool get _isLast => _index == widget.queue.length - 1;

  @override
  void initState() {
    super.initState();
    _resetExercise();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _resetExercise() {
    _ticker?.cancel();
    _running = false;
    _setsThisExercise = 0;
    _secondsLeft = _current.timed ? _current.seconds : 0;
  }

  void _toggleTimer() {
    HapticFeedback.selectionClick();
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_secondsLeft <= 0) _secondsLeft = _current.seconds;
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _secondsLeft = 0;
          _running = false;
          _setsThisExercise++;
          _setsDone++;
          if (_setsThisExercise < _current.sets) _secondsLeft = _current.seconds; // ready for the next set
        });
      }
    });
  }

  void _setDone() {
    HapticFeedback.selectionClick();
    if (_setsThisExercise >= _current.sets) return;
    setState(() {
      _setsThisExercise++;
      _setsDone++;
    });
  }

  void _undoSet() {
    if (_setsThisExercise == 0) return;
    setState(() {
      _setsThisExercise--;
      _setsDone--;
    });
  }

  void _advance({required bool skipped}) {
    _ticker?.cancel();
    if (skipped) {
      _skipped++;
    } else {
      _completed++;
    }
    if (_isLast) {
      _session.stop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PostureFeedbackScreen(
            result: SessionResult(total: widget.queue.length, completed: _completed, skipped: _skipped, setsDone: _setsDone, elapsed: _session.elapsed),
          ),
        ),
      );
      return;
    }
    setState(() {
      _index++;
      _resetExercise();
    });
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this session?'),
        content: const Text('Your progress in this guided session will not be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _counterCard(PlannedExercise p) {
    final done = _setsThisExercise >= p.sets;
    if (p.timed) {
      final frac = p.seconds == 0 ? 0.0 : 1 - (_secondsLeft / p.seconds);
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            ProgressRing(
              size: 118,
              stroke: 11,
              value: done ? 1 : frac,
              semanticLabel: '${_mmss(_secondsLeft)} remaining',
              child: Text(done ? 'Done' : _mmss(_secondsLeft), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.6)),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SET', style: AppTheme.overline),
                  Text('${(_setsThisExercise + 1).clamp(1, p.sets)} of ${p.sets}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
                  const SizedBox(height: 4),
                  Text('${p.seconds >= 120 ? '${(p.seconds / 60).round()} min' : '${p.seconds}s'} per set${p.restSeconds > 0 && p.sets > 1 ? ' · rest ${p.restSeconds}s' : ''}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  if (!done)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: _toggleTimer,
                      icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      label: Text(_running ? 'Pause' : (_secondsLeft == p.seconds ? 'Start' : 'Resume')),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          ProgressRing(
            size: 118,
            stroke: 11,
            value: p.sets == 0 ? 0 : _setsThisExercise / p.sets,
            semanticLabel: '$_setsThisExercise of ${p.sets} sets done',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$_setsThisExercise', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, height: 1, letterSpacing: -0.8)),
              Text('of ${p.sets} sets', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TARGET', style: AppTheme.overline),
                Text('${p.reps} reps', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.4)),
                if (p.restSeconds > 0 && p.sets > 1)
                  Text('Rest ${p.restSeconds}s between sets', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: done ? null : _setDone,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Set done'),
                    ),
                  ),
                  IconButton(onPressed: _setsThisExercise == 0 ? null : _undoSet, icon: const Icon(Icons.undo_rounded), tooltip: 'Undo last set'),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _current;
    final e = p.exercise;
    final n = widget.queue.length;
    final allSetsDone = _setsThisExercise >= p.sets;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'End session', onPressed: _confirmExit),
          title: Text('Exercise ${_index + 1} of $n'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (_index) / n),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: Column(
                  key: ValueKey(_index),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: BorderRadius.circular(AppTheme.rHero),
                        boxShadow: AppTheme.glowShadow(blur: 28, opacity: 0.3, offset: const Offset(0, 12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.4)),
                            child: Icon(AppIcons.exercise(e.group), size: 36, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5, height: 1.15)),
                                const SizedBox(height: 6),
                                Text(e.muscles.take(3).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.88), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _counterCard(p),
                  ],
                ),
              ),
              const SectionHeader('How to do it', padding: EdgeInsets.fromLTRB(0, 24, 0, 10)),
              for (var i = 0; i < e.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    radius: AppTheme.rMedium,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(gradient: AppTheme.buttonGradient, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(e.steps[i], style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500)))),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              GlowButton(
                icon: _isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
                label: _isLast ? 'Finish session' : (allSetsDone ? 'Done — next exercise' : 'Mark done and continue'),
                onPressed: () => _advance(skipped: false),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => _advance(skipped: true), child: const Text('Skip'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Make it easier'),
                          content: const Text(
                            'Do fewer repetitions, rest longer, or choose an easier version (for example a wall push-up instead of a floor push-up). '
                            'Stop if anything hurts. You can also regenerate your plan from the Workout tab.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutPlan()));
                              },
                              child: const Text('Open my workout plan'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Too difficult'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Stop if you feel sharp pain, dizziness or chest discomfort.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45)),
            ],
          ),
        ),
      ),
    );
  }
}

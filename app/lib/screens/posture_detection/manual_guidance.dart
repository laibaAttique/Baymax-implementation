import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../services/workout_session/workout_session_controller.dart';
import '../../theme/app_theme.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import 'posture_feedback.dart';

/// S-14: guided exercise without the camera (Module 5, FR-10 / FR-11).
///
/// Nothing here is measured by the app: sets and reps are what the user
/// confirms, and no posture score is produced.
class ManualGuidance extends StatefulWidget {
  final WorkoutSessionRequest request;
  const ManualGuidance({super.key, required this.request});

  @override
  State<ManualGuidance> createState() => _ManualGuidanceState();
}

class _ManualGuidanceState extends State<ManualGuidance> with SingleTickerProviderStateMixin {
  final WorkoutSessionController _session = WorkoutSessionController.instance;
  late final AnimationController _float;
  Timer? _ticker;

  /// Form cues ticked off in the current set.
  final Set<int> _done = {};

  /// Seconds left of the rest between sets; 0 when not resting.
  int _restLeft = 0;

  /// Seconds left of the current hold, for timed exercises.
  int _holdLeft = 0;
  bool _leaving = false;

  SessionExercise get _exercise => widget.request.exercise;
  bool get _resting => _restLeft > 0;
  bool get _paused => _session.status == SessionStatus.paused;
  bool get _allSetsDone => _session.setsCompleted >= _exercise.sets;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    // The timer starts as soon as the screen opens (report FR17.1).
    _session.start(widget.request, SessionMode.manual);
    _session.addListener(_onSessionChanged);
    _holdLeft = _exercise.timed ? _exercise.seconds : 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _float.dispose();
    _session.removeListener(_onSessionChanged);
    if (!_leaving) _session.abandon();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _session.status != SessionStatus.active) return;
    setState(() {
      if (_resting) {
        _restLeft--;
        if (_restLeft == 0 && _exercise.timed) _holdLeft = _exercise.seconds;
      } else if (_exercise.timed && !_allSetsDone && _holdLeft > 0) {
        _holdLeft--;
        if (_holdLeft == 0) _completeSet();
      }
    });
  }

  void _onSessionChanged() {
    if (!mounted || _leaving) return;
    if (_session.finishRequested) {
      _finish();
      return;
    }
    _paused ? _float.stop() : _float.repeat(reverse: true);
    setState(() {});
  }

  /// The user confirms one set of the prescribed reps (report FR17.2).
  void _completeSet() {
    if (_allSetsDone || _resting) return;
    _session.recordManualSet(_exercise.reps);
    _done.clear();
    if (_allSetsDone) {
      _finish();
    } else {
      _restLeft = _exercise.restSeconds;
      if (_restLeft == 0 && _exercise.timed) _holdLeft = _exercise.seconds;
    }
  }

  /// Saves the session, then moves on: to the next exercise when the workout
  /// supplied one and [advance] is set, otherwise to the summary.
  void _finish({bool skipped = false, bool tooDifficult = false, bool advance = false}) {
    if (_leaving) return;
    _leaving = true;
    final summary = _session.finish(skipped: skipped, tooDifficult: tooDifficult);
    final next = widget.request.next;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    navigator.popUntil((r) => r == route || r.isFirst);
    navigator.pushReplacement(MaterialPageRoute(
      builder: (_) => advance && next != null ? ManualGuidance(request: next) : PostureFeedbackScreen(summary: summary),
    ));
  }

  static String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _buildFormCue(int index, String text) {
    final done = _done.contains(index);
    final firstPending = List.generate(_exercise.steps.length, (i) => i).where((i) => !_done.contains(i));
    final active = !done && firstPending.isNotEmpty && firstPending.first == index;
    return GestureDetector(
      onTap: () => setState(() => done ? _done.remove(index) : _done.add(index)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppTheme.primary : Colors.transparent, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: done ? AppTheme.success : (active ? AppTheme.primaryLight : AppTheme.border),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text('${index + 1}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: active ? AppTheme.primary : AppTheme.textSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4))),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterCard(String label, String value, {String? suffix, String? note}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  children: [
                    TextSpan(text: value),
                    if (suffix != null)
                      TextSpan(text: suffix, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _exercise;
    final currentSet = (_session.setsCompleted + 1).clamp(1, e.sets);
    final hasNext = widget.request.next != null;

    final String timeNote;
    if (_paused) {
      timeNote = 'Paused';
    } else if (_resting) {
      timeNote = 'Rest ${_clock(_restLeft)}';
    } else if (e.timed) {
      timeNote = 'Hold ${_clock(_holdLeft)}';
    } else {
      timeNote = 'Elapsed';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Guidance', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Ask Baymax',
            icon: const Icon(Icons.mic_none),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              height: 200,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1C2B3A), Color(0xFF0F1923)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: _float,
                builder: (_, child) => Transform.translate(offset: Offset(0, -10 * _float.value), child: child),
                child: Text(e.icon, style: const TextStyle(fontSize: 92)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  ),
                  if (e.group.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration:
                          BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(20)),
                      child: Text(e.group.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Target: ${e.targetLabel}${e.restSeconds > 0 ? ' · ${e.restSeconds}s rest' : ''}'
                '${e.muscles.isEmpty ? '' : '\nWorks: ${e.muscles.join(', ')}'}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  _buildCounterCard('TIME', _clock(_session.elapsed.inSeconds), note: timeNote),
                  const SizedBox(width: 10),
                  e.timed
                      ? _buildCounterCard('SETS', '${_session.setsCompleted}', suffix: ' /${e.sets}', note: 'confirmed')
                      : _buildCounterCard('REPS', '${_session.reps}',
                          suffix: ' /${e.targetReps}', note: 'Set $currentSet of ${e.sets}'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: OutlinedButton.icon(
                onPressed: () => _paused ? _session.resume() : _session.pause(),
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused ? 'Resume' : 'Pause'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text('Proper Form',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Tap each cue as you check it during the set.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: e.steps.isEmpty
                  ? const Text('No technique steps are available for this exercise.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))
                  : Column(children: [for (var i = 0; i < e.steps.length; i++) _buildFormCue(i, e.steps[i])]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🛡️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Move with control and breathe steadily. Stop if you feel sharp pain, dizziness or chest discomfort.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text("How's it feeling?",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _resting || _paused || _allSetsDone ? null : () => setState(_completeSet),
                    child: Text(_resting ? 'Resting… ${_clock(_restLeft)}' : 'Completed ✓'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _finish(skipped: true),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary, side: const BorderSide(color: AppTheme.border)),
                          child: const Text('Skip'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _finish(tooDifficult: true),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary, side: const BorderSide(color: AppTheme.border)),
                          child: const Text('Too Difficult'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => _finish(advance: true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                child: Text(hasNext ? 'Next Exercise →' : 'Finish Session →', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

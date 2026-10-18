import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../services/posture/exercise_form_rules.dart';
import '../../services/posture/movement_patterns.dart';
import '../../services/posture/pose_landmark.dart';
import '../../services/posture/pose_stream.dart';
import '../../services/posture/posture_engine.dart';
import '../../services/voice/posture_cue_announcer.dart';
import '../../services/voice/speech_output.dart';
import '../../services/workout_session/workout_session_controller.dart';
import '../../theme/app_theme.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import 'posture_feedback.dart';
import 'widgets/pose_overlay_painter.dart';

enum _CameraPhase { starting, running, paused, failed }

class _FrameView {
  final PoseFrame frame;
  final PostureAnalysis analysis;
  const _FrameView(this.frame, this.analysis);
}

/// S-13: live camera posture detection for one exercise.
///
/// The screen owns the camera lifecycle and wires
/// camera → pose model → [PostureEngine] → [WorkoutSessionController].
/// It must only be opened after the user has consented and granted the camera
/// permission (see `PostureModeSelection`).
class CameraDetection extends StatefulWidget {
  final WorkoutSessionRequest request;

  /// Override the pose source and speech output in tests.
  final PoseStream? poseStream;
  final SpeechOutput? speechOutput;

  const CameraDetection({super.key, required this.request, this.poseStream, this.speechOutput});

  @override
  State<CameraDetection> createState() => _CameraDetectionState();
}

class _CameraDetectionState extends State<CameraDetection> with WidgetsBindingObserver {
  final WorkoutSessionController _session = WorkoutSessionController.instance;
  final ValueNotifier<_FrameView?> _view = ValueNotifier<_FrameView?>(null);

  late final ExercisePostureConfig _support;
  late final ExerciseFormConfig _config;
  late final PostureEngine _engine;
  late final PoseStream _stream;
  late final PostureCueAnnouncer _cues;

  StreamSubscription<PoseFrame>? _frames;
  Timer? _ticker;
  _CameraPhase _phase = _CameraPhase.starting;
  String? _error;
  bool _stopping = false;
  bool _cameraBusy = false;

  @override
  void initState() {
    super.initState();
    // The tracker comes from the exercise's movement pattern (Module 4 hands over id + pattern).
    _support = MovementPatterns.forSession(widget.request.exercise);
    final config = _support.form;
    if (config == null) {
      throw ArgumentError('Camera detection cannot track "${widget.request.exercise.id}": ${_support.unsupportedReason}');
    }
    _config = config;
    _engine = PostureEngine(config);
    _stream = widget.poseStream ?? CameraPoseStream();
    _cues = PostureCueAnnouncer(session: _session, output: widget.speechOutput ?? DeviceSpeechOutput.instance)
      ..attach();

    WidgetsBinding.instance.addObserver(this);
    _session.start(widget.request, SessionMode.camera,
        formScored: _support.scoreValidated, formChecked: _support.supportsFormEvaluation);
    _session.addListener(_onSessionChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _session.status == SessionStatus.active) setState(() {});
    });
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _ticker?.cancel();
    _cues.detach();
    _frames?.cancel();
    // Always release the camera and model, however the screen is left.
    unawaited(_stream.stop());
    if (!_stopping) _session.abandon();
    _view.dispose();
    super.dispose();
  }

  /// Release the camera whenever the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _CameraPhase.running) _pause();
  }

  Future<void> _startCamera() async {
    if (_cameraBusy) return;
    _cameraBusy = true;
    setState(() {
      _phase = _CameraPhase.starting;
      _error = null;
    });
    try {
      await _stream.start();
      if (!mounted) return;
      _frames = _stream.frames.listen(_onFrame);
      setState(() => _phase = _CameraPhase.running);
    } on PoseStreamException catch (e) {
      if (mounted) _fail(e.message);
    } catch (_) {
      if (mounted) _fail('The camera could not be started.');
    } finally {
      _cameraBusy = false;
    }
  }

  void _fail(String message) {
    setState(() {
      _phase = _CameraPhase.failed;
      _error = message;
    });
  }

  Future<void> _releaseCamera() async {
    // Cancelling stops delivery immediately; there is nothing to wait for.
    unawaited(_frames?.cancel());
    _frames = null;
    await _stream.stop();
    _view.value = null;
  }

  void _onFrame(PoseFrame frame) {
    if (_session.status != SessionStatus.active || _stopping) return;
    final analysis = _engine.process(frame);
    _session.updatePosture(analysis, angleLabel: _config.primaryJoint);
    _view.value = _FrameView(frame, analysis);
    if (kDebugMode) _debugLog(frame, analysis);
  }

  int _lastDebugLogMs = 0;

  /// Debug builds only: angles, timings and rep events in the device log
  /// (`adb logcat -s flutter`), used to tune the thresholds in
  /// `exercise_form_rules.dart` against real movements. Only numbers are
  /// logged — never images.
  void _debugLog(PoseFrame frame, PostureAnalysis a) {
    final m = a.measurements;
    final event = a.repEvent;
    if (event != null) {
      debugPrint('[pose] ${event.counted ? 'REP ${a.reps}' : 'PARTIAL ${a.partialReps}'} '
          'min=${event.minAngle.toStringAsFixed(1)} dur=${event.durationMs}ms score=${a.postureScore}');
    }
    if (frame.timestampMs - _lastDebugLogMs < 500) return;
    _lastDebugLogMs = frame.timestampMs;
    debugPrint('[pose] fps=${_stream.fps.value.toStringAsFixed(1)} infer=${frame.inferenceMs}ms convert=${frame.convertMs}ms '
        'pose=${frame.hasPose} world=${frame.hasWorld} phase=${a.phase.name} '
        '${_config.primaryJoint.toLowerCase()}=${m?.primaryAngle.toStringAsFixed(1)} '
        'L=${m?.leftPrimary?.toStringAsFixed(1)} R=${m?.rightPrimary?.toStringAsFixed(1)} '
        'torso=${m?.torsoLean?.toStringAsFixed(1)} line=${m?.bodyLine?.toStringAsFixed(1)} '
        'facing=${m?.facingCamera} knees=${m?.kneeToAnkleRatio?.toStringAsFixed(2)} '
        'warn=${a.feedback.isWarning ? a.feedback.message : '-'}');
  }

  Future<void> _pause() async {
    _session.pause();
    if (_phase != _CameraPhase.running) return;
    setState(() => _phase = _CameraPhase.paused);
    await _releaseCamera();
  }

  Future<void> _resume() async {
    _session.resume();
    if (_phase == _CameraPhase.paused) await _startCamera();
  }

  /// Reacts to changes made elsewhere (the voice assistant can pause, resume
  /// and ask to end the session).
  void _onSessionChanged() {
    if (!mounted || _stopping) return;
    if (_session.finishRequested) {
      _stop();
      return;
    }
    if (_session.status == SessionStatus.paused && _phase == _CameraPhase.running) {
      _pause();
    } else if (_session.status == SessionStatus.active && _phase == _CameraPhase.paused) {
      _startCamera();
    }
    setState(() {});
  }

  /// Ends the session: release the camera, save the statistics, then show the
  /// summary (report FR16.5).
  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    final fps = _stream.averageFps;
    await _releaseCamera();
    final e = widget.request.exercise;
    final summary = _session.finish(
      report: _engine.buildReport(
        targetSeconds: e.timed ? e.sets * e.seconds : null,
        movement: _support.movementPattern.measures.isEmpty ? 'movement' : _support.movementPattern.measures,
      ),
      averageFps: fps,
      formScored: _support.scoreValidated,
      formChecked: _support.supportsFormEvaluation,
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    // The voice assistant may be open on top of this screen.
    navigator.popUntil((r) => r == route || r.isFirst);
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => PostureFeedbackScreen(summary: summary)));
  }

  void _openAssistant() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceAssistantScreen()));
  }

  static String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String get _elapsed {
    final d = _session.elapsed;
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tracking = _phase == _CameraPhase.running && _session.landmarksDetected;
    final score = _session.postureScore;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Baymax', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'switch') _stream.switchCamera().then((_) => mounted ? setState(() {}) : null);
              if (value == 'cues') setState(() => _cues.enabled = !_cues.enabled);
              if (value == 'assistant') _openAssistant();
            },
            itemBuilder: (_) => [
              if (_stream.canSwitchCamera && _phase == _CameraPhase.running)
                const PopupMenuItem(value: 'switch', child: Text('Switch camera')),
              PopupMenuItem(value: 'cues', child: Text(_cues.enabled ? 'Mute voice cues' : 'Unmute voice cues')),
              const PopupMenuItem(value: 'assistant', child: Text('Ask Baymax (voice)')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildViewfinder(context),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Column(
                children: [
                  Text(
                    tracking && _session.anglesCalculated ? widget.request.exercise.name : _config.setupHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  const Text('Camera Detection',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  if (!_support.scoreValidated)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        key: ValueKey(_support.isExperimental ? 'experimental-label' : 'basic-tracking-label'),
                        _support.isExperimental
                            ? 'Experimental: ${_support.checkLabels.join(', ').toLowerCase()} checked live. '
                                'The score is a guide until these checks are tested on real users.'
                            : 'No posture check is measurable for this exercise: the score reflects movement range only.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _buildStatusLine(tracking),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildDetectionChip('Landmarks detected', tracking),
                  _buildDetectionChip('Angles calculated', tracking && _session.anglesCalculated),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStat(_elapsed, 'Time'),
                  if (_support.supportsHoldTiming) ...[
                    _buildStat(_clock(_session.holdSeconds ?? 0), 'In position'),
                    _buildStat(score == null ? '—' : '$score%', _support.scoreLabel),
                  ] else ...[
                    _buildStat(score == null ? '—' : '$score%', _support.scoreLabel),
                    _buildStat('${_session.partialReps}', 'Too shallow'),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _phase == _CameraPhase.running
                          ? _pause
                          : (_phase == _CameraPhase.paused ? _resume : null),
                      child: Text(_phase == _CameraPhase.paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _stopping ? null : _stop,
                      child: const Text('Stop Session'),
                    ),
                  ),
                ],
              ),
            ),
            const Text('Processing is done locally. No video is stored.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLine(bool tracking) {
    final String text;
    switch (_phase) {
      case _CameraPhase.starting:
        text = 'Starting camera...';
      case _CameraPhase.paused:
        text = 'Paused';
      case _CameraPhase.failed:
        text = 'Camera unavailable';
      case _CameraPhase.running:
        text = tracking ? 'Detecting posture...' : 'Looking for your body...';
    }
    final busy = _phase == _CameraPhase.starting || _phase == _CameraPhase.running;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
        if (busy) const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildViewfinder(BuildContext context) {
    final height = (MediaQuery.of(context).size.height * 0.46).clamp(300.0, 520.0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_phase == _CameraPhase.running) _buildPreviewWithSkeleton(),
          if (_phase != _CameraPhase.running) _buildPlaceholder(),
          Positioned(top: 16, left: 16, child: _buildCorner(true, true)),
          Positioned(top: 16, right: 16, child: _buildCorner(true, false)),
          Positioned(bottom: 16, left: 16, child: _buildCorner(false, true)),
          Positioned(bottom: 16, right: 16, child: _buildCorner(false, false)),
          Positioned(top: 16, right: 16, child: _buildRepsBadge()),
          if (_phase == _CameraPhase.running)
            Positioned(
              top: 20,
              left: 24,
              child: ValueListenableBuilder<double>(
                valueListenable: _stream.fps,
                builder: (_, fps, _) => Text(
                  fps > 0 ? '${fps.toStringAsFixed(0)} FPS' : '',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (_phase == _CameraPhase.running)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ValueListenableBuilder<_FrameView?>(
                valueListenable: _view,
                builder: (_, view, _) => _buildFeedbackBanner(view?.analysis.feedback),
              ),
            ),
        ],
      ),
    );
  }

  /// Preview and skeleton share one box inside a [FittedBox], so the overlay
  /// stays aligned with the image however it is cropped to the viewfinder.
  Widget _buildPreviewWithSkeleton() {
    final preview = _stream.buildPreview();
    if (preview == null) return _buildPlaceholder();
    const baseWidth = 360.0;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: baseWidth,
        height: baseWidth / _stream.previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,
            ValueListenableBuilder<_FrameView?>(
              valueListenable: _view,
              builder: (_, view, _) {
                final m = view?.analysis.measurements;
                return CustomPaint(
                  painter: PoseOverlayPainter(
                    frame: view?.frame,
                    mirrored: _stream.mirrored,
                    minVisibility: _config.minVisibility,
                    highlight: {...?view?.analysis.feedback.highlight},
                    angles: [
                      if (m?.leftPrimary != null) AngleLabel(_config.leftPrimary.vertex, m!.leftPrimary!),
                      if (m?.rightPrimary != null) AngleLabel(_config.rightPrimary.vertex, m!.rightPrimary!),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final Widget child;
    switch (_phase) {
      case _CameraPhase.failed:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'The camera could not be started.',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _startCamera,
              child: const Text('Try again', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      case _CameraPhase.paused:
        child = const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline, color: Colors.white70, size: 48),
            SizedBox(height: 10),
            Text('Session paused — camera is off', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        );
      case _CameraPhase.starting:
      case _CameraPhase.running:
        child = const CircularProgressIndicator(color: Colors.white);
    }
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: child));
  }

  Widget _buildRepsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(_support.supportsHoldTiming ? 'HOLD' : 'REPS', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Text(
              _support.supportsHoldTiming ? _clock(_session.holdSeconds ?? 0) : '${_session.reps}',
              key: ValueKey(_support.supportsHoldTiming ? _session.holdSeconds : _session.reps),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary, height: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner(LiveFeedback? feedback) {
    if (feedback == null) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(feedback.message),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: (feedback.isWarning ? AppTheme.warning : AppTheme.primary).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          '${feedback.isWarning ? '⚡' : '✅'} ${feedback.message}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildDetectionChip(String text, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: active ? AppTheme.success : AppTheme.border, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(active ? Icons.check : Icons.remove, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active ? AppTheme.textPrimary : AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    const side = BorderSide(color: AppTheme.primary, width: 3);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? side : BorderSide.none,
          bottom: !isTop ? side : BorderSide.none,
          left: isLeft ? side : BorderSide.none,
          right: !isLeft ? side : BorderSide.none,
        ),
      ),
    );
  }
}

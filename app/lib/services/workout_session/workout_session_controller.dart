import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/workout_session.dart';
import '../api_client.dart' show ApiException;
import '../posture/posture_engine.dart';
import '../user_session.dart';
import 'plan_progress.dart';
import 'workout_log_service.dart';

/// Progress of saving the last finished session.
enum SaveState { idle, saving, saved, failed }

/// Read-only view of the workout in progress.
///
/// The voice assistant (Module 6) depends on this interface only, so it never
/// does its own posture calculations.
abstract class WorkoutSessionContext implements Listenable {
  SessionStatus get status;
  SessionMode? get mode;
  SessionExercise? get exercise;
  List<SessionExercise> get upNext;

  /// Repetitions counted by the pose engine (camera) or confirmed by the user
  /// (manual).
  int get reps;
  int get partialReps;
  int get setsCompleted;
  Duration get elapsed;

  /// Camera mode: whether the body is currently being tracked.
  bool get landmarksDetected;
  bool get anglesCalculated;

  /// Latest valid joint angles in degrees, keyed by a readable name.
  Map<String, double> get angles;

  /// Latest feedback from the pose engine, or null when none is available.
  String? get feedbackMessage;
  bool get feedbackIsWarning;

  /// Null when posture is not being analysed or there is not enough data yet.
  int? get postureScore;

  /// Camera mode: true when a posture score is given (validated evaluation only).
  bool get formScored;

  /// Camera mode: true when form checks run (validated or experimental); false for basic tracking.
  bool get formChecked;

  /// Camera mode, static holds: seconds held in position so far. Null otherwise.
  int? get holdSeconds;
  SessionSummary? get lastSummary;

  bool get hasActiveSession;
}

/// Shared state of the current workout session (Phase 6).
///
/// The posture engine and the manual-guidance screen write to it, the voice
/// assistant and the session screens read from it. It follows the app's
/// existing pattern of a `ChangeNotifier` singleton (see `UserSession`).
/// Nothing here is persisted or sent anywhere.
class WorkoutSessionController extends ChangeNotifier implements WorkoutSessionContext {
  /// [store] receives every finished session; null keeps sessions in memory
  /// only (tests). [onTooDifficult] is told about exercises the user marked
  /// too difficult, so the next plan generation can adjust them.
  WorkoutSessionController({this.store, this.onTooDifficult, this.onFinished});

  static final WorkoutSessionController instance = WorkoutSessionController(
    store: FirebaseWorkoutLog.instance,
    onTooDifficult: (id) => UserSession.instance.tooDifficult.add(id),
    onFinished: (s) => PlanProgress.instance.record(s),
  );

  /// Told about every finished session (Module 4 progress: planned-exercise completion).
  void Function(SessionSummary summary)? onFinished;

  WorkoutLogStore? store;
  final void Function(String exerciseId)? onTooDifficult;

  /// Whether the last summary reached the database.
  final ValueNotifier<SaveState> saveState = ValueNotifier<SaveState>(SaveState.idle);
  String? saveError;
  bool _summarySaved = false;
  bool _flagSaved = false;

  final Stopwatch _clock = Stopwatch();

  SessionStatus _status = SessionStatus.idle;
  SessionMode? _mode;
  SessionExercise? _exercise;
  List<SessionExercise> _upNext = const [];
  PlanLink? _plan;
  int _reps = 0;
  int _partialReps = 0;
  int _setsCompleted = 0;
  bool _landmarksDetected = false;
  bool _anglesCalculated = false;
  Map<String, double> _angles = const {};
  String? _feedbackMessage;
  bool _feedbackIsWarning = false;
  int? _postureScore;
  int? _holdSeconds;
  bool _formScored = true;
  bool _formChecked = true;
  bool _finishRequested = false;
  SessionSummary? _lastSummary;
  final List<SessionSummary> _history = [];

  @override
  SessionStatus get status => _status;
  @override
  SessionMode? get mode => _mode;
  @override
  SessionExercise? get exercise => _exercise;
  @override
  List<SessionExercise> get upNext => _upNext;
  @override
  int get reps => _reps;
  @override
  int get partialReps => _partialReps;
  @override
  int get setsCompleted => _setsCompleted;
  @override
  Duration get elapsed => _clock.elapsed;
  @override
  bool get landmarksDetected => _landmarksDetected;
  @override
  bool get anglesCalculated => _anglesCalculated;
  @override
  Map<String, double> get angles => _angles;
  @override
  String? get feedbackMessage => _feedbackMessage;
  @override
  bool get feedbackIsWarning => _feedbackIsWarning;
  @override
  int? get postureScore => _postureScore;

  @override
  int? get holdSeconds => _holdSeconds;
  @override
  bool get formScored => _formScored;
  @override
  bool get formChecked => _formChecked;
  @override
  SessionSummary? get lastSummary => _lastSummary;
  @override
  bool get hasActiveSession => _status == SessionStatus.active || _status == SessionStatus.paused;

  /// Sessions finished since the app started, oldest first (in memory only).
  List<SessionSummary> get history => List.unmodifiable(_history);

  /// Set when something other than the session screen (the voice assistant)
  /// asks to end the session. The session screen owns the camera, so it
  /// performs the actual stop.
  bool get finishRequested => _finishRequested;

  /// [formScored]: false for camera sessions with basic tracking only, so nothing (screen or voice) claims a form verdict.
  void start(WorkoutSessionRequest request, SessionMode mode, {bool formScored = true, bool? formChecked}) {
    _formScored = formScored;
    _formChecked = formChecked ?? formScored;
    _exercise = request.exercise;
    _upNext = request.upNext;
    _plan = request.plan;
    _mode = mode;
    _status = SessionStatus.active;
    _reps = 0;
    _partialReps = 0;
    _setsCompleted = 0;
    _landmarksDetected = false;
    _anglesCalculated = false;
    _angles = const {};
    _feedbackMessage = null;
    _feedbackIsWarning = false;
    _postureScore = null;
    _holdSeconds = null;
    _finishRequested = false;
    _clock
      ..reset()
      ..start();
    notifyListeners();
  }

  /// Returns false when there is nothing to pause.
  bool pause() {
    if (_status != SessionStatus.active) return false;
    _status = SessionStatus.paused;
    _clock.stop();
    notifyListeners();
    return true;
  }

  bool resume() {
    if (_status != SessionStatus.paused) return false;
    _status = SessionStatus.active;
    _clock.start();
    notifyListeners();
    return true;
  }

  bool requestFinish() {
    if (!hasActiveSession) return false;
    _finishRequested = true;
    notifyListeners();
    return true;
  }

  /// Called by the pose pipeline for every analysed frame. Listeners are only
  /// notified when something the user can see or ask about has changed.
  void updatePosture(PostureAnalysis analysis, {required String angleLabel}) {
    if (_status != SessionStatus.active) return;
    final m = analysis.measurements;
    if (m != null) {
      _angles = {
        if (m.leftPrimary != null) 'Left ${angleLabel.toLowerCase()}': m.leftPrimary!,
        if (m.rightPrimary != null) 'Right ${angleLabel.toLowerCase()}': m.rightPrimary!,
        if (m.torsoLean != null) 'Torso lean': m.torsoLean!,
        if (m.bodyLine != null) 'Body line': m.bodyLine!,
      };
    }
    final changed = _reps != analysis.reps ||
        _partialReps != analysis.partialReps ||
        _landmarksDetected != analysis.landmarksDetected ||
        _anglesCalculated != analysis.anglesCalculated ||
        _feedbackMessage != analysis.feedback.message ||
        _postureScore != analysis.postureScore ||
        _holdSeconds != analysis.holdSeconds;
    _holdSeconds = analysis.holdSeconds;
    _reps = analysis.reps;
    _partialReps = analysis.partialReps;
    _landmarksDetected = analysis.landmarksDetected;
    _anglesCalculated = analysis.anglesCalculated;
    _feedbackMessage = analysis.feedback.message;
    _feedbackIsWarning = analysis.feedback.isWarning;
    _postureScore = analysis.postureScore;
    if (changed) notifyListeners();
  }

  /// Manual mode: the user confirmed a set of [reps] repetitions.
  void recordManualSet(int reps) {
    if (!hasActiveSession) return;
    _setsCompleted++;
    _reps += reps;
    notifyListeners();
  }

  /// Ends the session and stores its summary. Pass [report] for camera
  /// sessions; manual sessions have no posture score.
  SessionSummary finish({
    SessionFormReport? report,
    double? averageFps,
    bool skipped = false,
    bool tooDifficult = false,
    bool formScored = true,
    bool? formChecked,
  }) {
    final exercise = _exercise;
    if (exercise == null) throw StateError('finish() called without a session');
    _clock.stop();
    final camera = (_mode ?? SessionMode.manual) == SessionMode.camera;
    final reps = report?.reps ?? _reps;
    final held = report?.holdSeconds;
    // The planned exercise is complete only when its target was reached — never just because a session was opened.
    final reachedTarget = !skipped &&
        (held != null
            ? held >= exercise.sets * exercise.seconds && held > 0
            : camera
                ? (exercise.timed ? _clock.elapsed.inSeconds >= exercise.sets * exercise.seconds && exercise.seconds > 0 : reps >= exercise.targetReps && reps > 0)
                : _setsCompleted >= exercise.sets && _setsCompleted > 0);
    final summary = SessionSummary(
      exercise: exercise,
      mode: _mode ?? SessionMode.manual,
      endedAt: DateTime.now(),
      duration: _clock.elapsed,
      reps: report?.reps ?? _reps,
      partialReps: report?.partialReps ?? 0,
      setsCompleted: _setsCompleted,
      postureScore: report?.postureScore,
      accuracy: report?.accuracy,
      feedback: report?.feedback ?? const [],
      averageFps: averageFps,
      skipped: skipped,
      tooDifficult: tooDifficult,
      formScored: formScored,
      formChecked: formChecked ?? formScored,
      holdSeconds: report?.holdSeconds,
      plan: _plan,
      completedTarget: reachedTarget,
    );
    _lastSummary = summary;
    _history.add(summary);
    if (tooDifficult) onTooDifficult?.call(exercise.id);
    onFinished?.call(summary);
    _summarySaved = false;
    _flagSaved = !tooDifficult;
    unawaited(retrySave());
    _status = SessionStatus.finished;
    _finishRequested = false;
    _landmarksDetected = false;
    _anglesCalculated = false;
    notifyListeners();
    return summary;
  }

  /// Saves [lastSummary] (and its "Too Difficult" mark). Safe to call again
  /// after a failure; parts that were already saved are not written twice.
  Future<void> retrySave() async {
    final summary = _lastSummary;
    final store = this.store;
    if (summary == null || store == null) return;
    if (saveState.value == SaveState.saving) return;
    saveState.value = SaveState.saving;
    try {
      if (!_summarySaved) {
        await store.save(summary);
        _summarySaved = true;
      }
      if (!_flagSaved) {
        await store.markTooDifficult(summary.exercise.id);
        _flagSaved = true;
      }
      saveError = null;
      saveState.value = SaveState.saved;
    } catch (e) {
      saveError = e is ApiException ? e.message : 'The session could not be saved.';
      saveState.value = SaveState.failed;
    }
  }

  /// Drops a session that was left without finishing (e.g. back button).
  void abandon() {
    if (!hasActiveSession) return;
    _clock.stop();
    _status = SessionStatus.idle;
    _finishRequested = false;
    notifyListeners();
  }
}

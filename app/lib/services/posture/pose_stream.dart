import 'dart:async';

import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pose_estimator.dart';
import 'pose_landmark.dart';

class PoseStreamException implements Exception {
  /// no_camera | camera_denied | camera_failed, or a [PoseEstimatorException] code.
  final String code;
  final String message;
  const PoseStreamException(this.code, this.message);

  @override
  String toString() => message;
}

/// A live source of pose results plus the preview that goes with it.
/// The camera screen depends on this interface, so it can be driven by a fake
/// in tests.
abstract class PoseStream {
  /// Opens the camera and the pose model. Throws [PoseStreamException].
  Future<void> start();

  /// Releases the camera and the model. Safe to call more than once.
  Future<void> stop();

  /// One event per analysed frame.
  Stream<PoseFrame> get frames;

  /// The live preview, or null while the camera is not running.
  Widget? buildPreview();

  /// Width / height of the preview as displayed.
  double get previewAspectRatio;

  /// True when the preview is mirrored (front camera), so the overlay must be too.
  bool get mirrored;
  bool get canSwitchCamera;
  Future<void> switchCamera();

  /// Analysed frames per second, measured over the last second.
  ValueListenable<double> get fps;

  /// Mean analysed frames per second since [start].
  double? get averageFps;
}

/// Camera frames → MediaPipe pose landmarks.
///
/// At most [maxFramesInFlight] frames are in flight: frames that arrive while
/// the model is busy are dropped, so latency stays low and the UI thread only
/// ever does a cheap hand-off. Frames live in memory for the duration of one inference.
class CameraPoseStream implements PoseStream {
  final PoseEstimator estimator;
  final ResolutionPreset resolution;

  /// Camera frames per second to request (report NFR-P4 needs ≥ 15 analysed).
  static const targetFps = 30;

  CameraPoseStream({PoseEstimator? estimator, this.resolution = ResolutionPreset.medium})
      : estimator = estimator ?? MediaPipePoseEstimator();

  final StreamController<PoseFrame> _frames = StreamController<PoseFrame>.broadcast();
  final ValueNotifier<double> _fps = ValueNotifier<double>(0);
  final Stopwatch _clock = Stopwatch();

  List<CameraDescription> _cameras = const [];
  CameraDescription? _camera;
  CameraController? _controller;
  /// Frames handed to the model and not yet answered.
  int _inFlight = 0;

  /// Two frames may overlap: while the model analyses one, the next is
  /// already being copied to the native side, so the model is never idle
  /// waiting for a frame. Measured on a Redmi Note 11 with nobody in view:
  /// 7.8 analysed FPS with one frame in flight, 13.2 with two.
  /// More would only add latency. Results still arrive in order because the
  /// native side processes frames one at a time on a single thread.
  static const maxFramesInFlight = 2;
  bool _running = false;
  int _analysed = 0;
  int _windowCount = 0;
  int _windowStartMs = 0;

  @override
  Stream<PoseFrame> get frames => _frames.stream;
  @override
  ValueListenable<double> get fps => _fps;
  @override
  double? get averageFps {
    final ms = _clock.elapsedMilliseconds;
    return ms < 1000 || _analysed == 0 ? null : _analysed * 1000 / ms;
  }

  @override
  bool get mirrored => _camera?.lensDirection == CameraLensDirection.front;
  @override
  bool get canSwitchCamera => _cameras.map((c) => c.lensDirection).toSet().length > 1;

  @override
  double get previewAspectRatio {
    final c = _controller;
    // The sensor reports landscape; the app is shown in portrait.
    return c == null || !c.value.isInitialized ? 3 / 4 : 1 / c.value.aspectRatio;
  }

  @override
  Widget? buildPreview() {
    final c = _controller;
    return c == null || !c.value.isInitialized ? null : CameraPreview(c);
  }

  @override
  Future<void> start() async {
    if (_running) return;
    try {
      await estimator.initialize();
    } on PoseEstimatorException catch (e) {
      throw PoseStreamException(e.code, e.message);
    }
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _cameraError(e);
    }
    if (_cameras.isEmpty) {
      throw const PoseStreamException('no_camera', 'No camera was found on this device.');
    }
    // Front camera by default so the user can see the screen while exercising.
    _camera ??= _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    await _open(_camera!);
  }

  Future<void> _open(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      // Without a target the camera lowers its frame rate indoors to brighten
      // the image (measured: ~11 FPS on a Redmi Note 11), which caps pose
      // processing below the 15 FPS requirement.
      fps: targetFps,
      // The formats the native pose bridges convert: NV21 on Android, BGRA on iOS.
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );
    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _controller = controller;
      _camera = camera;
      _running = true;
      _analysed = 0;
      _windowCount = 0;
      _windowStartMs = 0;
      _clock
        ..reset()
        ..start();
      await controller.startImageStream(_onImage);
    } on CameraException catch (e) {
      _running = false;
      _controller = null;
      await controller.dispose();
      throw _cameraError(e);
    }
  }

  PoseStreamException _cameraError(CameraException e) {
    final denied = e.code.startsWith('CameraAccessDenied') || e.code == 'CameraAccessRestricted';
    return PoseStreamException(
      denied ? 'camera_denied' : 'camera_failed',
      denied ? 'Camera permission was not granted.' : (e.description ?? 'The camera could not be started.'),
    );
  }

  /// Frames delivered by the camera since [start], analysed or not.
  int cameraFrames = 0;

  void _onImage(CameraImage image) {
    cameraFrames++;
    if (_inFlight >= maxFramesInFlight || !_running) return; // drop frames while the model is busy
    final camera = _camera;
    if (camera == null) return;
    _inFlight++;
    final frame = CameraFrame(
      planes: [for (final p in image.planes) FramePlane(p.bytes, p.bytesPerRow, p.bytesPerPixel ?? 1)],
      width: image.width,
      height: image.height,
      rotationDegrees: uprightRotation(image.width, image.height, camera.sensorOrientation),
      timestampMs: _clock.elapsedMilliseconds,
    );
    estimator.estimate(frame).then((pose) {
      if (!_running || _frames.isClosed) return;
      _countFrame(pose.timestampMs);
      _frames.add(pose);
    }).catchError((Object error) {
      // A single bad frame must not end the session; report "no pose".
      if (_running && !_frames.isClosed) {
        _frames.add(PoseFrame(landmarks: const [], timestampMs: frame.timestampMs));
      }
    }).whenComplete(() => _inFlight--);
  }

  /// The screen is portrait, so an upright frame is taller than it is wide.
  /// Android delivers sensor-oriented (landscape) frames that need rotating;
  /// a platform that already delivers portrait frames needs no rotation.
  @visibleForTesting
  static int uprightRotation(int width, int height, int sensorOrientation) =>
      width > height ? sensorOrientation : 0;

  void _countFrame(int nowMs) {
    _analysed++;
    _windowCount++;
    final span = nowMs - _windowStartMs;
    if (span >= 1000) {
      _fps.value = _windowCount * 1000 / span;
      _windowCount = 0;
      _windowStartMs = nowMs;
    }
  }

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera || !_running) return;
    final current = _camera;
    final next = _cameras.firstWhere((c) => c.lensDirection != current?.lensDirection);
    await _closeCamera();
    await _open(next);
  }

  Future<void> _closeCamera() async {
    _running = false;
    _clock.stop();
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
    } on CameraException {
      // The stream was already stopped by the platform.
    }
    await controller.dispose();
  }

  @override
  Future<void> stop() async {
    await _closeCamera();
    await estimator.dispose();
    _fps.value = 0;
  }
}

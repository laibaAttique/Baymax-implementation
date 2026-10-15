import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pose_landmark.dart';

/// One image plane of a camera frame.
class FramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
  const FramePlane(this.bytes, this.bytesPerRow, this.bytesPerPixel);
}

/// A raw camera frame: a single NV21 plane or three YUV 4:2:0 planes
/// (Android), or a single BGRA plane (iOS).
class CameraFrame {
  final List<FramePlane> planes;
  final int width;
  final int height;

  /// Clockwise rotation needed to make the image upright.
  final int rotationDegrees;
  final int timestampMs;

  const CameraFrame({
    required this.planes,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.timestampMs,
  });
}

class PoseEstimatorException implements Exception {
  /// unsupported_platform | model_missing | init_failed | inference_failed
  final String code;
  final String message;
  const PoseEstimatorException(this.code, this.message);

  @override
  String toString() => message;
}

/// Runs a pose model on camera frames. Implementations must process frames on
/// the device and must not keep or transmit them.
abstract class PoseEstimator {
  Future<void> initialize();

  /// Returns the pose for [frame]; the frame has no landmarks when no person
  /// is found.
  Future<PoseFrame> estimate(CameraFrame frame);
  Future<void> dispose();
}

/// MediaPipe Pose Landmarker (33 landmarks), run natively on Android through
/// the `baymax/pose_landmarker` platform channel
/// (`android/.../PoseLandmarkerChannel.kt`). Inference happens on a native
/// background thread; frames are passed in memory and discarded.
///
/// The iOS side is `ios/Runner/PoseLandmarkerPlugin.swift`.
class MediaPipePoseEstimator implements PoseEstimator {
  static const _channel = MethodChannel('baymax/pose_landmarker');
  static const _valuesPerLandmark = 4;

  /// MediaPipe's "lite" pose model (float16), bundled as a Flutter asset so
  /// Android and iOS load the same file.
  static const modelAsset = 'assets/models/pose_landmarker_lite.task';

  @override
  Future<void> initialize() async {
    final Uint8List model;
    try {
      model = (await rootBundle.load(modelAsset)).buffer.asUint8List();
    } catch (_) {
      throw const PoseEstimatorException('model_missing', 'The pose model is not bundled with the app.');
    }
    try {
      final info = await _channel.invokeMethod<Object?>('initialize', {'model': model});
      if (kDebugMode && info is Map) debugPrint('[pose] model started on ${info['delegate']}');
    } on MissingPluginException {
      throw const PoseEstimatorException(
        'unsupported_platform',
        'Camera posture detection is available on Android and iOS phones only.',
      );
    } on PlatformException catch (e) {
      throw PoseEstimatorException(
        e.code == 'model_missing' ? 'model_missing' : 'init_failed',
        e.message ?? 'The pose model could not be started.',
      );
    }
  }

  @override
  Future<PoseFrame> estimate(CameraFrame frame) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('detect', {
        'planes': [for (final p in frame.planes) p.bytes],
        'rowStrides': [for (final p in frame.planes) p.bytesPerRow],
        'pixelStrides': [for (final p in frame.planes) p.bytesPerPixel],
        'width': frame.width,
        'height': frame.height,
        'rotation': frame.rotationDegrees,
        'timestampMs': frame.timestampMs,
      });
      if (result == null) throw const PoseEstimatorException('inference_failed', 'The pose model returned no result.');
      final width = (result['width'] as num).toDouble();
      final height = (result['height'] as num).toDouble();
      return PoseFrame(
        landmarks: _unpack(result['landmarks']),
        worldLandmarks: _unpack(result['worldLandmarks']),
        timestampMs: frame.timestampMs,
        aspectRatio: height > 0 ? width / height : 1,
        inferenceMs: (result['inferenceMs'] as num?)?.toInt(),
        convertMs: (result['convertMs'] as num?)?.toInt(),
      );
    } on PlatformException catch (e) {
      throw PoseEstimatorException('inference_failed', e.message ?? 'Pose detection failed on this frame.');
    }
  }

  /// Unpacks a flat [x, y, z, visibility, …] list. Anything that is not
  /// exactly 33 landmarks is treated as "no pose".
  static List<PoseLandmark> _unpack(dynamic packed) {
    if (packed is! List || packed.length != PoseIndex.count * _valuesPerLandmark) return const [];
    return [
      for (var i = 0; i < packed.length; i += _valuesPerLandmark)
        PoseLandmark(
          (packed[i] as num).toDouble(),
          (packed[i + 1] as num).toDouble(),
          (packed[i + 2] as num).toDouble(),
          (packed[i + 3] as num).toDouble(),
        ),
    ];
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Nothing to release on a platform without the native side.
    } on PlatformException {
      // Already closed.
    }
  }
}

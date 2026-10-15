import CoreVideo
import Flutter
import Foundation
import MediaPipeTasksVision

/// Runs the MediaPipe Pose Landmarker (33 landmarks) for the Flutter posture
/// module (Module 5). Same channel contract as the Android side
/// (android/.../PoseLandmarkerChannel.kt); Dart side:
/// lib/services/posture/pose_estimator.dart.
///
/// Frames arrive as BGRA bytes, are rotated upright into a pixel buffer in
/// memory, passed to the model and discarded. Nothing is written to disk except
/// the model file itself (copied once into the caches folder, because the iOS
/// MediaPipe API loads models from a path). Work happens on a serial
/// background queue so the UI thread is never blocked.
final class PoseLandmarkerPlugin: NSObject {
  static let channelName = "baymax/pose_landmarker"

  private let queue = DispatchQueue(label: "baymax.pose_landmarker")
  private var landmarker: PoseLandmarker?
  private var lastTimestampMs = -1

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = PoseLandmarkerPlugin()
    channel.setMethodCallHandler { call, result in instance.handle(call, result: result) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "initialize":
      let model = (args?["model"] as? FlutterStandardTypedData)?.data
      queue.async { self.initialize(model: model, result: result) }
    case "detect":
      queue.async { self.detect(args ?? [:], result: result) }
    case "close":
      queue.async {
        self.landmarker = nil
        DispatchQueue.main.async { result(nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func initialize(model: Data?, result: @escaping FlutterResult) {
    if landmarker != nil { return reply(result, nil) }
    guard let model = model, !model.isEmpty else {
      return reply(result, FlutterError(code: "model_missing", message: "The pose model was not provided.", details: nil))
    }
    do {
      let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pose_landmarker_lite.task")
      if (try? Data(contentsOf: url)) != model { try model.write(to: url, options: .atomic) }

      let options = PoseLandmarkerOptions()
      options.baseOptions.modelAssetPath = url.path
      options.runningMode = .video
      options.numPoses = 1
      options.minPoseDetectionConfidence = 0.5
      options.minPosePresenceConfidence = 0.5
      options.minTrackingConfidence = 0.5
      landmarker = try PoseLandmarker(options: options)
      lastTimestampMs = -1
      reply(result, nil)
    } catch {
      reply(result, FlutterError(code: "init_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func detect(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let model = landmarker else {
      return reply(result, FlutterError(code: "not_initialized", message: "The pose model is not running.", details: nil))
    }
    guard
      let planes = args["planes"] as? [FlutterStandardTypedData], let plane = planes.first,
      let rowStrides = args["rowStrides"] as? [Int], let rowStride = rowStrides.first,
      let width = args["width"] as? Int, let height = args["height"] as? Int,
      width > 0, height > 0, plane.data.count >= rowStride * (height - 1) + width * 4
    else {
      return reply(result, FlutterError(code: "bad_frame", message: "Unsupported camera frame layout.", details: nil))
    }
    let rotation = (((args["rotation"] as? Int) ?? 0) % 360 + 360) % 360
    // VIDEO mode requires strictly increasing timestamps.
    let timestampMs = max((args["timestampMs"] as? Int) ?? 0, lastTimestampMs + 1)
    lastTimestampMs = timestampMs

    guard let buffer = Self.uprightPixelBuffer(plane.data, width: width, height: height, rowStride: rowStride, rotation: rotation) else {
      return reply(result, FlutterError(code: "bad_frame", message: "Could not convert the camera frame.", details: nil))
    }
    do {
      let started = CFAbsoluteTimeGetCurrent()
      let detection = try model.detect(videoFrame: try MPImage(pixelBuffer: buffer), timestampInMilliseconds: timestampMs)
      let inferenceMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

      func pack(_ points: [(Float, Float, Float, Float)]?) -> FlutterStandardTypedData? {
        guard let points = points else { return nil }
        var out = [Float64]()
        out.reserveCapacity(points.count * 4)
        for p in points { out += [Float64(p.0), Float64(p.1), Float64(p.2), Float64(p.3)] }
        return FlutterStandardTypedData(float64: out.withUnsafeBufferPointer { Data(buffer: $0) })
      }
      let image = detection.landmarks.first?.map { ($0.x, $0.y, $0.z, $0.visibility?.floatValue ?? 0) }
      let world = detection.worldLandmarks.first?.map { ($0.x, $0.y, $0.z, $0.visibility?.floatValue ?? 0) }
      let swap = rotation == 90 || rotation == 270
      reply(result, [
        "width": swap ? height : width,
        "height": swap ? width : height,
        "inferenceMs": inferenceMs,
        "landmarks": pack(image) as Any,
        "worldLandmarks": pack(world) as Any,
      ])
    } catch {
      reply(result, FlutterError(code: "inference_failed", message: error.localizedDescription, details: nil))
    }
  }

  /// Copies a BGRA frame into a new pixel buffer, rotated clockwise by
  /// [rotation] so the result is upright.
  private static func uprightPixelBuffer(_ data: Data, width: Int, height: Int, rowStride: Int, rotation: Int) -> CVPixelBuffer? {
    let swap = rotation == 90 || rotation == 270
    let outW = swap ? height : width
    let outH = swap ? width : height
    var created: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    guard CVPixelBufferCreate(kCFAllocatorDefault, outW, outH, kCVPixelFormatType_32BGRA, attrs, &created) == kCVReturnSuccess,
          let buffer = created else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let outStride = CVPixelBufferGetBytesPerRow(buffer)
    let dst = base.assumingMemoryBound(to: UInt32.self)
    let dstRow = outStride / 4

    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let src = raw.baseAddress else { return }
      for y in 0..<height {
        let row = src.advanced(by: y * rowStride).assumingMemoryBound(to: UInt32.self)
        for x in 0..<width {
          let (dx, dy): (Int, Int)
          switch rotation {
          case 90: (dx, dy) = (height - 1 - y, x)
          case 180: (dx, dy) = (width - 1 - x, height - 1 - y)
          case 270: (dx, dy) = (y, width - 1 - x)
          default: (dx, dy) = (x, y)
          }
          dst[dy * dstRow + dx] = row[x]
        }
      }
    }
    return buffer
  }
}

package com.example.app

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Runs the MediaPipe Pose Landmarker (33 landmarks) for the Flutter posture
 * module (Module 5). Dart side: lib/services/posture/pose_estimator.dart.
 *
 * Frames arrive as raw YUV bytes, are converted to an upright bitmap in memory,
 * passed to the model and then overwritten by the next frame. Nothing is
 * written to disk or sent off the device. Inference runs on a single
 * background thread so the UI thread is never blocked.
 */
class PoseLandmarkerChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "baymax/pose_landmarker"
    }

    private val channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var landmarker: PoseLandmarker? = null
    private var lastTimestampMs = -1L
    private var argb = IntArray(0)
    private var bitmap: Bitmap? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val model = call.argument<ByteArray>("model")
                worker.execute { initialize(model, result) }
            }
            "detect" -> worker.execute { detect(call, result) }
            "close" -> worker.execute {
                close()
                main.post { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.execute { close() }
        worker.shutdown()
    }

    /** [model] is the .task file, read by Dart from the Flutter assets. */
    private fun initialize(model: ByteArray?, result: MethodChannel.Result) {
        try {
            if (landmarker == null) {
                if (model == null || model.isEmpty()) {
                    main.post { result.error("model_missing", "The pose model was not provided.", null) }
                    return
                }
                // The GPU is much faster on most phones; fall back to the CPU
                // when the device has no usable GPU delegate.
                landmarker = try {
                    create(model, Delegate.GPU).also { delegate = "GPU" }
                } catch (e: Throwable) {
                    create(model, Delegate.CPU).also { delegate = "CPU" }
                }
                lastTimestampMs = -1L
            }
            main.post { result.success(mapOf("delegate" to delegate)) }
        } catch (e: Throwable) {
            main.post { result.error("init_failed", e.message ?: "Could not start the pose model.", null) }
        }
    }

    private var delegate = "CPU"

    private fun create(model: ByteArray, delegate: Delegate): PoseLandmarker {
        val buffer = ByteBuffer.allocateDirect(model.size).order(ByteOrder.nativeOrder())
        buffer.put(model)
        buffer.rewind()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(buffer).setDelegate(delegate).build())
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return PoseLandmarker.createFromOptions(context, options)
    }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        try {
            val model = landmarker
            if (model == null) {
                main.post { result.error("not_initialized", "The pose model is not running.", null) }
                return
            }
            val planes = call.argument<List<ByteArray>>("planes")!!
            val rowStrides = call.argument<List<Int>>("rowStrides")!!
            val pixelStrides = call.argument<List<Int>>("pixelStrides")!!
            val width = call.argument<Int>("width")!!
            val height = call.argument<Int>("height")!!
            val rotation = ((call.argument<Int>("rotation") ?: 0) % 360 + 360) % 360
            // VIDEO mode requires strictly increasing timestamps.
            val timestampMs = maxOf((call.argument<Number>("timestampMs") ?: 0).toLong(), lastTimestampMs + 1)
            lastTimestampMs = timestampMs

            // The model works on a 256x256 input, so frames of 480p and up are
            // halved while converting: 4x less work with no loss for the model.
            val step = if (minOf(width, height) >= 480) 2 else 1
            val sw = width / step
            val sh = height / step
            val swap = rotation == 90 || rotation == 270
            val outW = if (swap) sh else sw
            val outH = if (swap) sw else sh
            if (argb.size != sw * sh) argb = IntArray(sw * sh)
            val convertStart = SystemClock.elapsedRealtime()
            if (!yuvToUprightArgb(planes, rowStrides, pixelStrides, width, height, step, rotation, argb)) {
                main.post { result.error("bad_frame", "Unsupported camera frame layout.", null) }
                return
            }
            var frame = bitmap
            if (frame == null || frame.width != outW || frame.height != outH) {
                frame = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
                bitmap = frame
            }
            frame!!.setPixels(argb, 0, outW, 0, 0, outW, outH)

            val started = SystemClock.elapsedRealtime()
            val detection = model.detectForVideo(BitmapImageBuilder(frame).build(), timestampMs)
            val inferenceMs = SystemClock.elapsedRealtime() - started
            val convertMs = started - convertStart

            val image = detection.landmarks().firstOrNull()
            val world = detection.worldLandmarks().firstOrNull()
            val reply = hashMapOf<String, Any?>(
                "width" to outW,
                "height" to outH,
                "inferenceMs" to inferenceMs,
                "convertMs" to convertMs,
                "delegate" to delegate,
                "landmarks" to image?.let { list ->
                    DoubleArray(list.size * 4).also { out ->
                        list.forEachIndexed { i, lm ->
                            out[i * 4] = lm.x().toDouble()
                            out[i * 4 + 1] = lm.y().toDouble()
                            out[i * 4 + 2] = lm.z().toDouble()
                            out[i * 4 + 3] = lm.visibility().orElse(0f).toDouble()
                        }
                    }
                },
                "worldLandmarks" to world?.let { list ->
                    DoubleArray(list.size * 4).also { out ->
                        list.forEachIndexed { i, lm ->
                            out[i * 4] = lm.x().toDouble()
                            out[i * 4 + 1] = lm.y().toDouble()
                            out[i * 4 + 2] = lm.z().toDouble()
                            out[i * 4 + 3] = lm.visibility().orElse(0f).toDouble()
                        }
                    }
                },
            )
            main.post { result.success(reply) }
        } catch (e: Throwable) {
            main.post { result.error("inference_failed", e.message ?: "Pose detection failed.", null) }
        }
    }

    private fun close() {
        try {
            landmarker?.close()
        } catch (_: Throwable) {
        }
        landmarker = null
        bitmap?.recycle()
        bitmap = null
        argb = IntArray(0)
    }

    /**
     * Converts a YUV 4:2:0 frame (one NV21 plane, or separate Y/U/V planes) to
     * ARGB, keeping every [step]-th pixel in each direction and rotating it
     * clockwise by [rotation] so the result is upright.
     * Returns false when the buffers do not match the stated size.
     */
    private fun yuvToUprightArgb(
        planes: List<ByteArray>,
        rowStrides: List<Int>,
        pixelStrides: List<Int>,
        width: Int,
        height: Int,
        step: Int,
        rotation: Int,
        out: IntArray,
    ): Boolean {
        val yPlane = planes[0]
        val uPlane: ByteArray
        val vPlane: ByteArray
        val yStride: Int
        val uvStride: Int
        val uvPixelStride: Int
        val uOffset: Int
        val vOffset: Int
        if (planes.size == 1) {
            // NV21: full-resolution Y, then interleaved V,U at half resolution.
            if (yPlane.size < width * height * 3 / 2) return false
            yStride = width
            uvStride = width
            uvPixelStride = 2
            uPlane = yPlane
            vPlane = yPlane
            vOffset = width * height
            uOffset = width * height + 1
        } else if (planes.size >= 3) {
            yStride = rowStrides[0]
            uvStride = rowStrides[1]
            uvPixelStride = pixelStrides[1]
            uPlane = planes[1]
            vPlane = planes[2]
            uOffset = 0
            vOffset = 0
            val lastUv = (height / 2 - 1) * uvStride + (width / 2 - 1) * uvPixelStride
            if (yPlane.size < (height - 1) * yStride + width || uPlane.size <= lastUv || vPlane.size <= lastUv) {
                return false
            }
        } else {
            return false
        }

        val sw = width / step
        val sh = height / step
        for (oy in 0 until sh) {
            val y = oy * step
            val yRow = y * yStride
            val uvRow = (y shr 1) * uvStride
            for (ox in 0 until sw) {
                val x = ox * step
                val uvIndex = uvRow + (x shr 1) * uvPixelStride
                val yy = (yPlane[yRow + x].toInt() and 0xFF) - 16
                val u = (uPlane[uOffset + uvIndex].toInt() and 0xFF) - 128
                val v = (vPlane[vOffset + uvIndex].toInt() and 0xFF) - 128
                val c = 1192 * (if (yy < 0) 0 else yy)
                var r = (c + 1634 * v) shr 10
                var g = (c - 833 * v - 400 * u) shr 10
                var b = (c + 2066 * u) shr 10
                r = if (r < 0) 0 else if (r > 255) 255 else r
                g = if (g < 0) 0 else if (g > 255) 255 else g
                b = if (b < 0) 0 else if (b > 255) 255 else b
                val index = when (rotation) {
                    90 -> ox * sh + (sh - 1 - oy)
                    180 -> (sh - 1 - oy) * sw + (sw - 1 - ox)
                    270 -> (sw - 1 - ox) * sh + oy
                    else -> oy * sw + ox
                }
                out[index] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return true
    }
}

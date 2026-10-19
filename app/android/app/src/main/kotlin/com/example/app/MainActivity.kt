package com.example.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var poseChannel: PoseLandmarkerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Module 5: on-device MediaPipe pose estimation.
        poseChannel = PoseLandmarkerChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        poseChannel?.dispose()
        poseChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

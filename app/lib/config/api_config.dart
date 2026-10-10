import 'package:flutter/foundation.dart';

/// Base URL of the Express backend (`Baymax-main/server.js`).
///
/// Override at run time, e.g. for a physical phone on the same Wi-Fi:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    // The Android emulator reaches the host machine at 10.0.2.2, not localhost.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }
}

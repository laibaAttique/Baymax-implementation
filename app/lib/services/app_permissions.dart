import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome {
  granted,
  denied,

  /// The system will not ask again; the user must change it in Settings.
  permanentlyDenied,
}

/// Runtime permissions for the camera (Module 5) and microphone (Module 6).
/// Replace [instance] in tests.
class AppPermissions {
  const AppPermissions();
  static AppPermissions instance = const AppPermissions();

  Future<PermissionOutcome> requestCamera() => _request(Permission.camera);
  Future<PermissionOutcome> requestMicrophone() => _request(Permission.microphone);

  Future<bool> openSettings() => openAppSettings();

  Future<PermissionOutcome> _request(Permission permission) async {
    try {
      final status = await permission.request();
      if (status.isGranted || status.isLimited) return PermissionOutcome.granted;
      if (status.isPermanentlyDenied || status.isRestricted) return PermissionOutcome.permanentlyDenied;
      return PermissionOutcome.denied;
    } on MissingPluginException {
      // Platform without the permission plugin: never assume access.
      return PermissionOutcome.denied;
    }
  }
}

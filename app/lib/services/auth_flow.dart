import 'package:flutter/material.dart';
import '../models/health_profile.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/main_navigation.dart';
import '../screens/health_profiling/step1_personal_info.dart';
import 'auth_service.dart';
import 'api_client.dart';
import 'user_session.dart';

/// Decides where a signed-in user goes next: the dashboard if they already
/// completed health profiling, otherwise the profiling wizard.
class AuthFlow {
  AuthFlow._();

  static Future<void> continueAfterAuth(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = AuthService.instance.currentUser?.displayName ?? '';

    Widget next;
    try {
      final hasProfile = await UserSession.instance.load();
      next = hasProfile
          ? const MainNavigation()
          : Step1PersonalInfo(profile: HealthProfile(fullName: name));
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Token rejected (expired/revoked account): force a fresh login.
        await AuthService.instance.signOut();
        messenger.showSnackBar(const SnackBar(content: Text('Your session expired. Please log in again.')));
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      // Can't tell whether a profile exists; fall back to profiling so a new
      // user is never skipped past it.
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t load your profile: ${e.message}')));
      next = Step1PersonalInfo(profile: HealthProfile(fullName: name));
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => next),
      (route) => false,
    );
  }
}

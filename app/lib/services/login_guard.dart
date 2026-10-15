/// Module 1 (mockup M3 FR3.4, NFR-S3): after 5 failed logins in a row for the same email, further attempts are refused for 15 minutes.
///
/// This is a best-effort guard in the app. It is kept in memory, so it resets when the app is closed, and a determined person can bypass
/// an app-side check. The real defence is the server: Firebase Authentication also rate-limits repeated sign-in attempts on its own
/// (the "too many attempts" response). The scope's "notify the user by email" is not done.
class LoginGuard {
  LoginGuard({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final LoginGuard instance = LoginGuard();

  static const maxAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  final DateTime Function() _now;
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  String _key(String email) => email.trim().toLowerCase();

  /// How long this email stays locked, or null when it may try.
  Duration? lockedFor(String email) {
    final k = _key(email);
    final until = _lockedUntil[k];
    if (until == null) return null;
    final left = until.difference(_now());
    if (left <= Duration.zero) {
      _lockedUntil.remove(k);
      _failures.remove(k);
      return null;
    }
    return left;
  }

  /// Records a failed attempt. Returns how many attempts are left before the lock (0 means it is now locked).
  int recordFailure(String email) {
    final k = _key(email);
    final n = (_failures[k] ?? 0) + 1;
    _failures[k] = n;
    if (n >= maxAttempts) {
      _lockedUntil[k] = _now().add(lockDuration);
      return 0;
    }
    return maxAttempts - n;
  }

  void recordSuccess(String email) {
    final k = _key(email);
    _failures.remove(k);
    _lockedUntil.remove(k);
  }

  static String describe(Duration d) {
    final m = (d.inSeconds / 60).ceil();
    return m <= 1 ? 'about a minute' : '$m minutes';
  }
}

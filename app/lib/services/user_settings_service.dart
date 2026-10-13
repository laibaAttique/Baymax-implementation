import 'realtime_db.dart';

/// The user's own choices for Modules 11 and 14, stored at `users/{uid}/settings`. Everything is off until the user turns it on.
class UserSettings {
  final bool leaderboardOptIn;

  /// Name shown to other users on the leaderboard (never the email or the full profile name unless the user types it).
  final String displayName;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final bool inactivityAlerts;

  const UserSettings({
    this.leaderboardOptIn = false,
    this.displayName = '',
    this.reminderEnabled = false,
    this.reminderHour = 18,
    this.reminderMinute = 0,
    this.inactivityAlerts = false,
  });

  UserSettings copyWith({
    bool? leaderboardOptIn,
    String? displayName,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? inactivityAlerts,
  }) =>
      UserSettings(
        leaderboardOptIn: leaderboardOptIn ?? this.leaderboardOptIn,
        displayName: displayName ?? this.displayName,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        inactivityAlerts: inactivityAlerts ?? this.inactivityAlerts,
      );

  Map<String, dynamic> toJson() => {
        'leaderboardOptIn': leaderboardOptIn,
        'displayName': displayName.trim(),
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'inactivityAlerts': inactivityAlerts,
      };

  factory UserSettings.fromJson(Map<String, dynamic> j) {
    int inRange(Object? v, int lo, int hi, int fallback) {
      final n = (v as num?)?.toInt();
      return n == null || n < lo || n > hi ? fallback : n;
    }

    return UserSettings(
      leaderboardOptIn: j['leaderboardOptIn'] == true,
      displayName: (j['displayName'] as String? ?? '').trim(),
      reminderEnabled: j['reminderEnabled'] == true,
      reminderHour: inRange(j['reminderHour'], 0, 23, 18),
      reminderMinute: inRange(j['reminderMinute'], 0, 59, 0),
      inactivityAlerts: j['inactivityAlerts'] == true,
    );
  }
}

class UserSettingsService {
  UserSettingsService._();
  static final UserSettingsService instance = UserSettingsService._();

  Future<UserSettings> load() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('settings').get();
      if (!snap.exists) return const UserSettings();
      return UserSettings.fromJson(Map<String, dynamic>.from(RealtimeDb.plain(snap.value) as Map));
    });
  }

  Future<void> save(UserSettings s) => RealtimeDb.guard(() => RealtimeDb.userRef('settings').set(s.toJson()));
}

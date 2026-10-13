import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/plan.dart';
import 'activity_service.dart';
import 'gamification.dart';
import 'progress_service.dart';
import 'user_settings_service.dart';

/// Module 14 (FR-3, FR-5): workout reminders and the inactivity nudge, as notifications scheduled on the phone.
///
/// These are local notifications: they need no server and no internet. Push notifications from a server (FCM, FR-6) are not
/// part of this version. Notification text never contains health data, because it is shown on the lock screen.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _reminderIdBase = 10; // 11..17 = Monday..Sunday
  static const _inactivityId = 99;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _init() async {
    if (_ready || !supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
    );
    _ready = true;
  }

  /// Asks the user for permission to show notifications (Android 13+ and iOS). Returns true when allowed.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      await _init();
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
      }
      return await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('workout_reminders', 'Workout reminders',
        channelDescription: 'Reminders for your planned workouts', importance: Importance.defaultImportance, priority: Priority.defaultPriority),
    iOS: DarwinNotificationDetails(),
  );

  // Times are scheduled as UTC instants (the same moment as the local time chosen), so no timezone database is needed.
  // Repeating weekly keeps the same UTC time; the schedule is rebuilt each time the app starts, which corrects daylight-saving shifts.
  tz.TZDateTime _utc(DateTime local) => tz.TZDateTime.from(local.toUtc(), tz.UTC);

  Future<void> cancelAll() async {
    if (!supported) return;
    try {
      await _init();
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Rebuilds every scheduled notification from the user's settings, plan and last workout.
  /// Safe to call often; does nothing (and schedules nothing) when the user has not turned reminders on.
  Future<void> refresh({required UserSettings settings, required PersonalizedPlan? plan, DateTime? lastWorkout, DateTime? now}) async {
    if (!supported) return;
    try {
      await _init();
      await _plugin.cancelAll();
      final t = now ?? DateTime.now();
      if (plan != null && settings.reminderEnabled) {
        for (final weekday in ProgressService.plannedWeekdays(plan)) {
          final at = nextWeekdayAt(t, weekday, settings.reminderHour, settings.reminderMinute);
          await _plugin.zonedSchedule(
            id: _reminderIdBase + weekday,
            title: 'Time to move 💪',
            body: 'Your workout is planned for today. Open Baymax to start.',
            scheduledDate: _utc(at),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
      if (plan != null && settings.inactivityAlerts) {
        final at = inactivityNudgeAt(t, lastWorkout);
        if (at != null) {
          await _plugin.zonedSchedule(
            id: _inactivityId,
            title: 'We miss you 👋',
            body: 'It has been a few days since your last workout. A short session still counts.',
            scheduledDate: _utc(at),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (_) {
      // Scheduling is best effort: a failure must never break the app.
    }
  }

  /// Loads the settings and last workout, then [refresh]es. Used after sign-in, after a workout is marked, and after the settings change.
  Future<void> refreshFromAccount(PersonalizedPlan? plan) async {
    try {
      final settings = await UserSettingsService.instance.load();
      final last = await ActivityService.instance.lastWorkoutDate();
      await refresh(settings: settings, plan: plan, lastWorkout: last);
    } catch (_) {}
  }
}

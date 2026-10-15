import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import 'food_log_service.dart';
import 'gamification.dart';
import 'notification_service.dart';
import 'progress_service.dart';
import 'realtime_db.dart';
import 'user_settings_service.dart';

/// Module 16 (FR-3 to FR-9): the in-app notification list, stored at `users/{uid}/inbox/{id}`.
///
/// Items are created when something happens (a badge is earned, an allergen is found) or when a reminder came due while the app was
/// closed ([dueItems]). Ids are stable, so noticing the same event twice never creates a second item.
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  /// Unread count for the badge on the bell icon. Updated by every change below.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Bumped when the list changes, so an open Notifications screen reloads.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// The user's master switch (Profile preferences). While off, nothing new is created and nothing is shown on the phone.
  bool enabled = true;

  void applySettings(UserSettings s) => enabled = s.notificationsEnabled;

  Future<List<AppNotification>> load({int limit = 100}) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('inbox').orderByChild('createdAt').limitToLast(limit).get();
      if (!snap.exists) {
        unread.value = 0;
        return <AppNotification>[];
      }
      final raw = RealtimeDb.plain(snap.value) as Map<String, dynamic>;
      final list = <AppNotification>[
        for (final e in raw.entries)
          if (AppNotification.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)) case final n?) n,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      unread.value = list.where((n) => !n.read).length;
      return list;
    });
  }

  /// Reads just the unread count (for the bell). Quietly does nothing when signed out or offline.
  Future<void> refreshUnread() async {
    try {
      await load();
    } catch (_) {}
  }

  /// Stores [n] once. Returns true when it was new. Pass [alsoOnPhone] to also show it as a phone notification right now.
  Future<bool> add(AppNotification n, {bool alsoOnPhone = false}) async {
    if (!enabled) return false;
    final created = await RealtimeDb.guard(() async {
      final ref = RealtimeDb.userRef('inbox/${n.id}');
      if ((await ref.get()).exists) return false;
      await ref.set(n.toJson());
      return true;
    });
    if (!created) return false;
    unread.value++;
    changes.value++;
    if (alsoOnPhone) {
      // The phone banner is best effort: it needs the notification permission the user may not have given.
      await NotificationService.instance.showNow(id: n.id.hashCode & 0x3fffffff, title: n.title, body: n.body);
    }
    return true;
  }

  Future<void> markRead(String id) async {
    await RealtimeDb.guard(() => RealtimeDb.userRef('inbox/$id/read').set(true));
    if (unread.value > 0) unread.value--;
    changes.value++;
  }

  /// FR-9: marks everything read and clears the badge count.
  Future<void> markAllRead(List<AppNotification> items) async {
    final ids = [for (final n in items) if (!n.read) n.id];
    if (ids.isNotEmpty) {
      await RealtimeDb.guard(() => RealtimeDb.db.ref().update({for (final id in ids) 'users/${RealtimeDb.uid}/inbox/$id/read': true}));
    }
    unread.value = 0;
    changes.value++;
  }

  // ---- what to create --------------------------------------------------------------------------------------------------------

  static AppNotification badge(String badgeId, DateTime now) {
    final b = Gamification.catalogue.firstWhere((b) => b.id == badgeId, orElse: () => AppBadge(badgeId, badgeId, ''));
    return AppNotification(
      id: 'badge-$badgeId',
      type: NotificationType.badgeEarned,
      title: 'New badge: ${b.title}',
      body: b.description.isEmpty ? 'You earned a new badge.' : 'You earned it. ${b.description}',
      createdAt: now,
      route: 'progress',
    );
  }

  static AppNotification allergen(List<String> allergens, DateTime now) => AppNotification(
        id: 'allergen-${now.millisecondsSinceEpoch}',
        type: NotificationType.allergenAlert,
        title: 'Allergen found in a scanned product',
        body: 'The label contains ${allergens.join(' and ')}, which ${allergens.length > 1 ? 'are' : 'is'} on your allergy list. Avoid this product.',
        createdAt: now,
        route: 'scanner',
      );

  /// Reminders that came due in the last [days] days (including today) while the app was closed. Pure: nothing is written here.
  /// A workout reminder is due on a planned day, after the reminder time, with no workout completed. A meal reminder is due after
  /// the meal-reminder time with no food logged. The inactivity item appears once per day while the user is inactive.
  static List<AppNotification> dueItems({
    required DateTime now,
    required ProgressSnapshot progress,
    required UserSettings settings,
    int days = 3,
  }) {
    final out = <AppNotification>[];
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final recent = progress.days.where((d) => !d.date.isAfter(Gamification.dateOnly(now))).toList();
    for (final d in recent.skip(recent.length > days ? recent.length - days : 0)) {
      final key = FoodLogService.dateKey(d.date);
      final day = names[d.date.weekday - 1];
      final isToday = Gamification.dateOnly(now) == d.date;
      if (settings.reminderEnabled && d.planned && !d.workoutDone) {
        final at = DateTime(d.date.year, d.date.month, d.date.day, settings.reminderHour, settings.reminderMinute);
        if (!at.isAfter(now)) {
          out.add(AppNotification(
            id: 'wr-$key',
            type: NotificationType.workoutReminder,
            title: 'Workout reminder',
            body: isToday ? 'Your workout is planned for today. A short session still counts.' : 'Your workout was planned for $day and is not marked as done.',
            createdAt: at,
            route: 'workout',
          ));
        }
      }
      if (settings.mealReminderEnabled && !d.foodLogged) {
        final at = DateTime(d.date.year, d.date.month, d.date.day, settings.mealReminderHour, settings.mealReminderMinute);
        if (!at.isAfter(now)) {
          out.add(AppNotification(
            id: 'ml-$key',
            type: NotificationType.mealReminder,
            title: 'Meal log reminder',
            body: isToday ? 'You have not logged any food today.' : 'You did not log any food on $day.',
            createdAt: at,
            route: 'diet',
          ));
        }
      }
    }
    final i = progress.inactivity;
    if (settings.inactivityAlerts && i != null) {
      out.add(AppNotification(
        id: 'ia-${FoodLogService.dateKey(now)}',
        type: NotificationType.inactivity,
        title: 'We miss you',
        body: 'It has been ${i.daysSinceWorkout} days since your last workout. A short session still counts.',
        createdAt: now,
        route: 'workout',
      ));
    }
    return out;
  }

  /// Stores whatever [dueItems] finds. Best effort: a failure never breaks the screen that called it.
  Future<void> syncDue({required DateTime now, required ProgressSnapshot progress, required UserSettings settings}) async {
    applySettings(settings);
    try {
      for (final n in dueItems(now: now, progress: progress, settings: settings)) {
        await add(n);
      }
      await refreshUnread();
    } catch (_) {}
  }
}

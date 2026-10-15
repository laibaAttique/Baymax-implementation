import 'package:flutter/material.dart';

/// The kinds of notification the app creates (Module 16, FR-3 to FR-8). Each has its own icon and opens its own screen.
enum NotificationType { workoutReminder, mealReminder, badgeEarned, allergenAlert, inactivity, appointment }

/// The tabs of the Notifications screen.
enum NotificationCategory { workout, diet, alerts }

extension NotificationTypeInfo on NotificationType {
  /// Stored in the database.
  String get id => const {
        NotificationType.workoutReminder: 'workout_reminder',
        NotificationType.mealReminder: 'meal_reminder',
        NotificationType.badgeEarned: 'badge_earned',
        NotificationType.allergenAlert: 'allergen_alert',
        NotificationType.inactivity: 'inactivity',
        NotificationType.appointment: 'appointment',
      }[this]!;

  NotificationCategory get category => const {
        NotificationType.workoutReminder: NotificationCategory.workout,
        NotificationType.badgeEarned: NotificationCategory.workout,
        NotificationType.inactivity: NotificationCategory.workout,
        NotificationType.mealReminder: NotificationCategory.diet,
        NotificationType.allergenAlert: NotificationCategory.alerts,
        NotificationType.appointment: NotificationCategory.alerts,
      }[this]!;

  IconData get icon => const {
        NotificationType.workoutReminder: Icons.alarm_rounded,
        NotificationType.mealReminder: Icons.restaurant_rounded,
        NotificationType.badgeEarned: Icons.military_tech_rounded,
        NotificationType.allergenAlert: Icons.warning_amber_rounded,
        NotificationType.inactivity: Icons.waving_hand_rounded,
        NotificationType.appointment: Icons.event_available_rounded,
      }[this]!;

  String get label => const {
        NotificationType.workoutReminder: 'Workout reminder',
        NotificationType.mealReminder: 'Meal log reminder',
        NotificationType.badgeEarned: 'Badge earned',
        NotificationType.allergenAlert: 'Allergen alert',
        NotificationType.inactivity: 'Inactivity',
        NotificationType.appointment: 'Appointment',
      }[this]!;

  static NotificationType? fromId(String? id) {
    for (final t in NotificationType.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

extension NotificationCategoryLabel on NotificationCategory {
  String get label => const ['Workout', 'Diet', 'Alerts'][index];
}

class AppNotification {
  /// Stable id: the same event always has the same id, so it is stored once however often the app notices it.
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Which screen a tap opens: workout | diet | progress | scanner | appointments.
  final String route;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.route = '',
  });

  AppNotification copyWith({bool? read}) =>
      AppNotification(id: id, type: type, title: title, body: body, createdAt: createdAt, read: read ?? this.read, route: route);

  Map<String, Object?> toJson() => {
        'type': type.id,
        'title': title,
        'body': body,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'read': read,
        if (route.isNotEmpty) 'route': route,
      };

  static AppNotification? fromJson(String id, Map<String, dynamic> j) {
    final type = NotificationTypeInfo.fromId(j['type'] as String?);
    if (type == null) return null;
    return AppNotification(
      id: id,
      type: type,
      title: (j['title'] as String?) ?? type.label,
      body: (j['body'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(((j['createdAt'] as num?) ?? 0).toInt()),
      read: j['read'] == true,
      route: (j['route'] as String?) ?? '',
    );
  }
}

import 'package:flutter/material.dart';
import '../screens/notifications/notifications_screen.dart';
import '../services/inbox_service.dart';

/// The bell in the top bar: opens the Notifications screen and shows how many are unread (Module 3 FR-8, Module 16 FR-9).
class NotificationBell extends StatelessWidget {
  const NotificationBell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: InboxService.instance.unread,
      builder: (context, count, _) => IconButton(
        tooltip: count > 0 ? 'Notifications, $count unread' : 'Notifications',
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 9 ? '9+' : '$count'),
          child: const Icon(Icons.notifications_none_rounded),
        ),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => InboxService.instance.refreshUnread()),
      ),
    );
  }
}

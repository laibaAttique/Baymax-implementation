import 'package:flutter/material.dart';
import '../../models/app_notification.dart';
import '../../services/api_client.dart';
import '../../services/inbox_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../allergy/allergy_scanner.dart';
import '../specialists/my_appointments_screen.dart';
import '../community/community_screen.dart';
import '../dashboard/main_navigation.dart';

/// Module 16 (FR-8, FR-9, mockup M39): the categorised notification list with read / unread states and "Mark all read".
class NotificationsScreen extends StatefulWidget {
  final Future<List<AppNotification>> Function()? loader;
  final Future<void> Function(String id)? onMarkRead;
  final Future<void> Function(List<AppNotification> items)? onMarkAllRead;
  const NotificationsScreen({Key? key, this.loader, this.onMarkRead, this.onMarkAllRead}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _error;
  bool _loading = true;
  NotificationCategory? _tab; // null = All

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await (widget.loader ?? () => InboxService.instance.load())();
      if (mounted) setState(() => _items = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your notifications.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    final items = _items;
    if (items == null) return;
    setState(() => _items = [for (final n in items) n.copyWith(read: true)]); // clears the unread look at once
    try {
      await (widget.onMarkAllRead ?? InboxService.instance.markAllRead)(items);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save that. Pull down to refresh.')));
        _load();
      }
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      setState(() => _items = [for (final x in _items!) x.id == n.id ? x.copyWith(read: true) : x]);
      try {
        await (widget.onMarkRead ?? InboxService.instance.markRead)(n.id);
      } catch (_) {}
    }
    if (!mounted) return;
    switch (n.route) {
      case 'workout':
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 2)), (r) => false);
      case 'diet':
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 1)), (r) => false);
      case 'progress':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityScreen()));
      case 'scanner':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AllergyScanner()));
      case 'appointments':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAppointmentsScreen()));
    }
  }

  static String when(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = now.difference(t);
    String clock() {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
    }

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (day == today) return 'Today, ${clock()}';
    if (today.difference(day).inDays == 1) return 'Yesterday, ${clock()}';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}, ${clock()}';
  }

  Widget _tile(AppNotification n) {
    final unread = !n.read;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        tint: unread ? AppTheme.tint(AppTheme.primary, 0.14) : null,
        padding: const EdgeInsets.all(14),
        onTap: () => _open(n),
        semanticLabel: '${unread ? 'Unread. ' : ''}${n.title}. ${n.body}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconWell(icon: n.type.icon, color: n.type == NotificationType.allergenAlert ? AppTheme.error : AppTheme.primary, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(n.title, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 14.5, color: AppTheme.textPrimary))),
                    if (unread) Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 8), decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
                  ]),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(n.body, style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                  const SizedBox(height: 6),
                  Text(when(n.createdAt, DateTime.now()), style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _items ?? const <AppNotification>[];
    final shown = [for (final n in all) if (_tab == null || n.type.category == _tab) n];
    final anyUnread = all.any((n) => !n.read);
    int unreadIn(NotificationCategory? c) => all.where((n) => !n.read && (c == null || n.type.category == c)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: anyUnread ? _markAll : null, child: const Text('Mark all read')),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _items == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items == null
              ? MessageState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        children: [
                          for (final c in <NotificationCategory?>[null, ...NotificationCategory.values])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(unreadIn(c) > 0 ? '${c?.label ?? 'All'} (${unreadIn(c)})' : (c?.label ?? 'All')),
                                selected: _tab == c,
                                showCheckmark: false,
                                selectedColor: AppTheme.primary,
                                backgroundColor: AppTheme.card,
                                side: BorderSide(color: _tab == c ? AppTheme.primary : AppTheme.border),
                                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _tab == c ? Colors.white : AppTheme.textPrimary),
                                onSelected: (_) => setState(() => _tab = c),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: shown.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 60),
                                MessageStateBody(message: _tab == null ? 'No notifications yet. Reminders, badges and allergen alerts will show up here.' : 'Nothing in ${_tab!.label} yet.', icon: Icons.notifications_none_rounded),
                              ])
                            : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [for (final n in shown) _tile(n)]),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// The card of [MessageState] without the Center, for use inside a list.
class MessageStateBody extends StatelessWidget {
  final String message;
  final IconData icon;
  const MessageStateBody({Key? key, required this.message, required this.icon}) : super(key: key);

  @override
  Widget build(BuildContext context) => MessageState(message: message, icon: icon);
}

import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/gamification.dart';
import '../../services/inbox_service.dart';
import '../../services/notification_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/user_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

/// Modules 11 and 14: workout reminders, inactivity alerts, leaderboard participation and the user's role.
/// Everything is off until the user turns it on.
class SettingsScreen extends StatefulWidget {
  final Future<UserSettings> Function()? loader;
  final Future<void> Function(UserSettings)? saver;
  const SettingsScreen({Key? key, this.loader, this.saver}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserSettings? _s;
  String? _error;
  final _name = TextEditingController();

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.loader ?? UserSettingsService.instance.load)();
      if (!mounted) return;
      setState(() {
        _s = s;
        _name.text = s.displayName;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your settings.');
    }
  }

  /// Saves, then rebuilds the scheduled reminders.
  Future<void> _save(UserSettings next) async {
    final previous = _s;
    setState(() => _s = next);
    try {
      await (widget.saver ?? UserSettingsService.instance.save)(next);
      if (widget.saver == null) {
        InboxService.instance.applySettings(next);
        await NotificationService.instance.refreshFromAccount(UserSession.instance.plan);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _s = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _setReminders(bool on) async {
    final s = _s!;
    if (on && widget.saver == null) {
      final ok = await NotificationService.instance.requestPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Notifications are not allowed for Baymax. Turn them on in your phone settings to get reminders.')));
        }
        return;
      }
    }
    await _save(s.copyWith(reminderEnabled: on));
  }

  Future<void> _setInactivity(bool on) async {
    final s = _s!;
    if (on && widget.saver == null) {
      final ok = await NotificationService.instance.requestPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications are not allowed for Baymax. Turn them on in your phone settings.')));
        }
        return;
      }
    }
    await _save(s.copyWith(inactivityAlerts: on));
  }

  Future<void> _setMealReminders(bool on) async {
    final s = _s!;
    if (on && widget.saver == null) {
      final ok = await NotificationService.instance.requestPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications are not allowed for Baymax. Turn them on in your phone settings.')));
        }
        return;
      }
    }
    await _save(s.copyWith(mealReminderEnabled: on));
  }

  Future<void> _pickMealTime() async {
    final s = _s!;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.mealReminderHour, minute: s.mealReminderMinute));
    if (t != null) await _save(s.copyWith(mealReminderHour: t.hour, mealReminderMinute: t.minute));
  }

  Future<void> _pickTime() async {
    final s = _s!;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute));
    if (t != null) await _save(s.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
  }

  Widget _section(String title, IconData icon, List<Widget> children, int index) => Reveal(
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconWell(icon: icon, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary, letterSpacing: -0.2))),
                ]),
                const SizedBox(height: 10),
                ...children,
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final plan = UserSession.instance.plan;
    final days = plan == null ? <int>[] : (ProgressService.plannedWeekdays(plan).toList()..sort());
    final role = UserSession.instance.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders & community')),
      body: s == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _section('Notifications', Icons.notifications_rounded, [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow notifications'),
                    subtitle: const Text('Turn this off to stop every reminder, alert and notification at once. Your Notifications list stops filling up as well.'),
                    value: s.notificationsEnabled,
                    onChanged: (v) => _save(s.copyWith(notificationsEnabled: v)),
                  ),
                ], 0),
                _section('Workout reminders', Icons.alarm_rounded, [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind me on workout days'),
                    subtitle: Text(days.isEmpty ? 'Available once you have a plan.' : 'On your planned days: ${days.map((d) => _dayNames[d - 1]).join(', ')}'),
                    value: s.reminderEnabled,
                    onChanged: plan == null ? null : _setReminders,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: s.reminderEnabled,
                    title: const Text('Reminder time'),
                    trailing: Text(TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute).format(context),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    onTap: s.reminderEnabled ? _pickTime : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind me to log my meals'),
                    subtitle: const Text('A daily reminder to add what you ate.'),
                    value: s.mealReminderEnabled,
                    onChanged: _setMealReminders,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: s.mealReminderEnabled,
                    title: const Text('Meal reminder time'),
                    trailing: Text(TimeOfDay(hour: s.mealReminderHour, minute: s.mealReminderMinute).format(context),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    onTap: s.mealReminderEnabled ? _pickMealTime : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Nudge me if I stop working out'),
                    subtitle: const Text('One reminder, after 3 days without a workout on a planned day.'),
                    value: s.inactivityAlerts,
                    onChanged: plan == null ? null : _setInactivity,
                  ),
                  const Text('Reminders are scheduled on this phone and need no internet. They never show health details on the lock screen.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.45)),
                ], 1),
                _section('Leaderboard', Icons.leaderboard_rounded, [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show me on the weekly leaderboard'),
                    subtitle: const Text('Shares your display name, weekly score and workout and logging counts with other signed-in users.'),
                    value: s.leaderboardOptIn,
                    onChanged: (v) => _save(s.copyWith(leaderboardOptIn: v, displayName: _name.text.trim())),
                  ),
                  TextField(
                    controller: _name,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: 'Display name'),
                    onSubmitted: (v) => _save(s.copyWith(displayName: v.trim())),
                  ),
                ], 2),
                _section('Account role', Icons.badge_rounded, [
                  Text(role.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  const SizedBox(height: 4),
                  Text(
                    role == UserRole.user
                        ? 'Standard member access: you can see and change only your own data. Doctor, nutritionist and trainer access is granted by an administrator.'
                        : 'This role is set by an administrator and cannot be changed in the app.',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45),
                  ),
                ], 3),
              ],
            ),
    );
  }
}

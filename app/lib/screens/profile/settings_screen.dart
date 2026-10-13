import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/gamification.dart';
import '../../services/notification_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_session.dart';
import '../../services/user_settings_service.dart';
import '../../theme/app_theme.dart';

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
      if (widget.saver == null) await NotificationService.instance.refreshFromAccount(UserSession.instance.plan);
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

  Future<void> _pickTime() async {
    final s = _s!;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute));
    if (t != null) await _save(s.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
  }

  Widget _section(String title, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final plan = UserSession.instance.plan;
    final days = plan == null ? <int>[] : (ProgressService.plannedWeekdays(plan).toList()..sort());
    final role = UserSession.instance.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders & community', style: TextStyle(fontSize: 16))),
      body: s == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _section('Workout reminders', [
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
                    title: const Text('Nudge me if I stop working out'),
                    subtitle: const Text('One reminder, after 3 days without a workout on a planned day.'),
                    value: s.inactivityAlerts,
                    onChanged: plan == null ? null : _setInactivity,
                  ),
                  const Text('Reminders are scheduled on this phone and need no internet. They never show health details on the lock screen.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
                ]),
                _section('Leaderboard', [
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
                ]),
                _section('Account role', [
                  Text(role.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  const SizedBox(height: 4),
                  Text(
                    role == UserRole.user
                        ? 'Standard member access: you can see and change only your own data. Doctor, nutritionist and trainer access is granted by an administrator.'
                        : 'This role is set by an administrator and cannot be changed in the app.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ]),
              ],
            ),
    );
  }
}

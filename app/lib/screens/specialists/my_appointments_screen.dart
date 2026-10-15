import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/consultation.dart';
import '../../models/payment.dart';
import '../../services/api_client.dart';
import '../../services/consultation_rules.dart';
import '../../services/consultation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

Color _statusColor(AppointmentStatus s) => switch (s) {
      AppointmentStatus.confirmed => AppTheme.teal,
      AppointmentStatus.completed => AppTheme.primary,
      AppointmentStatus.cancelled => AppTheme.error,
      AppointmentStatus.noShow => AppTheme.warning,
      AppointmentStatus.pendingPayment => AppTheme.warning,
    };

/// Module 14: the member's own appointments, upcoming first, with the meeting link and whatever the specialist wrote afterwards.
class MyAppointmentsScreen extends StatefulWidget {
  final Future<List<Appointment>> Function()? loader;
  final Future<void> Function(Appointment)? onCancel;
  final DateTime Function()? clock;
  const MyAppointmentsScreen({Key? key, this.loader, this.onCancel, this.clock}) : super(key: key);

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  List<Appointment>? _items;
  String? _error;
  bool _loading = true;
  bool _upcomingTab = true;

  DateTime get _now => (widget.clock ?? DateTime.now)();

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
      final list = await (widget.loader ?? () => ConsultationService.instance.loadMine())();
      if (mounted) setState(() => _items = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your appointments.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Appointment a) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointment: a, onCancel: widget.onCancel, clock: widget.clock)),
    );
    if (mounted) _load();
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.card,
          side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
          labelStyle: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : AppTheme.textPrimary),
          onSelected: (_) => onTap(),
        ),
      );

  Widget _card(Appointment a) {
    final now = _now;
    final live = ConsultationRules.canJoin(a, now);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _open(a),
      semanticLabel: '${a.specialistName}, ${ConsultationService.formatDateTime(a.startAt)}, ${a.status.label}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconWell(icon: a.role.icon, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.specialistName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(ConsultationService.formatDateTime(a.startAt), style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              InfoChip(live ? 'Open now' : a.status.label, icon: live ? Icons.sensors_rounded : null, color: live ? AppTheme.teal : _statusColor(a.status)),
              InfoChip(a.type.label, icon: a.type.icon),
              if (a.consultation != null) const InfoChip('Notes from specialist', icon: Icons.description_rounded),
            ]),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _items ?? const <Appointment>[];
    final now = _now;
    final shown = [for (final a in all) if (ConsultationRules.isUpcoming(a, now) == _upcomingTab) a];
    final upcomingCount = all.where((a) => ConsultationRules.isUpcoming(a, now)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('My appointments')),
      body: _loading && _items == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items == null
              ? MessageState(message: _error!, onRetry: _load)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(children: [
                      _tab('Upcoming ($upcomingCount)', _upcomingTab, () => setState(() => _upcomingTab = true)),
                      _tab('Past', !_upcomingTab, () => setState(() => _upcomingTab = false)),
                    ]),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: shown.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 60),
                              MessageState(
                                icon: Icons.event_busy_rounded,
                                message: _upcomingTab ? 'You have no upcoming appointments. Find a specialist to book one.' : 'No past appointments yet.',
                              ),
                            ])
                          : ListView(padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)), children: [for (final a in shown) _card(a)]),
                    ),
                  ),
                ]),
    );
  }
}

/// One appointment: when, with whom, the meeting link, what the member shared, and the specialist's notes and prescription.
class AppointmentDetailScreen extends StatefulWidget {
  final Appointment appointment;
  final Future<void> Function(Appointment)? onCancel;
  final DateTime Function()? clock;
  const AppointmentDetailScreen({Key? key, required this.appointment, this.onCancel, this.clock}) : super(key: key);

  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  late Appointment _a = widget.appointment;
  bool _cancelling = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: Text('${_a.specialistName}, ${ConsultationService.formatDateTime(_a.startAt)}. The time will be offered to other people.${_a.payment?.status == PaymentStatus.paid && _a.payment?.isTest == false ? ' Refunds are not automatic: contact support with your transaction number.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel appointment')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await (widget.onCancel ?? (a) => ConsultationService.instance.cancel(a))(_a);
      if (!mounted) return;
      setState(() => _a = Appointment.fromJson(_a.id, {..._a.toJson(), 'status': AppointmentStatus.cancelled.id})!);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not cancel. Please try again.')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _a.meetingLink));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting link copied. Open it in your browser to join.')));
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final now = _now;
    final canJoin = ConsultationRules.canJoin(a, now);
    final shared = [
      if (a.shares.healthSummary) 'Health summary',
      if (a.shares.foodLog7d) 'Diet log, last 7 days',
      if (a.shares.activity30d) 'Workouts, last 30 days',
    ];
    final note = a.consultation;

    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
        children: [
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconWell(icon: a.role.icon, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.specialistName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textPrimary)),
                    Text('${a.role.label}${a.specialty.isEmpty ? '' : ' · ${a.specialty}'}', style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                  ]),
                ),
                InfoChip(a.status.label, color: _statusColor(a.status)),
              ]),
              const SizedBox(height: 14),
              _row('When', ConsultationService.formatDateTime(a.startAt)),
              _row('Length', '${a.durationMinutes} minutes'),
              _row('Type', a.type.label),
              _row('Fee', ConsultationService.pkr(a.fee)),
            ]),
          ),
          if (a.status == AppointmentStatus.confirmed) ...[
            const SectionHeader('Meeting room', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  canJoin
                      ? 'The room is open now. Copy the link and open it in your browser.'
                      : now.isBefore(a.startAt)
                          ? 'The room opens ${ConsultationRules.joinEarly.inMinutes} minutes before your appointment.'
                          : 'This appointment has ended.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.4, color: canJoin ? AppTheme.teal : AppTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                SelectableText(a.meetingLink, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
                const SizedBox(height: 12),
                GlowButton(label: 'Copy meeting link', icon: Icons.copy_rounded, onPressed: _copy),
              ]),
            ),
          ],
          if (note != null) ...[
            const SectionHeader('From your specialist', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (note.notes.trim().isNotEmpty) ...[
                  const Text('Consultation notes', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(note.notes, style: const TextStyle(height: 1.45, color: AppTheme.textPrimary)),
                ],
                if (note.prescription.trim().isNotEmpty) ...[
                  if (note.notes.trim().isNotEmpty) const SizedBox(height: 14),
                  const Text('Prescription', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(note.prescription, style: const TextStyle(height: 1.45, color: AppTheme.textPrimary)),
                ],
                const SizedBox(height: 10),
                Text('Updated ${ConsultationService.formatDateTime(note.updatedAt)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ]),
            ),
          ],
          if (a.payment != null) ...[
            const SectionHeader('Payment', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
            GlassCard(
              child: Column(children: [
                _row('Status', a.payment!.status == PaymentStatus.paid ? 'Paid' : 'To pay at the clinic'),
                _row('Method', a.payment!.description),
                _row('Transaction', a.payment!.transactionId),
                _row('Consultation fee', ConsultationService.pkr(a.payment!.consultationFee)),
                _row('Platform fee', ConsultationService.pkr(a.payment!.platformFee)),
                _row('Total', ConsultationService.pkr(a.payment!.total)),
                if (a.payment!.isTest)
                  const Padding(padding: EdgeInsets.only(top: 6), child: Text('Test payment: no money was taken.', style: TextStyle(fontSize: 12.5, color: AppTheme.warning, fontWeight: FontWeight.w700))),
              ]),
            ),
          ],
          const SectionHeader('What you shared', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
          GlassCard(
            child: Text(
              shared.isEmpty ? 'Nothing. Your specialist sees only this booking.' : shared.join(', '),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          if (a.notesForSpecialist.isNotEmpty) ...[
            const SectionHeader('Your note', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
            GlassCard(child: Text(a.notesForSpecialist, style: const TextStyle(color: AppTheme.textPrimary, height: 1.45))),
          ],
          if (ConsultationRules.canCancel(a, now)) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancel,
              icon: _cancelling ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.event_busy_rounded),
              label: const Text('Cancel appointment'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Baymax specialists give advice, not emergency care. In an emergency contact emergency services.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

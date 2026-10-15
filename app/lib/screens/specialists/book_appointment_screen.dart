import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/consultation.dart';
import '../../services/api_client.dart';
import '../../services/consultation_rules.dart';
import '../../services/consultation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/glass.dart';
import 'payment_screen.dart';

typedef BookingCallback = Future<Appointment> Function({
  required Specialist specialist,
  required DateTime slot,
  required ConsultType type,
  required SharePrefs shares,
  required String notes,
});

/// Module 14 (FR-2, mockup M36): choose a date, a time and a consultation type, decide what to share, and confirm.
///
/// Confirming holds the chosen time for ten minutes (FR36.8) and opens the payment screen (Module 15). The booking becomes an
/// appointment, and the confirmation is sent, only when payment (or "pay at clinic") is completed there.
class BookAppointmentScreen extends StatefulWidget {
  final Specialist specialist;
  final Future<Set<int>> Function(Specialist)? loadBooked;
  final BookingCallback? book;
  final DateTime Function()? clock;
  final PaymentHooks paymentHooks;

  const BookAppointmentScreen({Key? key, required this.specialist, this.loadBooked, this.book, this.clock, this.paymentHooks = const PaymentHooks()}) : super(key: key);

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  Set<int>? _booked;
  String? _loadError;
  DateTime? _day; // UTC-midnight date in the specialist's time zone
  DateTime? _slot;
  ConsultType _type = ConsultType.video; // FR36.4: video is the recommended default
  SharePrefs _shares = const SharePrefs();
  final _notes = TextEditingController();
  bool _booking = false;
  String? _bookError;

  Specialist get _s => widget.specialist;
  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final booked = await (widget.loadBooked ?? (s) => ConsultationService.instance.loadBookedSlots(s.id))(_s);
      if (!mounted) return;
      setState(() {
        _booked = booked;
        final days = ConsultationRules.upcomingDays(_s, now: _now, booked: booked);
        _day = days.where((d) => d.hasSlots).map((d) => d.day).firstOrNull;
        _slot = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load the available times.');
    }
  }

  Future<void> _confirm() async {
    final problem = ConsultationRules.bookingProblem(specialist: _s, slot: _slot, notes: _notes.text, now: _now, booked: _booked ?? const {});
    if (problem != null) {
      setState(() => _bookError = problem);
      return;
    }
    setState(() {
      _booking = true;
      _bookError = null;
    });
    try {
      final book = widget.book ?? ConsultationService.instance.book;
      final held = await book(specialist: _s, slot: _slot!, type: _type, shares: _shares, notes: _notes.text);
      if (!mounted) return;
      // The payment screen gives the time back if the member leaves it without paying, so the slots are reloaded on return.
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(appointment: held, hooks: widget.paymentHooks, clock: widget.clock)));
      if (mounted) _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _bookError = e.message);
      if (e.statusCode == 409) _load(); // someone took the time: show the fresh list
    } catch (_) {
      if (mounted) setState(() => _bookError = 'Could not book this appointment. Please try again.');
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Widget _dayTile(DayAvailability d) {
    final selected = _day == d.day;
    final enabled = d.hasSlots;
    final fg = selected ? Colors.white : (enabled ? AppTheme.textPrimary : AppTheme.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: '${_wd[d.day.weekday - 1]} ${d.day.day} ${_mo[d.day.month - 1]}${enabled ? '' : ', unavailable'}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: enabled
              ? () => setState(() {
                    _day = d.day;
                    _slot = null;
                  })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.rMedium),
              border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_wd[d.day.weekday - 1], style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(height: 2),
              Text('${d.day.day}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: fg, decoration: enabled ? null : TextDecoration.lineThrough)),
              Text(_mo[d.day.month - 1], style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _typeTile(ConsultType t) {
    final selected = _type == t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        tint: selected ? AppTheme.tint(AppTheme.primary, 0.16) : null,
        padding: const EdgeInsets.all(14),
        semanticLabel: '${t.label}, ${ConsultationService.pkr(_s.feeFor(t))}${selected ? ', selected' : ''}',
        onTap: () => setState(() => _type = t),
        child: Row(children: [
          IconWell(icon: t.icon, size: 44, filled: selected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(t.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
                if (t == ConsultType.video) const InfoChip('Recommended', icon: Icons.thumb_up_alt_rounded),
              ]),
              const SizedBox(height: 2),
              Text(
                t == ConsultType.video ? 'See and hear your specialist.' : 'Text chat in the meeting room, camera and microphone off.',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(ConsultationService.pkr(_s.feeFor(t)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textPrimary)),
          const SizedBox(width: 6),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppTheme.primary : AppTheme.textSecondary),
        ]),
      ),
    );
  }

  Widget _share(String title, String detail, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: _booking ? null : (v) => onChanged(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35)),
    );
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
    final booked = _booked;
    final days = booked == null ? const <DayAvailability>[] : ConsultationRules.upcomingDays(_s, now: _now, booked: booked);
    final slots = (booked == null || _day == null) ? const <DateTime>[] : ConsultationRules.openSlots(_s, _day!, now: _now, booked: booked);
    final canConfirm = _slot != null && !_booking;

    return Scaffold(
      appBar: AppBar(title: const Text('Book appointment')),
      body: _loadError != null && booked == null
          ? MessageState(message: _loadError!, onRetry: _load)
          : booked == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
                  children: [
                    GlassCard(
                      child: Row(children: [
                        IconWell(icon: _s.type.icon, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_s.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textPrimary)),
                            Text('${_s.type.label} · ${_s.specialty}', style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            _s.reviewCount == 0
                                ? const Text('No reviews yet', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))
                                : Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
                                    const SizedBox(width: 3),
                                    Text('${_s.rating.toStringAsFixed(1)} (${_s.reviewCount} reviews)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                  ]),
                          ]),
                        ),
                      ]),
                    ),
                    if (_s.bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(_s.bio, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.45)),
                      ),
                    const SectionHeader('Date', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
                    if (!days.any((d) => d.hasSlots))
                      const GlassCard(child: Text('There are no open times in the next two weeks. Please check again later.', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, height: 1.4)))
                    else
                      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final d in days) _dayTile(d)])),
                    if (slots.isNotEmpty) ...[
                      const SectionHeader('Time', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final t in slots)
                          SelectChip(label: ConsultationService.formatTime(t), selected: _slot == t, onTap: () => setState(() => _slot = t)),
                      ]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 0, 0),
                        child: Text('Times are shown in your phone\'s time zone. One time can be chosen.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withOpacity(0.95))),
                      ),
                    ],
                    const SectionHeader('Consultation type', padding: EdgeInsets.fromLTRB(2, 22, 0, 10)),
                    for (final t in ConsultType.values) _typeTile(t),
                    const SectionHeader('Share with your specialist', padding: EdgeInsets.fromLTRB(2, 16, 0, 4)),
                    const Text('Nothing is shared unless you tick it. The specialist sees it only for this appointment.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
                    _share('Health summary', 'Age, goal, BMI, health class, conditions, allergies and medicines.', _shares.healthSummary, (v) => setState(() => _shares = _shares.copyWith(healthSummary: v))),
                    _share('Diet log, last 7 days', 'Meals and calories you logged this week.', _shares.foodLog7d, (v) => setState(() => _shares = _shares.copyWith(foodLog7d: v))),
                    _share('Workouts, last 30 days', 'The days you completed a workout, with minutes.', _shares.activity30d, (v) => setState(() => _shares = _shares.copyWith(activity30d: v))),
                    const SectionHeader('Notes for the specialist (optional)', padding: EdgeInsets.fromLTRB(2, 12, 0, 8)),
                    TextField(
                      controller: _notes,
                      maxLines: 4,
                      maxLength: ConsultationRules.maxNoteLength,
                      inputFormatters: [LengthLimitingTextInputFormatter(ConsultationRules.maxNoteLength)],
                      enabled: !_booking,
                      decoration: const InputDecoration(hintText: 'What would you like help with?'),
                    ),
                    const SectionHeader('Booking summary', padding: EdgeInsets.fromLTRB(2, 12, 0, 8)),
                    GlassCard(
                      child: Column(children: [
                        _row('Specialist', _s.displayName),
                        _row('Role', _s.type.label),
                        _row('Date and time', _slot == null ? 'Not chosen yet' : ConsultationService.formatDateTime(_slot!)),
                        _row('Type', _type.label),
                        const Divider(height: 20),
                        _row('Total fee', ConsultationService.pkr(_s.feeFor(_type))),
                      ]),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 10, 4, 14),
                      child: Text(
                        'You pay on the next screen. Your time is held for 10 minutes while you do, and given back if you leave without paying.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ),
                    if (_bookError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_bookError!, style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, height: 1.4)),
                        ),
                      ),
                    GlowButton(label: 'Confirm booking', icon: Icons.lock_rounded, loading: _booking, onPressed: canConfirm ? _confirm : null),
                  ],
                ),
    );
  }
}

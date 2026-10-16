import 'package:flutter/material.dart';
import '../../models/consultation.dart';
import '../../services/api_client.dart';
import '../../services/consultation_rules.dart';
import '../../services/consultation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../chatbot/chatbot_screen.dart';
import 'book_appointment_screen.dart';
import 'my_appointments_screen.dart';
import 'payment_screen.dart';

/// What the list needs: the specialists and the earliest open slot of each.
class SpecialistsData {
  final List<Specialist> specialists;
  final Map<String, DateTime?> nextSlots;
  const SpecialistsData(this.specialists, this.nextSlots);
}

Future<SpecialistsData> _loadFromDatabase() async {
  final list = await ConsultationService.instance.loadSpecialists();
  return SpecialistsData(list, await ConsultationService.instance.loadNextSlots(list));
}

/// Module 14 (FR-1, mockup M35): find a doctor, nutritionist or trainer, then book.
class SpecialistsScreen extends StatefulWidget {
  final Future<SpecialistsData> Function()? loader;
  final DateTime Function()? clock;

  /// Passed on to the booking screen (tests and previews replace them).
  final Future<Set<int>> Function(Specialist)? loadBooked;
  final BookingCallback? book;
  final Future<List<Appointment>> Function()? loadAppointments;
  final PaymentHooks paymentHooks;

  const SpecialistsScreen({Key? key, this.loader, this.clock, this.loadBooked, this.book, this.loadAppointments, this.paymentHooks = const PaymentHooks()}) : super(key: key);

  @override
  State<SpecialistsScreen> createState() => _SpecialistsScreenState();
}

class _SpecialistsScreenState extends State<SpecialistsScreen> {
  SpecialistsData? _data;
  String? _error;
  bool _loading = true;

  SpecialistType? _type; // null = all
  String _query = '';
  bool _availableToday = false, _topRated = false, _emergency = false;

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
      final d = await (widget.loader ?? _loadFromDatabase)();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the specialists.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 18, color: selected ? Colors.white : AppTheme.primary),
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
  }

  void _book(Specialist s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookAppointmentScreen(specialist: s, loadBooked: widget.loadBooked, book: widget.book, clock: widget.clock, paymentHooks: widget.paymentHooks)),
    ).then((_) => _load());
  }

  Widget _stars(Specialist s) {
    if (s.reviewCount == 0) return const InfoChip('New', icon: Icons.fiber_new_rounded);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
      const SizedBox(width: 3),
      Text(s.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.textPrimary)),
      const SizedBox(width: 4),
      Text('(${s.reviewCount})', style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _card(Specialist s, int index) {
    final next = _data!.nextSlots[s.id];
    final canBook = s.available && next != null;
    final nextText = !s.available
        ? 'Not taking bookings'
        : next == null
            ? 'No open times in the next ${ConsultationRules.bookingDays} days'
            : 'Next: ${ConsultationService.relativeDay(next, _now)}, ${ConsultationService.formatTime(next)}';
    return Reveal(
      index: index.clamp(0, 6),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        semanticLabel: '${s.displayName}, ${s.type.label}, ${s.specialty}. $nextText',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconWell(icon: s.type.icon, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text('${s.type.label} · ${s.specialty}', style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _stars(s),
                  if (s.yearsOfExperience > 0) InfoChip('${s.yearsOfExperience} yrs experience', icon: Icons.workspace_premium_rounded),
                  if (s.verified) const InfoChip('Verified', icon: Icons.verified_rounded, color: AppTheme.teal),
                  if (s.emergency && s.available) const InfoChip('Emergency', icon: Icons.emergency_rounded, color: AppTheme.error),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nextText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: canBook ? AppTheme.teal : AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text('From ${ConsultationService.pkr(s.chatFee < s.videoFee ? s.chatFee : s.videoFee)}', style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: canBook ? () => _book(s) : null, child: const Text('Book')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading && _data == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _data == null) {
      body = MessageState(message: _error!, onRetry: _load);
    } else {
      final data = _data!;
      final shown = ConsultationRules.filter(
        data.specialists,
        type: _type,
        query: _query,
        availableToday: _availableToday,
        topRated: _topRated,
        emergency: _emergency,
        now: _now,
        nextSlots: data.nextSlots,
      );
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(hintText: 'Search by name, specialty or keyword', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('All', _type == null, () => setState(() => _type = null)),
                for (final t in SpecialistType.values) _chip(t.label, _type == t, () => setState(() => _type = t), icon: t.icon),
              ]),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('Available today', _availableToday, () => setState(() => _availableToday = !_availableToday)),
                _chip('Top rated', _topRated, () => setState(() => _topRated = !_topRated)),
                _chip('Emergency', _emergency, () => setState(() => _emergency = !_emergency)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
              child: Semantics(
                liveRegion: true,
                child: Text(ConsultationRules.countLabel(shown.length, _type), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
              ),
            ),
            if (shown.isEmpty)
              GlassCard(
                child: Text(
                  data.specialists.isEmpty
                      ? 'No specialists have joined yet. Please check back soon.'
                      : 'No specialist matches these filters. Try clearing a filter or the search.',
                  style: const TextStyle(color: AppTheme.textPrimary, height: 1.45, fontWeight: FontWeight.w600),
                ),
              )
            else
              for (var i = 0; i < shown.length; i++) _card(shown[i], i),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Ask the Baymax chatbot first'),
            ),
            const SizedBox(height: 16),
            const Text(
              'If you have chest pain, fainting, severe breathlessness or any emergency symptom, contact emergency services or go to a hospital now. Booked consultations are not an emergency service.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a specialist'),
        actions: [
          IconButton(
            tooltip: 'My appointments',
            icon: const Icon(Icons.event_note_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyAppointmentsScreen(loader: widget.loadAppointments, clock: widget.clock))),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }
}

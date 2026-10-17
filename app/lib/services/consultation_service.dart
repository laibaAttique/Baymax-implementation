import '../models/app_notification.dart';
import '../models/consultation.dart';
import 'consultation_rules.dart';
import '../models/payment.dart';
import 'inbox_service.dart';
import 'payment_rules.dart';
import 'realtime_db.dart';
import 'user_session.dart';
import 'api_client.dart' show ApiException;

/// Module 14: reads specialists and slots, books and cancels appointments, in the Realtime Database that the specialist web portal
/// also uses. Database layout (rules in `database.rules.json`):
///
/// * `specialists/{uid}` public profile, written only by the portal's administrator tooling.
/// * `slots/{specialistId}/{startMs}` = `{appt, holdUntil?}`. Creating it is what holds the time: a second person cannot create the same
///   key while it exists. `holdUntil` is present while the booking waits for payment (ten minutes); an expired hold can be taken over.
/// * `appointments/{id}` the booking (`pending_payment` until paid, then `confirmed`); the member and the specialist can read it; the
///   specialist's notes are added by the portal.
/// * `users/{uid}/appointmentIds/{id}` = start time: the member's own index, so their list needs no query across all bookings.
class ConsultationService {
  ConsultationService._();
  static final ConsultationService instance = ConsultationService._();

  Future<List<Specialist>> loadSpecialists() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.db.ref('specialists').get();
      if (!snap.exists) return <Specialist>[];
      final raw = RealtimeDb.plain(snap.value);
      if (raw is! Map) return <Specialist>[];
      return [
        for (final e in raw.entries)
          if (Specialist.fromJson(e.key as String, e.value) case final s?) s,
      ];
    });
  }

  /// Start times (ms) already booked for [specialistId] from [from] onwards.
  Future<Set<int>> loadBookedSlots(String specialistId, {DateTime? from}) {
    return RealtimeDb.guard(() async {
      final start = (from ?? DateTime.now()).toUtc().subtract(const Duration(hours: 1)).millisecondsSinceEpoch.toString();
      final snap = await RealtimeDb.db.ref('slots/$specialistId').orderByKey().startAt(start).get();
      if (!snap.exists) return <int>{};
      final raw = RealtimeDb.plain(snap.value);
      if (raw is! Map) return <int>{};
      final nowMs = (from ?? DateTime.now()).millisecondsSinceEpoch;
      return {
        for (final e in raw.entries)
          // A slot held for a payment that never came is free again once the hold runs out.
          if (int.tryParse(e.key.toString()) case final ms? when !_holdExpired(e.value, nowMs)) ms,
      };
    });
  }

  static bool _holdExpired(Object? slot, int nowMs) {
    if (slot is! Map) return false;
    final until = slot['holdUntil'];
    return until is num && until <= nowMs;
  }

  /// The earliest open slot of every specialist, for the "next available" line on the list.
  Future<Map<String, DateTime?>> loadNextSlots(List<Specialist> specialists, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final out = <String, DateTime?>{};
    await Future.wait(specialists.map((s) async {
      try {
        out[s.id] = ConsultationRules.nextSlot(s, now: t, booked: await loadBookedSlots(s.id, from: t));
      } catch (_) {
        out[s.id] = null;
      }
    }));
    return out;
  }

  /// Holds [slot] with [specialist] for [PaymentRules.holdDuration] while the member pays (FR36.8). The appointment (status
  /// `pending_payment`), the slot lock and the member's index are written in one atomic update, so either all of it exists or none
  /// of it does. The rules refuse it if someone else holds the slot. Nothing is confirmed and no notification is sent until
  /// [confirmPayment].
  Future<Appointment> book({
    required Specialist specialist,
    required DateTime slot,
    required ConsultType type,
    required SharePrefs shares,
    String notes = '',
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final uid = RealtimeDb.uid;
    final booked = await loadBookedSlots(specialist.id, from: t);
    final problem = ConsultationRules.bookingProblem(specialist: specialist, slot: slot, notes: notes, now: t, booked: booked);
    if (problem != null) throw ApiException(problem);

    final ref = RealtimeDb.db.ref('appointments').push();
    final id = ref.key!;
    final appointment = Appointment(
      id: id,
      patientId: uid,
      patientName: _patientName(),
      specialistId: specialist.id,
      specialistName: specialist.displayName,
      role: specialist.type,
      specialty: specialist.specialty,
      startAt: slot,
      durationMinutes: specialist.availability.slotMinutes,
      type: type,
      status: AppointmentStatus.pendingPayment,
      fee: specialist.feeFor(type),
      notesForSpecialist: notes.trim(),
      shares: shares,
      createdAt: t,
      holdUntil: t.add(PaymentRules.holdDuration),
    );
    try {
      await RealtimeDb.guard(() => RealtimeDb.db.ref().update({
            'appointments/$id': appointment.toJson(),
            'slots/${specialist.id}/${ConsultationRules.slotKey(slot)}': {'appt': id, 'holdUntil': appointment.holdUntil!.millisecondsSinceEpoch},
            'users/$uid/appointmentIds/$id': slot.toUtc().millisecondsSinceEpoch,
          }));
    } on ApiException catch (e) {
      // The only write a member can lose is the slot: someone else took it between our check and our write.
      if (e.statusCode == 403) throw const ApiException('That time was just taken by someone else. Please choose another.', statusCode: 409);
      rethrow;
    }
    return appointment;
  }

  /// Gives the time back (the member left the payment screen, or the hold ran out). Best effort: an unreleased hold expires by itself.
  Future<void> releaseHold(Appointment a) async {
    try {
      await RealtimeDb.guard(() => RealtimeDb.db.ref().update({
            'appointments/${a.id}/status': AppointmentStatus.cancelled.id,
            'slots/${a.specialistId}/${ConsultationRules.slotKey(a.startAt)}': null,
          }));
    } catch (_) {}
  }

  /// Turns a held booking into a request to the specialist once payment succeeded (or pay-at-clinic was chosen), drops the hold, and
  /// sends the notification (FR36.8). One atomic update. The specialist accepts it in the portal, which creates the video room.
  Future<Appointment> submitRequest(Appointment a, PaymentRecord payment) async {
    final key = ConsultationRules.slotKey(a.startAt);
    await RealtimeDb.guard(() => RealtimeDb.db.ref().update({
          'appointments/${a.id}/payment': payment.toJson(),
          'appointments/${a.id}/status': AppointmentStatus.requested.id,
          'appointments/${a.id}/holdUntil': null,
          'slots/${a.specialistId}/$key/holdUntil': null,
        }));
    final sent = a.copyWith(status: AppointmentStatus.requested, payment: payment, clearHold: true);
    await _notifyRequested(sent);
    return sent;
  }

  /// The platform fee in PKR, from `config/payments/platformFee`; zero when it is not set (FR37.7).
  Future<int> loadPlatformFee() async {
    try {
      return await RealtimeDb.guard(() async {
        final snap = await RealtimeDb.db.ref('config/payments/platformFee').get();
        final v = snap.exists ? snap.value : null;
        return v is num && v >= 0 ? v.toInt() : 0;
      });
    } catch (_) {
      return 0;
    }
  }

  Future<void> _notifyRequested(Appointment a) async {
    try {
      await InboxService.instance.add(
        AppNotification(
          id: 'appt-${a.id}',
          type: NotificationType.appointment,
          title: 'Request sent',
          body: '${a.specialistName} will confirm ${formatDateTime(a.startAt)}. You will get a notification with the video link when they accept.',
          createdAt: DateTime.now(),
          route: 'appointments',
        ),
        alsoOnPhone: true,
      );
    } catch (_) {
      // The booking already succeeded; a missing notification must not look like a failed booking.
    }
  }

  /// The member's appointments, soonest upcoming first, then the past.
  Future<List<Appointment>> loadMine({DateTime? now}) {
    return RealtimeDb.guard(() async {
      final index = await RealtimeDb.userRef('appointmentIds').get();
      if (!index.exists) return <Appointment>[];
      final ids = (RealtimeDb.plain(index.value) as Map).keys.map((k) => k.toString()).toList();
      final loaded = await Future.wait(ids.map((id) async {
        try {
          final snap = await RealtimeDb.db.ref('appointments/$id').get();
          return snap.exists ? Appointment.fromJson(id, RealtimeDb.plain(snap.value)) : null;
        } catch (_) {
          return null;
        }
      }));
      return ConsultationRules.sortForList([for (final a in loaded) if (a != null) a], now ?? DateTime.now());
    });
  }

  /// Cancels a request or an accepted appointment that has not started and frees its slot. Atomic, like [book].
  Future<void> cancel(Appointment a, {DateTime? now}) {
    if (!ConsultationRules.canCancel(a, now ?? DateTime.now())) {
      throw const ApiException('This appointment can no longer be cancelled.');
    }
    return RealtimeDb.guard(() => RealtimeDb.db.ref().update({
          'appointments/${a.id}/status': AppointmentStatus.cancelled.id,
          'slots/${a.specialistId}/${ConsultationRules.slotKey(a.startAt)}': null,
        }));
  }

  String _patientName() {
    final n = UserSession.instance.profile?.fullName.trim() ?? '';
    return n.isEmpty ? 'Baymax member' : (n.length > 60 ? n.substring(0, 60) : n);
  }

  // ---- formatting shared by the screens ----------------------------------------------------------------------------------------

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String formatTime(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String formatDate(DateTime t) {
    final l = t.toLocal();
    return '${_weekdays[l.weekday - 1]}, ${l.day} ${_months[l.month - 1]}';
  }

  static String formatDateTime(DateTime t) => '${formatDate(t)}, ${formatTime(t)}';

  /// "Today", "Tomorrow" or the date, for the next-available line.
  static String relativeDay(DateTime t, DateTime now) {
    final l = t.toLocal(), n = now.toLocal();
    final days = DateTime(l.year, l.month, l.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return formatDate(t);
  }

  static String pkr(int amount) => 'PKR ${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
}

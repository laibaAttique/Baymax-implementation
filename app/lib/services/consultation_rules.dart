import 'dart:math';
import '../models/consultation.dart';

/// Module 14: the booking rules, as pure functions (no database, no clock of their own) so they can be tested and the web portal
/// can apply the same ones.
class ConsultationRules {
  ConsultationRules._();

  /// A member can open the meeting room this long before the start (FR10.5 uses the same five minutes for the specialist).
  static const joinEarly = Duration(minutes: 5);

  /// A specialist can open the member's shared data this long before the start (FR10.6).
  static const prepareEarly = Duration(minutes: 30);

  /// The longest note a member may leave for the specialist (FR36.6).
  static const maxNoteLength = 500;

  /// How far ahead a member can book.
  static const bookingDays = 14;

  /// Slots must start at least this far in the future, so nobody books a session that is already starting.
  static const minLead = Duration(minutes: 15);

  // ---- slots -------------------------------------------------------------------------------------------------------------------

  /// A calendar day in the specialist's own time zone.
  static DateTime _utcMidnight(int y, int m, int d) => DateTime.utc(y, m, d);

  /// The calendar day of the instant [now] in the specialist's time zone, as a UTC-midnight date.
  static DateTime specialistToday(Specialist s, DateTime now) {
    final shifted = now.toUtc().add(Duration(minutes: s.tzOffsetMinutes));
    return _utcMidnight(shifted.year, shifted.month, shifted.day);
  }

  /// Every slot start the specialist offers on [day] (a UTC-midnight date meaning a calendar day in their time zone), before any
  /// booking or lead-time filter. Empty on a day off.
  static List<DateTime> daySlots(Specialist s, DateTime day) {
    final a = s.availability;
    if (!a.days.contains(day.weekday)) return const [];
    final base = _utcMidnight(day.year, day.month, day.day).millisecondsSinceEpoch;
    final out = <DateTime>[];
    for (var m = a.startMinute; m + a.slotMinutes <= a.endMinute; m += a.slotMinutes) {
      out.add(DateTime.fromMillisecondsSinceEpoch(base + (m - s.tzOffsetMinutes) * 60000, isUtc: true));
    }
    return out;
  }

  /// The slots a member can actually pick on [day]: in the future by [minLead], and not already [booked] (start times in ms).
  /// Empty when the specialist is not taking bookings.
  static List<DateTime> openSlots(Specialist s, DateTime day, {required DateTime now, Set<int> booked = const {}}) {
    if (!s.available) return const [];
    final earliest = now.toUtc().add(minLead);
    return [
      for (final t in daySlots(s, day))
        if (!t.isBefore(earliest) && !booked.contains(t.millisecondsSinceEpoch)) t,
    ];
  }

  /// The next [bookingDays] calendar days (in the specialist's time zone) starting today, each with whether anything is open.
  static List<DayAvailability> upcomingDays(Specialist s, {required DateTime now, Set<int> booked = const {}}) {
    final today = specialistToday(s, now);
    return [
      for (var i = 0; i < bookingDays; i++)
        () {
          final day = today.add(Duration(days: i));
          return DayAvailability(day, openSlots(s, day, now: now, booked: booked).length);
        }(),
    ];
  }

  /// The earliest open slot within the booking window, or null.
  static DateTime? nextSlot(Specialist s, {required DateTime now, Set<int> booked = const {}}) {
    for (final d in upcomingDays(s, now: now, booked: booked)) {
      if (d.openCount == 0) continue;
      return openSlots(s, d.day, now: now, booked: booked).first;
    }
    return null;
  }

  // ---- the specialist list -----------------------------------------------------------------------------------------------------

  /// Applies the Find-a-specialist controls together (FR35.1 to FR35.3): the search text matches name, specialty, bio and type;
  /// "Available today" needs an open slot on the member's own calendar day; "Top rated" is 4.5 stars or more.
  static List<Specialist> filter(
    List<Specialist> all, {
    SpecialistType? type,
    String query = '',
    bool availableToday = false,
    bool topRated = false,
    bool emergency = false,
    required DateTime now,
    Map<String, DateTime?> nextSlots = const {},
  }) {
    final q = query.trim().toLowerCase();
    final todayLocal = DateTime(now.year, now.month, now.day);
    final out = all.where((s) {
      if (type != null && s.type != type) return false;
      if (q.isNotEmpty && !('${s.name} ${s.specialty} ${s.bio} ${s.type.label}'.toLowerCase().contains(q))) return false;
      if (topRated && !(s.rating >= 4.5 && s.reviewCount > 0)) return false;
      if (emergency && !(s.emergency && s.available)) return false;
      if (availableToday) {
        final next = nextSlots[s.id]?.toLocal();
        if (next == null || DateTime(next.year, next.month, next.day) != todayLocal) return false;
      }
      return true;
    }).toList();
    // Best rated first, then the most reviewed, then by name so the order is stable.
    out.sort((a, b) {
      final r = b.rating.compareTo(a.rating);
      if (r != 0) return r;
      final c = b.reviewCount.compareTo(a.reviewCount);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return out;
  }

  /// "24 Nutritionists Found" (FR35.6).
  static String countLabel(int count, SpecialistType? type) {
    final noun = type == null ? (count == 1 ? 'Specialist' : 'Specialists') : (count == 1 ? type.label : type.plural);
    return '$count $noun Found';
  }

  // ---- booking -----------------------------------------------------------------------------------------------------------------

  /// Why a booking cannot go ahead, or null when it can.
  static String? bookingProblem({
    required Specialist specialist,
    required DateTime? slot,
    required String notes,
    required DateTime now,
    Set<int> booked = const {},
  }) {
    if (!specialist.available) return 'This specialist is not taking bookings right now.';
    if (slot == null) return 'Choose a date and a time.';
    if (booked.contains(slot.millisecondsSinceEpoch)) return 'That time was just taken. Please choose another.';
    if (slot.isBefore(now.toUtc().add(minLead))) return 'That time is too soon. Please choose a later one.';
    if (!daySlots(specialist, specialistToday(specialist, slot)).any((t) => t.millisecondsSinceEpoch == slot.millisecondsSinceEpoch)) {
      return 'That time is outside the specialist\'s working hours.';
    }
    if (notes.length > maxNoteLength) return 'Notes can be at most $maxNoteLength characters.';
    return null;
  }

  /// The database key of a slot: the start instant in milliseconds, which sorts correctly as text.
  static String slotKey(DateTime start) => start.toUtc().millisecondsSinceEpoch.toString();

  /// An unguessable room name, so only people given the link can enter (the link is shared only with the two people booked).
  static String newRoomName([Random? random]) {
    final r = random ?? Random.secure();
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    return 'baymax-${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  /// The meeting link for a booking. [base] is the meeting service (a self-hosted Jitsi Meet in production). A chat-only booking
  /// opens the room with camera and microphone off.
  static String meetingLink(String base, String room, ConsultType type) {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final hash = type == ConsultType.chat ? '#config.startWithVideoMuted=true&config.startWithAudioMuted=true' : '';
    return '$trimmed/$room$hash';
  }

  // ---- an existing appointment -------------------------------------------------------------------------------------------------

  /// The meeting room can be opened from [joinEarly] before the start until the slot ends.
  static bool canJoin(Appointment a, DateTime now) =>
      a.status == AppointmentStatus.confirmed && !now.isBefore(a.startAt.subtract(joinEarly)) && now.isBefore(a.endAt);

  /// Cancelling is allowed while the appointment is confirmed and has not started.
  static bool canCancel(Appointment a, DateTime now) => a.status == AppointmentStatus.confirmed && now.isBefore(a.startAt);

  static bool isUpcoming(Appointment a, DateTime now) => a.status == AppointmentStatus.confirmed && now.isBefore(a.endAt);

  /// Upcoming first (soonest first), then the past (latest first). Bookings still waiting for payment are not appointments yet and
  /// are left out.
  static List<Appointment> sortForList(List<Appointment> all, DateTime now) {
    final list = all.where((a) => a.status != AppointmentStatus.pendingPayment).toList();
    final upcoming = list.where((a) => isUpcoming(a, now)).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
    final past = list.where((a) => !isUpcoming(a, now)).toList()..sort((a, b) => b.startAt.compareTo(a.startAt));
    return [...upcoming, ...past];
  }
}

class DayAvailability {
  /// UTC-midnight date in the specialist's time zone.
  final DateTime day;
  final int openCount;
  const DayAvailability(this.day, this.openCount);
  bool get hasSlots => openCount > 0;
}

import 'package:flutter/material.dart';
import 'payment.dart';

/// Module 14 (Online Consultation): the data shapes shared by the app and the specialist web portal.
/// Both talk to the same Firebase Realtime Database; the layout is described in `database.rules.json`.

/// The kinds of specialist a member can book (FR-1).
enum SpecialistType { doctor, nutritionist, trainer }

extension SpecialistTypeInfo on SpecialistType {
  String get id => name;

  String get label => const ['Doctor', 'Nutritionist', 'Trainer'][index];

  String get plural => const ['Doctors', 'Nutritionists', 'Trainers'][index];

  IconData get icon => const [Icons.medical_services_rounded, Icons.restaurant_menu_rounded, Icons.fitness_center_rounded][index];

  static SpecialistType? fromId(Object? id) {
    for (final t in SpecialistType.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// How the member meets the specialist (FR36.4). Both get a meeting room link; a chat-only booking opens the room with camera and
/// microphone off, and the conversation happens in the room's text chat.
enum ConsultType { video, chat }

extension ConsultTypeInfo on ConsultType {
  String get id => name;

  String get label => const ['Video call', 'Chat only'][index];

  IconData get icon => const [Icons.videocam_rounded, Icons.chat_bubble_rounded][index];

  static ConsultType? fromId(Object? id) {
    for (final t in ConsultType.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// `pendingPayment` is a booking whose time is being held for up to ten minutes while the member pays (FR36.8).
enum AppointmentStatus { confirmed, completed, cancelled, noShow, pendingPayment }

extension AppointmentStatusInfo on AppointmentStatus {
  /// Stored in the database.
  String get id => const ['confirmed', 'completed', 'cancelled', 'no_show', 'pending_payment'][index];

  String get label => const ['Confirmed', 'Completed', 'Cancelled', 'Missed', 'Awaiting payment'][index];

  static AppointmentStatus? fromId(Object? id) {
    for (final s in AppointmentStatus.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// The weekly working pattern a specialist publishes. Times are minutes after midnight in the specialist's own time zone
/// ([tzOffsetMinutes] east of UTC; Pakistan is +300), so a slot is the same instant for every viewer.
class Availability {
  /// ISO weekdays, Monday = 1 … Sunday = 7.
  final Set<int> days;
  final int startMinute;
  final int endMinute;
  final int slotMinutes;

  const Availability({this.days = const {1, 2, 3, 4, 5}, this.startMinute = 9 * 60, this.endMinute = 17 * 60, this.slotMinutes = 30});

  static int? parseClock(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(v);
    return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static String clock(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// Null when the stored value is unusable (no days, a backwards or empty window, a slot length outside 10–120 minutes).
  static Availability? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawDays = raw['days'];
    final days = <int>{};
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is num && d >= 1 && d <= 7) days.add(d.toInt());
      }
    }
    final start = parseClock(raw['start']);
    final end = parseClock(raw['end']);
    final slot = raw['slotMinutes'];
    if (days.isEmpty || start == null || end == null || end <= start || slot is! num || slot < 10 || slot > 120) return null;
    return Availability(days: days, startMinute: start, endMinute: end, slotMinutes: slot.toInt());
  }

  Map<String, Object?> toJson() => {
        'days': (days.toList()..sort()),
        'start': clock(startMinute),
        'end': clock(endMinute),
        'slotMinutes': slotMinutes,
      };
}

/// A specialist's public profile, `specialists/{uid}`. Written only by the portal's administrator tooling; members read it.
class Specialist {
  final String id;
  final String name;
  final SpecialistType type;
  final String specialty;
  final String bio;
  final int yearsOfExperience;
  final double rating;
  final int reviewCount;

  /// Fees in PKR per consultation type (FR36.7).
  final int videoFee;
  final int chatFee;
  final bool available;

  /// Takes urgent bookings (the "Emergency" filter, FR35.3).
  final bool emergency;
  final int tzOffsetMinutes;
  final Availability availability;

  const Specialist({
    required this.id,
    required this.name,
    required this.type,
    required this.specialty,
    this.bio = '',
    this.yearsOfExperience = 0,
    this.rating = 0,
    this.reviewCount = 0,
    required this.videoFee,
    required this.chatFee,
    this.available = true,
    this.emergency = false,
    this.tzOffsetMinutes = 300,
    this.availability = const Availability(),
  });

  int feeFor(ConsultType t) => t == ConsultType.video ? videoFee : chatFee;

  /// The name as patients know it: doctors are addressed as Dr. unless the name already says so.
  String get displayName => type == SpecialistType.doctor && !name.toLowerCase().startsWith('dr') ? 'Dr. $name' : name;

  /// Null when a required field is missing or malformed, so one bad record never breaks the whole list.
  static Specialist? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final type = SpecialistTypeInfo.fromId(raw['type']);
    final name = raw['name'];
    final fees = raw['fees'];
    final availability = Availability.fromJson(raw['availability']);
    if (type == null || name is! String || name.trim().isEmpty || fees is! Map || availability == null) return null;
    final video = fees['video'], chat = fees['chat'];
    if (video is! num || chat is! num || video < 0 || chat < 0) return null;
    return Specialist(
      id: id,
      name: name.trim(),
      type: type,
      specialty: (raw['specialty'] as String?) ?? type.label,
      bio: (raw['bio'] as String?) ?? '',
      yearsOfExperience: ((raw['yearsOfExperience'] as num?) ?? 0).toInt(),
      rating: ((raw['rating'] as num?) ?? 0).toDouble(),
      reviewCount: ((raw['reviewCount'] as num?) ?? 0).toInt(),
      videoFee: video.toInt(),
      chatFee: chat.toInt(),
      available: raw['available'] != false,
      emergency: raw['emergency'] == true,
      tzOffsetMinutes: ((raw['tzOffsetMinutes'] as num?) ?? 300).toInt(),
      availability: availability,
    );
  }
}

/// What the member agreed to share with the specialist (FR36.5). Nothing is shared unless its box was ticked.
class SharePrefs {
  final bool healthSummary;
  final bool foodLog7d;
  final bool activity30d;

  const SharePrefs({this.healthSummary = false, this.foodLog7d = false, this.activity30d = false});

  bool get any => healthSummary || foodLog7d || activity30d;

  Map<String, Object?> toJson() => {'healthSummary': healthSummary, 'foodLog7d': foodLog7d, 'activity30d': activity30d};

  static SharePrefs fromJson(Object? raw) => raw is Map
      ? SharePrefs(healthSummary: raw['healthSummary'] == true, foodLog7d: raw['foodLog7d'] == true, activity30d: raw['activity30d'] == true)
      : const SharePrefs();

  SharePrefs copyWith({bool? healthSummary, bool? foodLog7d, bool? activity30d}) =>
      SharePrefs(healthSummary: healthSummary ?? this.healthSummary, foodLog7d: foodLog7d ?? this.foodLog7d, activity30d: activity30d ?? this.activity30d);
}

/// What the specialist wrote after the session (FR-6, FR-8). Written by the portal; the member reads it.
class ConsultationNote {
  final String notes;
  final String prescription;
  final DateTime updatedAt;

  const ConsultationNote({this.notes = '', this.prescription = '', required this.updatedAt});

  bool get isEmpty => notes.trim().isEmpty && prescription.trim().isEmpty;

  static ConsultationNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final n = ConsultationNote(
      notes: (raw['notes'] as String?) ?? '',
      prescription: (raw['prescription'] as String?) ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(((raw['updatedAt'] as num?) ?? 0).toInt()),
    );
    return n.isEmpty ? null : n;
  }
}

/// A booking, `appointments/{id}`. Its `slotKey` is the start time in ms and the key of the locked slot in `slots/{specialistId}`.
class Appointment {
  final String id;
  final String patientId;
  final String patientName;
  final String specialistId;
  final String specialistName;
  final SpecialistType role;
  final String specialty;
  final DateTime startAt;
  final int durationMinutes;
  final ConsultType type;
  final AppointmentStatus status;
  final int fee;
  final String meetingLink;
  final String notesForSpecialist;
  final SharePrefs shares;
  final DateTime createdAt;
  final ConsultationNote? consultation;

  /// While [status] is `pendingPayment`: when the hold on the time runs out.
  final DateTime? holdUntil;

  /// Set when the booking was confirmed by payment (or by choosing to pay at the clinic).
  final PaymentRecord? payment;

  const Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.specialistId,
    required this.specialistName,
    required this.role,
    this.specialty = '',
    required this.startAt,
    required this.durationMinutes,
    required this.type,
    this.status = AppointmentStatus.confirmed,
    required this.fee,
    required this.meetingLink,
    this.notesForSpecialist = '',
    this.shares = const SharePrefs(),
    required this.createdAt,
    this.consultation,
    this.holdUntil,
    this.payment,
  });

  /// A booking that was never paid for and whose hold ran out: it never became an appointment and is not shown.
  bool isExpiredHold(DateTime now) => status == AppointmentStatus.pendingPayment && (holdUntil == null || !holdUntil!.isAfter(now));

  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));

  Map<String, Object?> toJson() => {
        'patientId': patientId,
        'patientName': patientName,
        'specialistId': specialistId,
        'specialistName': specialistName,
        'role': role.id,
        'specialty': specialty,
        'startAt': startAt.millisecondsSinceEpoch,
        'slotKey': startAt.toUtc().millisecondsSinceEpoch.toString(),
        'durationMinutes': durationMinutes,
        'type': type.id,
        'status': status.id,
        'fee': fee,
        'meetingLink': meetingLink,
        'notesForSpecialist': notesForSpecialist,
        'shares': shares.toJson(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (holdUntil != null) 'holdUntil': holdUntil!.millisecondsSinceEpoch,
        if (payment != null) 'payment': payment!.toJson(),
      };

  static Appointment? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final role = SpecialistTypeInfo.fromId(raw['role']);
    final type = ConsultTypeInfo.fromId(raw['type']);
    final status = AppointmentStatusInfo.fromId(raw['status']);
    // The slot key is the time that was actually locked, so it wins over the separately stored start time.
    final key = int.tryParse('${raw['slotKey']}');
    final start = key ?? raw['startAt'];
    if (role == null || type == null || status == null || start is! num) return null;
    return Appointment(
      id: id,
      patientId: (raw['patientId'] as String?) ?? '',
      patientName: (raw['patientName'] as String?) ?? '',
      specialistId: (raw['specialistId'] as String?) ?? '',
      specialistName: (raw['specialistName'] as String?) ?? '',
      role: role,
      specialty: (raw['specialty'] as String?) ?? '',
      startAt: DateTime.fromMillisecondsSinceEpoch(start.toInt()),
      durationMinutes: ((raw['durationMinutes'] as num?) ?? 30).toInt(),
      type: type,
      status: status,
      fee: ((raw['fee'] as num?) ?? 0).toInt(),
      meetingLink: (raw['meetingLink'] as String?) ?? '',
      notesForSpecialist: (raw['notesForSpecialist'] as String?) ?? '',
      shares: SharePrefs.fromJson(raw['shares']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(((raw['createdAt'] as num?) ?? 0).toInt()),
      consultation: ConsultationNote.fromJson(raw['consultation']),
      holdUntil: raw['holdUntil'] is num ? DateTime.fromMillisecondsSinceEpoch((raw['holdUntil'] as num).toInt()) : null,
      payment: PaymentRecord.fromJson(raw['payment']),
    );
  }

  Appointment copyWith({AppointmentStatus? status, PaymentRecord? payment, bool clearHold = false}) => Appointment(
        id: id,
        patientId: patientId,
        patientName: patientName,
        specialistId: specialistId,
        specialistName: specialistName,
        role: role,
        specialty: specialty,
        startAt: startAt,
        durationMinutes: durationMinutes,
        type: type,
        status: status ?? this.status,
        fee: fee,
        meetingLink: meetingLink,
        notesForSpecialist: notesForSpecialist,
        shares: shares,
        createdAt: createdAt,
        consultation: consultation,
        holdUntil: clearHold ? null : holdUntil,
        payment: payment ?? this.payment,
      );
}

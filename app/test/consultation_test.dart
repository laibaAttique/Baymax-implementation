import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/consultation.dart';
import 'package:app/models/payment.dart';
import 'package:app/screens/specialists/book_appointment_screen.dart';
import 'package:app/screens/specialists/my_appointments_screen.dart';
import 'package:app/screens/specialists/payment_screen.dart';
import 'package:app/screens/specialists/specialists_screen.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/consultation_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/glass.dart';

// Monday 19 Oct 2026, 08:00 in Pakistan (UTC+5) = 03:00 UTC.
final _now = DateTime.utc(2026, 10, 19, 3, 0);
DateTime _clock() => _now;

Specialist _spec(
  String id,
  String name, {
  SpecialistType type = SpecialistType.nutritionist,
  String specialty = 'Weight management',
  double rating = 4.8,
  int reviews = 40,
  bool available = true,
  bool emergency = false,
  Availability availability = const Availability(),
}) =>
    Specialist(
      id: id,
      name: name,
      type: type,
      specialty: specialty,
      rating: rating,
      reviewCount: reviews,
      videoFee: 2000,
      chatFee: 1200,
      available: available,
      emergency: emergency,
      availability: availability,
    );

Appointment _appt(String id, {DateTime? start, AppointmentStatus status = AppointmentStatus.confirmed, ConsultationNote? note, int minutes = 30, DateTime? holdUntil, PaymentRecord? payment}) => Appointment(
      id: id,
      patientId: 'p1',
      patientName: 'Ayesha',
      specialistId: 's1',
      specialistName: 'Dr. Hina Malik',
      role: SpecialistType.doctor,
      specialty: 'General medicine',
      startAt: start ?? _now.add(const Duration(days: 1)),
      durationMinutes: minutes,
      type: ConsultType.video,
      status: status,
      fee: 2000,
      meetingLink: 'https://meet.example/baymax-abc',
      createdAt: _now,
      consultation: note,
      holdUntil: holdUntil,
      payment: payment,
    );

Appointment _held() => _appt('held', status: AppointmentStatus.pendingPayment, holdUntil: _now.add(const Duration(minutes: 10)));

const _testHooks = PaymentHooks(testMode: true);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 9000); // tall, so a long list is built in full
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink()); // drop any earlier screen, so its State is not reused
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('Availability and Specialist parsing', () {
    test('a valid record parses', () {
      final a = Availability.fromJson({'days': [1, 2, 3], 'start': '09:00', 'end': '17:30', 'slotMinutes': 30});
      expect(a, isNotNull);
      expect(a!.days, {1, 2, 3});
      expect(a.startMinute, 540);
      expect(a.endMinute, 1050);
      expect(a.toJson()['end'], '17:30');
    });

    test('unusable records are rejected instead of guessed', () {
      expect(Availability.fromJson({'days': [], 'start': '09:00', 'end': '17:00', 'slotMinutes': 30}), isNull);
      expect(Availability.fromJson({'days': [1], 'start': '17:00', 'end': '09:00', 'slotMinutes': 30}), isNull);
      expect(Availability.fromJson({'days': [1], 'start': '9am', 'end': '17:00', 'slotMinutes': 30}), isNull);
      expect(Availability.fromJson({'days': [1], 'start': '09:00', 'end': '17:00', 'slotMinutes': 5}), isNull);
      expect(Availability.fromJson(null), isNull);
    });

    test('a specialist without fees or with a bad type is skipped; the rest still load', () {
      final good = {
        'name': 'Hina Malik',
        'type': 'doctor',
        'fees': {'video': 2500, 'chat': 1500},
        'availability': {'days': [1], 'start': '09:00', 'end': '12:00', 'slotMinutes': 30},
      };
      expect(Specialist.fromJson('a', good), isNotNull);
      expect(Specialist.fromJson('a', {...good, 'type': 'wizard'}), isNull);
      expect(Specialist.fromJson('a', {...good, 'fees': {'video': 1}}), isNull);
      expect(Specialist.fromJson('a', {...good, 'name': '  '}), isNull);
      expect(Specialist.fromJson('a', 'oops'), isNull);
    });

    test('doctors are addressed as Dr. once', () {
      expect(_spec('a', 'Hina Malik', type: SpecialistType.doctor).displayName, 'Dr. Hina Malik');
      expect(_spec('a', 'Dr. Hina Malik', type: SpecialistType.doctor).displayName, 'Dr. Hina Malik');
      expect(_spec('a', 'Sara Khan').displayName, 'Sara Khan');
    });
  });

  group('slots', () {
    final s = _spec('s1', 'Sara Khan');

    test('a working day gives the slots of the specialist\'s own clock, as the same instants for everyone', () {
      final day = ConsultationRules.specialistToday(s, _now);
      expect(day, DateTime.utc(2026, 10, 19));
      final slots = ConsultationRules.daySlots(s, day);
      expect(slots.length, 16); // 09:00 to 17:00 in 30-minute slots
      expect(slots.first, DateTime.utc(2026, 10, 19, 4, 0)); // 09:00 PKT
      expect(slots.last, DateTime.utc(2026, 10, 19, 11, 30)); // 16:30 PKT
    });

    test('a day off has no slots', () {
      expect(ConsultationRules.daySlots(s, DateTime.utc(2026, 10, 24)), isEmpty); // Saturday
    });

    test('the specialist\'s calendar day follows their time zone, not the phone\'s', () {
      final lateUtc = DateTime.utc(2026, 10, 19, 20, 0); // 01:00 on Tuesday in Pakistan
      expect(ConsultationRules.specialistToday(s, lateUtc), DateTime.utc(2026, 10, 20));
    });

    test('booked times and times too soon are not offered', () {
      final day = DateTime.utc(2026, 10, 19);
      final soon = DateTime.utc(2026, 10, 19, 3, 50); // 08:50 PKT: the 09:00 slot is only 10 minutes away
      final open = ConsultationRules.openSlots(s, day, now: soon, booked: {DateTime.utc(2026, 10, 19, 4, 30).millisecondsSinceEpoch});
      expect(open.first, DateTime.utc(2026, 10, 19, 5, 0)); // 09:00 too soon, 09:30 booked
      expect(open.length, 14);
    });

    test('a specialist who is not taking bookings offers nothing', () {
      final off = _spec('s2', 'Closed', available: false);
      expect(ConsultationRules.openSlots(off, DateTime.utc(2026, 10, 19), now: _now), isEmpty);
      expect(ConsultationRules.nextSlot(off, now: _now), isNull);
    });

    test('the next slot skips a fully booked day', () {
      final day = DateTime.utc(2026, 10, 19);
      final all = ConsultationRules.daySlots(s, day).map((t) => t.millisecondsSinceEpoch).toSet();
      expect(ConsultationRules.nextSlot(s, now: _now, booked: all), DateTime.utc(2026, 10, 20, 4, 0));
    });

    test('upcoming days cover the booking window and mark days off as empty', () {
      final days = ConsultationRules.upcomingDays(s, now: _now);
      expect(days.length, ConsultationRules.bookingDays);
      expect(days.first.hasSlots, isTrue);
      expect(days[5].day.weekday, DateTime.saturday);
      expect(days[5].hasSlots, isFalse);
    });
  });

  group('the specialist list controls (FR35.1 to FR35.3)', () {
    final doc = _spec('d', 'Hina Malik', type: SpecialistType.doctor, specialty: 'General medicine', rating: 4.9, reviews: 80, emergency: true);
    final nut = _spec('n', 'Sara Khan', specialty: 'Sports nutrition', rating: 4.2, reviews: 10);
    final tr = _spec('t', 'Ali Raza', type: SpecialistType.trainer, specialty: 'Strength', rating: 4.7, reviews: 0);
    final all = [nut, tr, doc];

    List<String> ids(List<Specialist> l) => [for (final s in l) s.id];

    test('sorted best rated first', () {
      expect(ids(ConsultationRules.filter(all, now: _now)), ['d', 't', 'n']);
    });

    test('type tab and search work together and the search is not case sensitive', () {
      expect(ids(ConsultationRules.filter(all, type: SpecialistType.trainer, now: _now)), ['t']);
      expect(ids(ConsultationRules.filter(all, query: 'SPORTS', now: _now)), ['n']);
      expect(ids(ConsultationRules.filter(all, query: 'doctor', now: _now)), ['d']);
      expect(ids(ConsultationRules.filter(all, type: SpecialistType.doctor, query: 'sports', now: _now)), isEmpty);
    });

    test('top rated needs 4.5 stars and at least one review; emergency needs an available emergency specialist', () {
      expect(ids(ConsultationRules.filter(all, topRated: true, now: _now)), ['d']); // Ali has 4.7 but no reviews
      expect(ids(ConsultationRules.filter(all, emergency: true, now: _now)), ['d']);
    });

    test('available today uses the next open slot on the member\'s own day, and filters combine', () {
      final next = {'d': DateTime.utc(2026, 10, 19, 5, 0), 'n': DateTime.utc(2026, 10, 21, 5, 0), 't': null};
      final today = ConsultationRules.filter(all, availableToday: true, now: _now.toLocal(), nextSlots: next);
      // Whether 05:00 UTC is "today" depends on the phone's zone; the day after is never today.
      expect(today.map((s) => s.id).contains('n'), isFalse);
      expect(today.map((s) => s.id).contains('t'), isFalse);
      expect(ids(ConsultationRules.filter(all, availableToday: true, topRated: true, now: _now, nextSlots: {'d': null})), isEmpty);
    });

    test('the count line names the type', () {
      expect(ConsultationRules.countLabel(24, SpecialistType.nutritionist), '24 Nutritionists Found');
      expect(ConsultationRules.countLabel(1, SpecialistType.doctor), '1 Doctor Found');
      expect(ConsultationRules.countLabel(3, null), '3 Specialists Found');
    });
  });

  group('booking rules (FR36)', () {
    final s = _spec('s1', 'Sara Khan');
    final slot = DateTime.utc(2026, 10, 19, 5, 0);

    test('a good booking has no problem', () {
      expect(ConsultationRules.bookingProblem(specialist: s, slot: slot, notes: 'hello', now: _now), isNull);
    });

    test('each way a booking can fail says so', () {
      String? p({DateTime? at, String notes = '', Set<int> booked = const {}, Specialist? spec}) =>
          ConsultationRules.bookingProblem(specialist: spec ?? s, slot: at, notes: notes, now: _now, booked: booked);
      expect(p(), contains('Choose a date'));
      expect(p(at: slot, booked: {slot.millisecondsSinceEpoch}), contains('just taken'));
      expect(p(at: DateTime.utc(2026, 10, 19, 3, 5)), contains('too soon'));
      expect(p(at: DateTime.utc(2026, 10, 19, 5, 7)), contains('working hours')); // not on the slot grid
      expect(p(at: DateTime.utc(2026, 10, 24, 5, 0)), contains('working hours')); // Saturday
      expect(p(at: slot, notes: 'x' * 501), contains('500'));
      expect(p(at: slot, spec: _spec('s2', 'Closed', available: false)), contains('not taking bookings'));
    });

    test('a note of exactly 500 characters is allowed', () {
      expect(ConsultationRules.bookingProblem(specialist: s, slot: slot, notes: 'x' * 500, now: _now), isNull);
    });

    test('slot keys sort as text in time order', () {
      final a = ConsultationRules.slotKey(DateTime.utc(2026, 10, 19, 5));
      final b = ConsultationRules.slotKey(DateTime.utc(2026, 10, 20, 5));
      expect(a.length, 13);
      expect(a.compareTo(b), lessThan(0));
    });
  });

  group('an existing appointment', () {
    final start = DateTime.utc(2026, 10, 20, 5, 0);
    final a = _appt('a1', start: start);

    test('the room opens five minutes early and closes when the slot ends', () {
      expect(ConsultationRules.canJoin(a, start.subtract(const Duration(minutes: 6))), isFalse);
      expect(ConsultationRules.canJoin(a, start.subtract(const Duration(minutes: 5))), isTrue);
      expect(ConsultationRules.canJoin(a, start.add(const Duration(minutes: 29))), isTrue);
      expect(ConsultationRules.canJoin(a, start.add(const Duration(minutes: 30))), isFalse);
      expect(ConsultationRules.canJoin(_appt('a2', start: start, status: AppointmentStatus.cancelled), start), isFalse);
    });

    test('only a confirmed appointment that has not started can be cancelled', () {
      expect(ConsultationRules.canCancel(a, start.subtract(const Duration(minutes: 1))), isTrue);
      expect(ConsultationRules.canCancel(a, start), isFalse);
      expect(ConsultationRules.canCancel(_appt('a3', start: start, status: AppointmentStatus.completed), _now), isFalse);
    });

    test('the list shows upcoming soonest first, then past latest first', () {
      final list = [
        _appt('past1', start: _now.subtract(const Duration(days: 5))),
        _appt('later', start: _now.add(const Duration(days: 3))),
        _appt('cancelled', start: _now.add(const Duration(days: 1)), status: AppointmentStatus.cancelled),
        _appt('soon', start: _now.add(const Duration(days: 1))),
        _appt('past2', start: _now.subtract(const Duration(days: 1))),
      ];
      expect([for (final x in ConsultationRules.sortForList(list, _now)) x.id], ['soon', 'later', 'cancelled', 'past2', 'past1']);
    });

    test('there is nothing to join before the specialist accepts: the room is made on acceptance', () {
      final requested = _appt('r', start: start, status: AppointmentStatus.requested);
      final at = start.subtract(const Duration(minutes: 1));
      expect(ConsultationRules.canJoin(requested, at), isFalse);
      final noLink = Appointment.fromJson('c', {..._appt('c', start: start).toJson(), 'meetingLink': null})!;
      expect(noLink.meetingLink, isEmpty);
      expect(ConsultationRules.canJoin(noLink, at), isFalse); // accepted but no link yet: nothing to open
      expect(ConsultationRules.canJoin(_appt('c2', start: start), at), isTrue);
    });

    test('a request can be cancelled until it starts, is upcoming until then, and expires if nobody answered', () {
      final requested = _appt('r', start: start, status: AppointmentStatus.requested);
      final before = start.subtract(const Duration(minutes: 30));
      expect(ConsultationRules.canCancel(requested, before), isTrue);
      expect(ConsultationRules.isUpcoming(requested, before), isTrue);
      expect(ConsultationRules.isExpiredRequest(requested, before), isFalse);
      expect(ConsultationRules.isUpcoming(requested, start), isFalse);
      expect(ConsultationRules.isExpiredRequest(requested, start), isTrue);
      expect(ConsultationRules.canCancel(requested, start), isFalse);
      final declined = _appt('d', start: start, status: AppointmentStatus.declined);
      expect(ConsultationRules.canCancel(declined, before), isFalse);
      expect(ConsultationRules.isUpcoming(declined, before), isFalse);
    });

    test('the list puts requests among the upcoming ones and declined or expired ones in the past', () {
      final list = [
        _appt('req', start: _now.add(const Duration(days: 2)), status: AppointmentStatus.requested),
        _appt('ok', start: _now.add(const Duration(days: 1))),
        _appt('declined', start: _now.add(const Duration(days: 3)), status: AppointmentStatus.declined),
        _appt('expired', start: _now.subtract(const Duration(hours: 2)), status: AppointmentStatus.requested),
      ];
      final sorted = [for (final x in ConsultationRules.sortForList(list, _now)) x.id];
      expect(sorted.sublist(0, 2), ['ok', 'req']);
      expect(sorted.toSet(), {'ok', 'req', 'declined', 'expired'});
    });

    test('an appointment survives a round trip through the database format', () {
      final json = {
        ..._appt('a1', start: start).toJson(),
        'consultation': {'notes': 'Drink more water.', 'prescription': 'Vitamin D 1000 IU daily', 'updatedAt': 1700000000000},
      };
      final back = Appointment.fromJson('a1', json)!;
      expect(back.startAt.toUtc(), start);
      expect(back.status, AppointmentStatus.confirmed);
      expect(back.consultation!.prescription, contains('Vitamin D'));
      expect(Appointment.fromJson('x', {...json, 'status': 'weird'}), isNull);
      expect(Appointment.fromJson('x', {...json, 'status': 'requested'})!.status, AppointmentStatus.requested);
      expect(Appointment.fromJson('x', {...json, 'status': 'declined', 'declineReason': 'On leave'})!.declineReason, 'On leave');
    });

    test('shares default to nothing', () {
      expect(const SharePrefs().any, isFalse);
      expect(SharePrefs.fromJson(null).any, isFalse);
      expect(SharePrefs.fromJson({'foodLog7d': true}).foodLog7d, isTrue);
    });
  });

  group('formatting', () {
    test('fees carry thousands separators', () {
      expect(ConsultationService.pkr(2500), 'PKR 2,500');
      expect(ConsultationService.pkr(950), 'PKR 950');
      expect(ConsultationService.pkr(1250000), 'PKR 1,250,000');
    });
  });

  group('Find a specialist screen', () {
    final doc = _spec('d', 'Hina Malik', type: SpecialistType.doctor, specialty: 'General medicine', rating: 4.9, reviews: 80, emergency: true);
    final nut = _spec('n', 'Sara Khan', specialty: 'Sports nutrition', rating: 4.2, reviews: 10);
    final closed = _spec('c', 'Omar Closed', type: SpecialistType.trainer, specialty: 'Yoga', available: false);
    final data = SpecialistsData([doc, nut, closed], {'d': DateTime.utc(2026, 10, 19, 5), 'n': DateTime.utc(2026, 10, 20, 5), 'c': null});

    testWidgets('lists specialists with a count, filters by type and search, and disables Book when nothing is open', (tester) async {
      await _pump(tester, SpecialistsScreen(loader: () async => data, clock: _clock));
      expect(find.text('3 Specialists Found'), findsOneWidget);
      expect(find.text('Dr. Hina Malik'), findsOneWidget);
      expect(find.text('Not taking bookings'), findsOneWidget);
      final bookButtons = tester.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Book')).toList();
      expect(bookButtons.length, 3);
      expect(bookButtons.where((b) => b.onPressed == null).length, 1);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutritionist'));
      await tester.pumpAndSettle();
      expect(find.text('1 Nutritionist Found'), findsOneWidget);
      expect(find.text('Sara Khan'), findsOneWidget);
      expect(find.text('Dr. Hina Malik'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'yoga');
      await tester.pumpAndSettle();
      expect(find.text('1 Trainer Found').evaluate().isEmpty, isTrue); // type is "All" so the noun is generic
      expect(find.text('1 Specialist Found'), findsOneWidget);
      expect(find.text('Omar Closed'), findsOneWidget);
    });

    testWidgets('a specialist an administrator verified shows a Verified badge', (tester) async {
      const verified = Specialist(id: 'v', name: 'Checked Doc', type: SpecialistType.doctor, specialty: 'General', videoFee: 1, chatFee: 1, rating: 4.5, reviewCount: 3, verified: true);
      await _pump(tester, SpecialistsScreen(loader: () async => SpecialistsData([verified, _spec('u', 'Unchecked')], {'v': DateTime.utc(2026, 10, 19, 5), 'u': DateTime.utc(2026, 10, 19, 5)}), clock: _clock));
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('a specialist with no reviews is shown as new rather than hidden', (tester) async {
      final fresh = _spec('f', 'Newly Joined', reviews: 0, rating: 0);
      await _pump(tester, SpecialistsScreen(loader: () async => SpecialistsData([fresh], {'f': DateTime.utc(2026, 10, 19, 5)}), clock: _clock));
      expect(find.text('Newly Joined'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('an empty catalogue and a failed load are explained, and the failure can be retried', (tester) async {
      await _pump(tester, SpecialistsScreen(loader: () async => const SpecialistsData([], {}), clock: _clock));
      expect(find.textContaining('No specialists have joined yet'), findsOneWidget);

      var calls = 0;
      await _pump(
        tester,
        SpecialistsScreen(
          loader: () async {
            calls++;
            if (calls == 1) throw const ApiException('Could not reach the database. Check your internet connection.');
            return data;
          },
          clock: _clock,
        ),
      );
      expect(find.textContaining('Could not reach the database'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('3 Specialists Found'), findsOneWidget);
    });

    testWidgets('Book opens the booking screen for that specialist', (tester) async {
      await _pump(tester, SpecialistsScreen(loader: () async => data, clock: _clock, loadBooked: (_) async => <int>{}, paymentHooks: _testHooks));
      await tester.tap(find.widgetWithText(FilledButton, 'Book').first); // best rated: Dr. Hina Malik
      await tester.pumpAndSettle();
      expect(find.text('Book appointment'), findsOneWidget);
      expect(find.text('Dr. Hina Malik'), findsWidgets);
    });
  });

  group('Book appointment screen', () {
    final s = _spec('s1', 'Sara Khan');

    testWidgets('confirm stays disabled until a time is chosen; video is the default; nothing is shared by default', (tester) async {
      await _pump(tester, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}));
      await tester.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
      final glow = find.ancestor(of: find.text('Confirm booking'), matching: find.byType(GlowButton));
      expect(tester.widget<GlowButton>(glow).onPressed, isNull);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Not chosen yet'), findsOneWidget);
      for (final c in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
        expect(c.value, isFalse);
      }
    });

    testWidgets('choosing a time, type and sharing holds exactly that, then opens the payment screen', (tester) async {
      Specialist? bookedSpecialist;
      DateTime? bookedSlot;
      ConsultType? bookedType;
      SharePrefs? bookedShares;
      String? bookedNotes;
      await _pump(
        tester,
        BookAppointmentScreen(
          specialist: s,
          clock: _clock,
          loadBooked: (_) async => <int>{},
          paymentHooks: _testHooks,
          book: ({required specialist, required slot, required type, required shares, required notes}) async {
            bookedSpecialist = specialist;
            bookedSlot = slot;
            bookedType = type;
            bookedShares = shares;
            bookedNotes = notes;
            return _held();
          },
        ),
      );
      final firstSlot = DateTime.utc(2026, 10, 19, 4, 0);
      await tester.tap(find.text(ConsultationService.formatTime(firstSlot)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diet log, last 7 days'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Help with a meal plan');
      await tester.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('PKR 1,200'), findsWidgets); // the chat-only fee is in the summary
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();

      expect(bookedSpecialist!.id, 's1');
      expect(bookedSlot, firstSlot);
      expect(bookedType, ConsultType.chat);
      expect(bookedShares!.foodLog7d, isTrue);
      expect(bookedShares!.healthSummary, isFalse);
      expect(bookedShares!.activity30d, isFalse);
      expect(bookedNotes, 'Help with a meal plan');
      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Order summary'), findsOneWidget);
    });

    testWidgets('a time taken by someone else shows a message and the screen stays', (tester) async {
      await _pump(
        tester,
        BookAppointmentScreen(
          specialist: s,
          clock: _clock,
          loadBooked: (_) async => <int>{},
          book: ({required specialist, required slot, required type, required shares, required notes}) async =>
              throw const ApiException('That time was just taken by someone else. Please choose another.', statusCode: 409),
        ),
      );
      await tester.tap(find.text(ConsultationService.formatTime(DateTime.utc(2026, 10, 19, 4, 0))).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('just taken by someone else'), findsOneWidget);
      expect(find.text('Book appointment'), findsOneWidget);
    });

    testWidgets('times that are already booked are not offered', (tester) async {
      final taken = DateTime.utc(2026, 10, 19, 4, 0);
      await _pump(tester, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => {taken.millisecondsSinceEpoch}));
      expect(find.text(ConsultationService.formatTime(taken)), findsNothing);
      expect(find.text(ConsultationService.formatTime(DateTime.utc(2026, 10, 19, 4, 30))), findsWidgets);
    });

    testWidgets('a specialist with no open days says so', (tester) async {
      final none = _spec('s3', 'Nobody', available: false);
      await _pump(tester, BookAppointmentScreen(specialist: none, clock: _clock, loadBooked: (_) async => <int>{}));
      expect(find.textContaining('no open times'), findsOneWidget);
    });

    testWidgets('the notes box stops at 500 characters', (tester) async {
      await _pump(tester, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}));
      await tester.enterText(find.byType(TextField), 'x' * 600);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, 500);
    });

    testWidgets('it says the time is held while paying, and that nothing is confirmed yet', (tester) async {
      await _pump(tester, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}));
      await tester.scrollUntilVisible(find.textContaining('You pay on the next screen'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('held for 10 minutes'), findsOneWidget);
    });
  });

  group('My appointments screen', () {
    final upcoming = _appt('u1', start: _now.add(const Duration(days: 1)));
    final past = _appt('p1', start: _now.subtract(const Duration(days: 3)), status: AppointmentStatus.completed, note: ConsultationNote(notes: 'Eat more protein.', prescription: 'Iron tablets', updatedAt: _now));

    testWidgets('upcoming and past are separate tabs', (tester) async {
      await _pump(tester, MyAppointmentsScreen(loader: () async => [upcoming, past], clock: _clock));
      expect(find.text('Upcoming (1)'), findsOneWidget);
      expect(find.text('Dr. Hina Malik'), findsOneWidget);
      expect(find.text('Notes from specialist'), findsNothing);
      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('Notes from specialist'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('a request shows as awaiting acceptance with no video link, can be cancelled as a request, and a declined one shows the reason', (tester) async {
      final req = _appt('req', start: _now.add(const Duration(days: 1)), status: AppointmentStatus.requested).copyWith(meetingLink: '');
      await _pump(tester, MyAppointmentsScreen(loader: () async => [req], clock: _clock));
      expect(find.text('Awaiting acceptance'), findsOneWidget);
      await _pump(tester, AppointmentDetailScreen(appointment: req, clock: _clock));
      expect(find.text('Waiting for your specialist'), findsOneWidget);
      expect(find.text('Meeting room'), findsNothing);
      expect(find.text('Copy meeting link'), findsNothing);
      await tester.scrollUntilVisible(find.text('Cancel request'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Cancel request'), findsOneWidget);

      final declined = Appointment.fromJson('d', {..._appt('d', start: _now.add(const Duration(days: 1)), status: AppointmentStatus.declined).toJson(), 'declineReason': 'On leave that day'})!;
      await _pump(tester, AppointmentDetailScreen(appointment: declined, clock: _clock));
      expect(find.text('Not accepted'), findsOneWidget);
      expect(find.textContaining('On leave that day'), findsOneWidget);
      expect(find.text('Cancel appointment'), findsNothing);
    });

    testWidgets('a request nobody answered before its start is shown as expired', (tester) async {
      final old = _appt('old', start: _now.subtract(const Duration(hours: 3)), status: AppointmentStatus.requested);
      await _pump(tester, MyAppointmentsScreen(loader: () async => [old], clock: _clock));
      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('an empty list and an error are explained', (tester) async {
      await _pump(tester, MyAppointmentsScreen(loader: () async => const [], clock: _clock));
      expect(find.textContaining('no upcoming appointments'), findsOneWidget);
      await _pump(tester, MyAppointmentsScreen(loader: () async => throw const ApiException('The database refused access.'), clock: _clock));
      expect(find.textContaining('refused access'), findsOneWidget);
    });

    testWidgets('detail shows the meeting link, the specialist\'s notes and what was shared', (tester) async {
      await _pump(tester, AppointmentDetailScreen(appointment: past, clock: _clock));
      expect(find.text('Consultation notes'), findsOneWidget);
      expect(find.text('Eat more protein.'), findsOneWidget);
      expect(find.text('Iron tablets'), findsOneWidget);
      expect(find.textContaining('Nothing. Your specialist sees only this booking.'), findsOneWidget);
      expect(find.text('Meeting room'), findsNothing); // only for confirmed appointments

      await _pump(tester, AppointmentDetailScreen(appointment: upcoming, clock: _clock));
      expect(find.text('Meeting room'), findsOneWidget);
      expect(find.text('https://meet.example/baymax-abc'), findsOneWidget);
      expect(find.textContaining('opens 5 minutes before'), findsOneWidget);
    });

    testWidgets('the room is announced as open inside the join window', (tester) async {
      final start = _now.add(const Duration(minutes: 3));
      await _pump(tester, AppointmentDetailScreen(appointment: _appt('live', start: start), clock: _clock));
      expect(find.textContaining('The room is open now'), findsOneWidget);
    });

    testWidgets('cancelling asks first, then calls back and shows the new status', (tester) async {
      Appointment? cancelled;
      await _pump(tester, AppointmentDetailScreen(appointment: upcoming, clock: _clock, onCancel: (a) async => cancelled = a));
      await tester.scrollUntilVisible(find.text('Cancel appointment'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Cancel appointment'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this appointment?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(cancelled, isNull);

      await tester.tap(find.text('Cancel appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel appointment'));
      await tester.pumpAndSettle();
      expect(cancelled!.id, 'u1');
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel appointment'), findsNothing);
    });

    testWidgets('a started appointment has no cancel button', (tester) async {
      final started = _appt('s', start: _now.subtract(const Duration(minutes: 5)));
      await _pump(tester, AppointmentDetailScreen(appointment: started, clock: _clock));
      expect(find.text('Cancel appointment'), findsNothing);
    });
  });
}

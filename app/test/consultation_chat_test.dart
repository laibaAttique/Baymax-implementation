import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/consultation.dart';
import 'package:app/screens/specialists/consultation_chat_screen.dart';
import 'package:app/screens/specialists/my_appointments_screen.dart';
import 'package:app/services/consultation_chat.dart';
import 'package:app/theme/app_theme.dart';

// Monday 19 Oct 2026, 08:00 in Pakistan (UTC+5) = 03:00 UTC.
final _now = DateTime.utc(2026, 10, 19, 3, 0);
DateTime _clock() => _now;

Appointment _appt({AppointmentStatus status = AppointmentStatus.confirmed, DateTime? start, Map<String, Object?> extra = const {}}) => Appointment.fromJson('a1', {
      'patientId': 'p1',
      'patientName': 'Ayesha',
      'specialistId': 's1',
      'specialistName': 'Dr. Hina Malik',
      'role': 'doctor',
      'specialty': 'General medicine',
      'startAt': (start ?? _now.add(const Duration(days: 1))).millisecondsSinceEpoch,
      'slotKey': (start ?? _now.add(const Duration(days: 1))).millisecondsSinceEpoch.toString(),
      'durationMinutes': 30,
      'type': 'video',
      'status': status.id,
      'fee': 2000,
      'meetingLink': 'https://meet.example/baymax-abc',
      'createdAt': _now.millisecondsSinceEpoch,
      ...extra,
    })!;

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 9000); // tall, so a long page is built in full
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink()); // drop any earlier screen, so its State is not reused
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: child));
  await tester.pump();
}

void main() {
  group('ChatRules (the same rules as the portal and the database)', () {
    test('only an accepted appointment has a conversation', () {
      for (final s in AppointmentStatus.values) {
        final yes = s == AppointmentStatus.confirmed || s == AppointmentStatus.completed || s == AppointmentStatus.noShow;
        expect(ChatRules.hasConversation(_appt(status: s)), yes, reason: s.id);
      }
    });

    test('writing is open until 24 hours after the slot ends', () {
      final a = _appt(status: AppointmentStatus.completed, start: _now.subtract(const Duration(days: 3)));
      expect(ChatRules.canSend(a, a.endAt.add(const Duration(hours: 23, minutes: 59))), isTrue);
      expect(ChatRules.canSend(a, a.endAt.add(const Duration(hours: 24))), isFalse);
      expect(ChatRules.canSend(_appt(status: AppointmentStatus.requested), _now), isFalse);
      expect(ChatRules.closedReason(_appt(status: AppointmentStatus.requested), _now), contains('once they accept'));
      expect(ChatRules.closedReason(a, _now), contains('closed'));
      expect(ChatRules.closedReason(_appt(), _now), isNull);
    });

    test('a message is 1 to 1000 characters of plain text', () {
      expect(ChatRules.problem('  hello  '), isNull);
      expect(ChatRules.problem(''), isNotNull);
      expect(ChatRules.problem('   '), isNotNull);
      expect(ChatRules.problem('x' * 1000), isNull);
      expect(ChatRules.problem('x' * 1001), contains('1000'));
      expect(ChatRules.problem('bell\u0007'), contains('not allowed'));
      expect(ChatRules.problem('two\nlines'), isNull);
    });

    test('stored messages are cleaned, ordered, and marked mine only when the member wrote them', () {
      final list = ChatRules.parse({
        'b': {'from': 'p1', 'side': 'patient', 'text': 'second', 'at': 20},
        'a': {'from': 'd1', 'side': 'specialist', 'text': 'first', 'at': 10},
        'x': {'from': 'p2', 'side': 'patient', 'text': 'someone else', 'at': 30},
        'bad1': {'side': 'patient', 'text': 5, 'at': 1},
        'bad2': {'side': 'admin', 'text': 'x', 'at': 1},
        'bad3': {'side': 'patient', 'text': '', 'at': 1},
        'bad4': 'text',
      }, myId: 'p1');
      expect(list.map((m) => m.text), ['first', 'second', 'someone else']);
      expect(list.map((m) => m.mine), [false, true, false]);
      expect(ChatRules.parse(null, myId: 'p1'), isEmpty);
    });
  });

  group('a refund recorded by the portal', () {
    test('is read, kept, and ignored when malformed', () {
      final a = _appt(extra: {'refund': {'status': 'refunded', 'amount': 2150, 'at': 1000, 'reason': 'Declined'}});
      expect(a.refund!.returned, isTrue);
      expect(a.refund!.amount, 2150);
      expect(Appointment.fromJson('x', {...a.toJson(), 'refund': a.refund!.toJson()})!.refund!.reason, 'Declined');
      expect(_appt(extra: {'refund': {'status': 'weird'}}).refund, isNull);
      expect(_appt().refund, isNull);
      expect(_appt(extra: {'refund': {'status': 'manual', 'amount': 5}}).refund!.returned, isFalse);
    });
  });

  group('ConsultationChatScreen', () {
    testWidgets('shows the conversation, sends a message, and clears the box', (tester) async {
      final controller = StreamController<List<ChatMessage>>();
      addTearDown(controller.close);
      final sent = <String>[];
      var opened = 0;
      await _pump(tester, ConsultationChatScreen(appointment: _appt(), messages: () => controller.stream, onSend: (t) async => sent.add(t), onOpened: () async => opened++, clock: _clock));
      expect(opened, 1);
      controller.add([
        ChatMessage(id: '1', mine: true, text: 'My back hurts', at: _now),
        ChatMessage(id: '2', mine: false, text: 'Please avoid lifting.', at: _now.add(const Duration(minutes: 1))),
      ]);
      await tester.pump();
      expect(find.text('My back hurts'), findsOneWidget);
      expect(find.text('Please avoid lifting.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  Thank you  ');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(sent, ['Thank you']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('an empty message is refused with a reason and nothing is sent', (tester) async {
      final sent = <String>[];
      await _pump(tester, ConsultationChatScreen(appointment: _appt(), messages: () => Stream.value(const []), onSend: (t) async => sent.add(t), onOpened: () async {}, clock: _clock));
      await tester.pump();
      expect(find.textContaining('No messages yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(find.text('Write a message first.'), findsOneWidget);
      expect(sent, isEmpty);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      expect(find.text('Write a message first.'), findsNothing);
    });

    testWidgets('a failed send keeps the text and says so', (tester) async {
      await _pump(tester, ConsultationChatScreen(appointment: _appt(), messages: () => Stream.value(const []), onSend: (t) async => throw StateError('offline'), onOpened: () async {}, clock: _clock));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(find.text('Could not send the message. Please try again.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'hello');
    });

    testWidgets('a closed conversation can be read but has no box to write in', (tester) async {
      final old = _appt(status: AppointmentStatus.completed, start: _now.subtract(const Duration(days: 3)));
      await _pump(tester, ConsultationChatScreen(appointment: old, messages: () => Stream.value([ChatMessage(id: '1', mine: false, text: 'Rest well', at: _now)]), onOpened: () async {}, clock: _clock));
      await tester.pump();
      expect(find.text('Rest well'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('closed'), findsOneWidget);
    });

    testWidgets('a stream error shows a message instead of a blank screen', (tester) async {
      await _pump(tester, ConsultationChatScreen(appointment: _appt(), messages: () => Stream.error('boom'), onOpened: () async {}, clock: _clock));
      await tester.pump();
      expect(find.textContaining('Could not load the messages'), findsOneWidget);
    });
  });

  group('the appointment page links to the conversation', () {
    testWidgets('an accepted appointment has a Messages card; a request does not', (tester) async {
      await _pump(tester, AppointmentDetailScreen(appointment: _appt(), clock: _clock));
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Open messages'), findsOneWidget);
      await _pump(tester, AppointmentDetailScreen(appointment: _appt(status: AppointmentStatus.requested), clock: _clock));
      expect(find.text('Messages'), findsNothing);
    });

    testWidgets('a refund is shown with the payment', (tester) async {
      final payment = {'transactionId': 'TXN-1234', 'method': 'card', 'status': 'paid', 'consultationFee': 2000, 'platformFee': 0, 'total': 2000, 'brand': 'Visa', 'last4': '4242', 'reference': 'r', 'mode': 'sandbox', 'paidAt': 1};
      final a = _appt(status: AppointmentStatus.declined, extra: {'payment': payment, 'refund': {'status': 'refunded', 'amount': 2000, 'at': 5, 'reason': 'x'}});
      await _pump(tester, AppointmentDetailScreen(appointment: a, clock: _clock));
      await tester.scrollUntilVisible(find.text('Refund'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('returned'), findsOneWidget);
    });
  });
}

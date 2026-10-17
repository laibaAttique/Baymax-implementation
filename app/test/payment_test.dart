import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/consultation.dart';
import 'package:app/models/payment.dart';
import 'package:app/screens/specialists/payment_screen.dart';
import 'package:app/screens/specialists/payment_success_screen.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/payment_gateway.dart';
import 'package:app/services/payment_rules.dart';
import 'package:app/services/payment_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/glass.dart';

// Monday 19 Oct 2026, 08:00 in Pakistan.
final _now = DateTime.utc(2026, 10, 19, 3, 0);
DateTime _clock() => _now;

Appointment _held({Duration hold = const Duration(minutes: 10), int fee = 2000}) => Appointment(
      id: 'a1',
      patientId: 'p1',
      patientName: 'Ayesha',
      specialistId: 's1',
      specialistName: 'Dr. Hina Malik',
      role: SpecialistType.doctor,
      specialty: 'General medicine',
      startAt: _now.add(const Duration(days: 1)),
      durationMinutes: 30,
      type: ConsultType.video,
      status: AppointmentStatus.pendingPayment,
      fee: fee,
      meetingLink: 'https://meet.example/baymax-abc',
      createdAt: _now,
      holdUntil: _now.add(hold),
    );

PaymentRecord _record({PaymentMethod method = PaymentMethod.card, PaymentStatus status = PaymentStatus.paid, int fee = 2000, int platform = 0, String mode = 'sandbox'}) => PaymentRecord(
      transactionId: 'TXN-TEST-0001',
      method: method,
      status: status,
      consultationFee: fee,
      platformFee: platform,
      brand: 'Visa',
      last4: '4242',
      reference: 'sbx_c_abc',
      mode: mode,
      paidAt: _now,
    );

const _good = CardInput(number: '4242 4242 4242 4242', expiry: '12/30', cvv: '123', holder: 'Ayesha Khan');

class _ThrowingGateway implements PaymentGateway {
  int calls = 0;
  @override
  String get mode => 'sandbox';
  @override
  Future<GatewayResult> charge(PaymentRequest request, {DateTime? now}) async {
    calls++;
    throw StateError('the gateway must not be called');
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('card checks (FR37.4)', () {
    test('the check-digit test accepts real card numbers and rejects typos', () {
      expect(PaymentRules.luhn('4242424242424242'), isTrue);
      expect(PaymentRules.luhn('5555555555554444'), isTrue);
      expect(PaymentRules.luhn('4242424242424241'), isFalse);
      expect(PaymentRules.luhn(''), isFalse);
    });

    test('Visa and Mastercard are recognised, other brands are not', () {
      expect(PaymentRules.brandOf('4242 4242 4242 4242'), 'Visa');
      expect(PaymentRules.brandOf('5555555555554444'), 'Mastercard');
      expect(PaymentRules.brandOf('2221000000000009'), 'Mastercard');
      expect(PaymentRules.brandOf('378282246310005'), isNull); // American Express
      expect(PaymentRules.brandOf('6011111111111117'), isNull); // Discover
    });

    test('typing is formatted as the person goes', () {
      expect(PaymentRules.groupCardNumber('4242424242424242999'), '4242 4242 4242 4242');
      expect(PaymentRules.groupCardNumber('42424'), '4242 4');
      expect(PaymentRules.formatExpiry('1'), '1');
      expect(PaymentRules.formatExpiry('122'), '12/2');
      expect(PaymentRules.formatExpiry('12306'), '12/30');
    });

    test('a valid card has no errors', () {
      expect(PaymentRules.validateCard(_good, _now), isEmpty);
    });

    test('each field reports its own problem', () {
      String? err(CardInput c, String key) => PaymentRules.validateCard(c, _now)[key];
      expect(err(const CardInput(number: '4242 4242 4242', expiry: '12/30', cvv: '123', holder: 'A B'), 'number'), contains('16 digits'));
      expect(err(const CardInput(number: '4242 4242 4242 4241', expiry: '12/30', cvv: '123', holder: 'A B'), 'number'), contains('not valid'));
      expect(err(const CardInput(number: '3782 8224 6310 005', expiry: '12/30', cvv: '123', holder: 'A B'), 'number'), isNotNull);
      expect(err(const CardInput(number: '4242424242424242', expiry: '13/30', cvv: '123', holder: 'A B'), 'expiry'), contains('MM/YY'));
      expect(err(const CardInput(number: '4242424242424242', expiry: '09/26', cvv: '123', holder: 'A B'), 'expiry'), contains('expired'));
      expect(err(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '12', holder: 'A B'), 'cvv'), isNotNull);
      expect(err(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '1234', holder: 'A B'), 'cvv'), isNotNull);
      expect(err(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '123', holder: ''), 'holder'), isNotNull);
      expect(err(const CardInput(number: '4242424242424242', expiry: '12/30', cvv: '123', holder: '1234'), 'holder'), isNotNull);
      expect(PaymentRules.validateCard(const CardInput(), _now).keys, containsAll(['number', 'expiry', 'cvv', 'holder'])); // all four are mandatory
    });

    test('a card is good through the last day of its expiry month', () {
      expect(PaymentRules.expiryInPast('10/26', DateTime(2026, 10, 31, 23, 59)), isFalse);
      expect(PaymentRules.expiryInPast('10/26', DateTime(2026, 11, 1)), isTrue);
      expect(PaymentRules.expiryInPast('nonsense', _now), isTrue);
    });
  });

  group('wallet and order', () {
    test('Pakistani mobile numbers are accepted in common spellings', () {
      expect(PaymentRules.normalizeMobile('0300 1234567'), '03001234567');
      expect(PaymentRules.normalizeMobile('+92 300 1234567'), '03001234567');
      expect(PaymentRules.normalizeMobile('3001234567'), '03001234567');
      expect(PaymentRules.normalizeMobile('0200 1234567'), isNull);
      expect(PaymentRules.normalizeMobile('0300 123456'), isNull);
    });

    test('a wallet needs a provider and a number', () {
      expect(PaymentRules.validateWallet(null, '03001234567'), contains('Choose'));
      expect(PaymentRules.validateWallet(WalletProvider.jazzcash, '123'), contains('mobile number'));
      expect(PaymentRules.validateWallet(WalletProvider.easypaisa, '03001234567'), isNull);
    });

    test('the total is always the fee plus the platform fee, including a zero platform fee', () {
      expect(const OrderSummary(consultationFee: 2000, platformFee: 150).total, 2150);
      expect(const OrderSummary(consultationFee: 2000).total, 2000);
    });

    test('Pay is possible only when everything the chosen method needs is valid and the fee is known', () {
      const order = OrderSummary(consultationFee: 2000);
      bool can(PaymentMethod m, {CardInput card = const CardInput(), WalletProvider? w, String number = '', SavedCard? saved, String savedCvv = '', OrderSummary? o = order}) =>
          PaymentRules.canPay(method: m, now: _now, order: o, card: card, wallet: w, walletNumber: number, savedCard: saved, savedCardCvv: savedCvv);
      expect(can(PaymentMethod.card), isFalse);
      expect(can(PaymentMethod.card, card: _good), isTrue);
      expect(can(PaymentMethod.card, card: _good, o: null), isFalse); // FR37.2: no fee, no payment
      expect(can(PaymentMethod.wallet, w: WalletProvider.jazzcash), isFalse);
      expect(can(PaymentMethod.wallet, w: WalletProvider.jazzcash, number: '03001234567'), isTrue);
      expect(can(PaymentMethod.clinic), isTrue);
      const saved = SavedCard(id: 'c1', token: 'sbx_tok_x', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030);
      expect(can(PaymentMethod.card, saved: saved), isFalse);
      expect(can(PaymentMethod.card, saved: saved, savedCvv: '123'), isTrue);
      const old = SavedCard(id: 'c2', token: 'sbx_tok_y', brand: 'Visa', last4: '1111', expMonth: 1, expYear: 2024);
      expect(can(PaymentMethod.card, saved: old, savedCvv: '123'), isFalse);
    });

    test('the hold counts down and never goes below zero', () {
      final until = _now.add(const Duration(minutes: 10));
      expect(PaymentRules.countdown(PaymentRules.holdRemaining(until, _now)), '10:00');
      expect(PaymentRules.countdown(PaymentRules.holdRemaining(until, _now.add(const Duration(minutes: 9, seconds: 19)))), '0:41');
      expect(PaymentRules.holdRemaining(until, _now.add(const Duration(hours: 1))), Duration.zero);
    });
  });

  group('the test gateway', () {
    final g = SandboxGateway(delay: Duration.zero);
    GatewayResult? last;
    Future<GatewayResult> charge(PaymentRequest r) async => last = await g.charge(r);

    test('published test cards succeed and give a reference, brand and last four digits only', () async {
      final r = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good, saveCard: false));
      expect(r.success, isTrue);
      expect(r.brand, 'Visa');
      expect(r.last4, '4242');
      expect(r.reference, startsWith('sbx_c_'));
      expect(r.cardToken, isNull); // not asked to save
      expect(r.mode, 'sandbox');
      final mc = await charge(const PaymentRequest(amount: 1, method: PaymentMethod.card, card: CardInput(number: '5555555555554444', expiry: '12/30', cvv: '123', holder: 'A B')));
      expect(mc.brand, 'Mastercard');
    });

    test('a token is made only when the member asked to save the card', () async {
      final r = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good, saveCard: true));
      expect(r.cardToken, startsWith('sbx_tok_'));
      expect(r.cardToken, isNot(contains('4242')));
      expect(r.expMonth, 12);
      expect(r.expYear, 2030);
    });

    test('the declined test card is declined, and a real-looking card is refused with a hint rather than "charged"', () async {
      final declined = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4000 0000 0000 0002', expiry: '12/30', cvv: '123', holder: 'A B')));
      expect(declined.success, isFalse);
      expect(declined.message, contains('declined'));
      final real = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4111 1111 1111 1111', expiry: '12/30', cvv: '123', holder: 'A B')));
      expect(real.success, isFalse);
      expect(real.message, contains('4242 4242 4242 4242'));
      expect(last!.reference, isNull);
    });

    test('wallets succeed unless the test number ends in 0000', () async {
      final ok = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.wallet, wallet: WalletProvider.jazzcash, walletNumber: '0300 1234567'));
      expect(ok.success, isTrue);
      expect(ok.last4, '4567');
      final low = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.wallet, wallet: WalletProvider.easypaisa, walletNumber: '03000000000'));
      expect(low.success, isFalse);
      expect(low.message, contains('insufficient'));
      final bad = await charge(const PaymentRequest(amount: 2000, method: PaymentMethod.wallet, wallet: null, walletNumber: '123'));
      expect(bad.success, isFalse);
    });

    test('a saved card is charged by its token and a fresh CVV, never a number', () async {
      const saved = SavedCard(id: 'c1', token: 'sbx_tok_abc', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030);
      expect((await charge(const PaymentRequest(amount: 1, method: PaymentMethod.card, savedCard: saved, savedCardCvv: '123'))).success, isTrue);
      expect((await charge(const PaymentRequest(amount: 1, method: PaymentMethod.card, savedCard: saved, savedCardCvv: '12'))).success, isFalse);
      const foreign = SavedCard(id: 'c2', token: 'tok_other', brand: 'Visa', last4: '1111', expMonth: 12, expYear: 2030);
      expect((await charge(const PaymentRequest(amount: 1, method: PaymentMethod.card, savedCard: foreign, savedCardCvv: '123'))).success, isFalse);
    });

    test('pay-at-clinic never reaches the gateway', () async {
      expect((await charge(const PaymentRequest(amount: 1, method: PaymentMethod.clinic))).success, isFalse);
    });
  });

  group('paying for a held booking', () {
    final svc = PaymentService.instance;
    late PaymentGateway original;
    setUp(() => original = svc.gateway);
    tearDown(() => svc.gateway = original);

    Future<Appointment> confirmOk(Appointment a, PaymentRecord p) async => a.copyWith(status: AppointmentStatus.confirmed, payment: p, clearHold: true);

    test('a successful card payment confirms the booking with a record that holds no card number', () async {
      svc.gateway = SandboxGateway(delay: Duration.zero);
      PaymentRecord? written;
      final done = await svc.pay(
        appointment: _held(),
        request: const PaymentRequest(amount: 2150, method: PaymentMethod.card, card: _good),
        platformFee: 150,
        now: _now,
        confirm: (a, p) {
          written = p;
          return confirmOk(a, p);
        },
      );
      expect(done.status, AppointmentStatus.confirmed);
      expect(done.holdUntil, isNull);
      expect(written!.status, PaymentStatus.paid);
      expect(written!.total, 2150);
      expect(written!.consultationFee, 2000);
      expect(written!.platformFee, 150);
      expect(written!.last4, '4242');
      expect(written!.transactionId, startsWith('TXN-'));
      final json = written!.toJson().toString();
      expect(json, isNot(contains('4242424242424242')));
      expect(json, isNot(contains('123'))); // no CVV
      expect(json, isNot(contains('Ayesha Khan'))); // no cardholder name
    });

    test('a declined payment throws 402, keeps the hold, and confirms nothing', () async {
      svc.gateway = SandboxGateway(delay: Duration.zero);
      var confirmed = false;
      await expectLater(
        svc.pay(
          appointment: _held(),
          request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: CardInput(number: '4000000000000002', expiry: '12/30', cvv: '123', holder: 'A B')),
          platformFee: 0,
          now: _now,
          confirm: (a, p) async {
            confirmed = true;
            return a;
          },
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 402).having((e) => e.message, 'message', contains('declined'))),
      );
      expect(confirmed, isFalse);
    });

    test('a hold that is about to run out is refused before any money is taken', () async {
      final gateway = _ThrowingGateway();
      svc.gateway = gateway;
      await expectLater(
        svc.pay(appointment: _held(hold: const Duration(seconds: 30)), request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 410)),
      );
      expect(gateway.calls, 0);
    });

    test('an amount that does not match the booking is refused', () async {
      final gateway = _ThrowingGateway();
      svc.gateway = gateway;
      await expectLater(
        svc.pay(appointment: _held(), request: const PaymentRequest(amount: 1, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('amount'))),
      );
      expect(gateway.calls, 0);
    });

    test('a booking that is not waiting for payment cannot be paid', () async {
      final gateway = _ThrowingGateway();
      svc.gateway = gateway;
      final confirmedAlready = _held().copyWith(status: AppointmentStatus.confirmed);
      await expectLater(
        svc.pay(appointment: confirmedAlready, request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk),
        throwsA(isA<ApiException>()),
      );
      expect(gateway.calls, 0);
    });

    test('pay at clinic confirms without touching the gateway and records that nothing was paid', () async {
      final gateway = _ThrowingGateway();
      svc.gateway = gateway;
      PaymentRecord? written;
      await svc.pay(
        appointment: _held(),
        request: const PaymentRequest(amount: 2000, method: PaymentMethod.clinic),
        platformFee: 0,
        now: _now,
        confirm: (a, p) {
          written = p;
          return confirmOk(a, p);
        },
      );
      expect(gateway.calls, 0);
      expect(written!.status, PaymentStatus.payAtClinic);
      expect(written!.method, PaymentMethod.clinic);
    });

    test('a second payment for the same booking while one is running is refused', () async {
      final gate = Completer<void>();
      svc.gateway = _SlowGateway(gate.future);
      final first = svc.pay(appointment: _held(), request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk);
      await expectLater(
        svc.pay(appointment: _held(), request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('already being processed'))),
      );
      gate.complete();
      expect((await first).status, AppointmentStatus.confirmed);
      // and once finished, the booking can be tried again
      svc.gateway = SandboxGateway(delay: Duration.zero);
      expect((await svc.pay(appointment: _held(), request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk)).status, AppointmentStatus.confirmed);
    });

    test('if the charge worked but the booking could not be written, the message carries the reference', () async {
      svc.gateway = SandboxGateway(delay: Duration.zero);
      Object? error;
      try {
        await svc.pay(
          appointment: _held(),
          request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good),
          platformFee: 0,
          now: _now,
          confirm: (a, p) async => throw const ApiException('The database refused access.'),
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<ApiException>());
      expect((error as ApiException).message, allOf(contains('payment went through'), contains('sbx_c_'), contains('support')));
    });

    test('the card is saved only when ticked, and only as a token; a failure to save does not undo the payment', () async {
      svc.gateway = SandboxGateway(delay: Duration.zero);
      SavedCard? saved;
      await svc.pay(
        appointment: _held(),
        request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good, saveCard: true),
        platformFee: 0,
        now: _now,
        confirm: confirmOk,
        saveCard: (c) async => saved = c,
      );
      expect(saved!.token, startsWith('sbx_tok_'));
      expect(saved!.last4, '4242');
      expect(saved!.toJson().toString(), isNot(contains('4242424242424242')));

      saved = null;
      await svc.pay(appointment: _held(), request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good), platformFee: 0, now: _now, confirm: confirmOk, saveCard: (c) async => saved = c);
      expect(saved, isNull);

      final ok = await svc.pay(
        appointment: _held(),
        request: const PaymentRequest(amount: 2000, method: PaymentMethod.card, card: _good, saveCard: true),
        platformFee: 0,
        now: _now,
        confirm: confirmOk,
        saveCard: (c) async => throw StateError('disk full'),
      );
      expect(ok.status, AppointmentStatus.confirmed);
    });
  });

  group('held bookings and payment records in the data model', () {
    test('a held booking that was never paid is not an appointment: it is hidden from the list and counts as expired after its hold', () {
      final held = _held();
      expect(held.isExpiredHold(_now), isFalse);
      expect(held.isExpiredHold(_now.add(const Duration(minutes: 11))), isTrue);
      expect(ConsultationRules.sortForList([held], _now), isEmpty);
    });

    test('hold and payment survive a round trip through the database format', () {
      final a = _held().copyWith(status: AppointmentStatus.confirmed, payment: _record(platform: 100), clearHold: true);
      final back = Appointment.fromJson('a1', a.toJson())!;
      expect(back.status, AppointmentStatus.confirmed);
      expect(back.holdUntil, isNull);
      expect(back.payment!.total, 2100);
      expect(back.payment!.description, 'Visa ending 4242');
      expect(back.payment!.isTest, isTrue);
      final live = PaymentRecord.fromJson(_record(mode: 'live').toJson())!;
      expect(live.isTest, isFalse);
      final held = Appointment.fromJson('a1', _held().toJson())!;
      expect(held.status, AppointmentStatus.pendingPayment);
      expect(held.holdUntil, isNotNull);
    });

    test('saved cards parse and bad records are skipped', () {
      expect(SavedCard.fromJson('c', {'token': 'sbx_tok_a', 'brand': 'Visa', 'last4': '4242', 'expMonth': 5, 'expYear': 2029})!.expiry, '05/29');
      expect(SavedCard.fromJson('c', {'brand': 'Visa'}), isNull);
    });
  });

  group('Payment screen (FR-1 to FR-6, FR37)', () {
    PaymentHooks hooks({
      Future<Appointment> Function(Appointment, PaymentRequest, int)? pay,
      Future<void> Function(Appointment)? release,
      Future<OrderSummary> Function(Appointment)? order,
      List<SavedCard> saved = const [],
    }) =>
        PaymentHooks(
          pay: pay,
          releaseHold: release ?? (_) async {},
          loadOrder: order ?? (a) async => OrderSummary(consultationFee: a.fee),
          loadSavedCards: () async => saved,
          testMode: true,
        );

    Future<void> fillCard(WidgetTester tester, {String number = '4242424242424242', String expiry = '1230', String cvv = '123', String holder = 'Ayesha Khan'}) async {
      await tester.enterText(find.widgetWithText(TextField, 'Card number'), number);
      await tester.enterText(find.widgetWithText(TextField, 'Expiry (MM/YY)'), expiry);
      await tester.enterText(find.widgetWithText(TextField, 'CVV'), cvv);
      await tester.enterText(find.widgetWithText(TextField, 'Cardholder name'), holder);
      await tester.pumpAndSettle();
    }

    GlowButton payButton(WidgetTester tester) => tester.widget<GlowButton>(find.byType(GlowButton).last);

    testWidgets('shows the booking read-only, the fee breakdown with an explicit zero platform fee, card as the default method, and the padlock', (tester) async {
      await _pump(tester, PaymentScreen(appointment: _held(), hooks: hooks(), clock: _clock));
      expect(find.text('Dr. Hina Malik'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Video call'), findsOneWidget);
      expect(find.text('Consultation fee'), findsOneWidget);
      expect(find.text('Platform fee'), findsOneWidget);
      expect(find.text('PKR 0'), findsOneWidget);
      expect(find.text('PKR 2,000'), findsWidgets);
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
      expect(find.widgetWithText(TextField, 'Card number'), findsOneWidget); // card is the default
      expect(find.text('Your time is held for 10:00'), findsOneWidget);
      expect(find.textContaining('Test mode'), findsOneWidget);
    });

    testWidgets('the total updates with the platform fee', (tester) async {
      await _pump(tester, PaymentScreen(appointment: _held(), hooks: hooks(order: (a) async => OrderSummary(consultationFee: a.fee, platformFee: 150)), clock: _clock));
      expect(find.text('PKR 150'), findsOneWidget);
      expect(find.text('PKR 2,150'), findsOneWidget);
    });

    testWidgets('Pay stays disabled until all four card fields are valid, shows field errors, and the CVV is hidden', (tester) async {
      await _pump(tester, PaymentScreen(appointment: _held(), hooks: hooks(), clock: _clock));
      expect(payButton(tester).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Card number'), '4242424242424241'); // fails the check digit
      await tester.pumpAndSettle();
      expect(find.textContaining('not valid'), findsOneWidget);
      await fillCard(tester, number: '4242424242424242', expiry: '0925'); // expired
      expect(find.text('This card has expired.'), findsOneWidget);
      expect(payButton(tester).onPressed, isNull);
      await fillCard(tester);
      expect(payButton(tester).onPressed, isNotNull);
      expect(find.text('Pay PKR 2,000'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'CVV')).obscureText, isTrue);
      // the number is grouped as it is typed
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Card number')).controller!.text, '4242 4242 4242 4242');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Expiry (MM/YY)')).controller!.text, '12/30');
    });

    testWidgets('"save card" is off by default', (tester) async {
      await _pump(tester, PaymentScreen(appointment: _held(), hooks: hooks(), clock: _clock));
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Save card for future payments')).value, isFalse);
    });

    testWidgets('paying sends exactly the card and amount, blocks a second tap while running, then shows the receipt', (tester) async {
      final gate = Completer<Appointment>();
      var calls = 0;
      PaymentRequest? sent;
      int? fee;
      await _pump(
        tester,
        PaymentScreen(
          appointment: _held(),
          clock: _clock,
          hooks: hooks(pay: (a, r, f) {
            calls++;
            sent = r;
            fee = f;
            return gate.future;
          }),
        ),
      );
      await fillCard(tester);
      await tester.tap(find.text('Pay PKR 2,000'));
      await tester.pump();
      expect(calls, 1);
      expect(payButton(tester).loading, isTrue); // loading state
      expect(payButton(tester).onPressed, isNull); // no duplicate submissions
      await tester.tap(find.byType(GlowButton).last, warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      expect(sent!.amount, 2000);
      expect(sent!.method, PaymentMethod.card);
      expect(sent!.card!.number, '4242 4242 4242 4242');
      expect(sent!.saveCard, isFalse);
      expect(fee, 0);

      gate.complete(_held().copyWith(status: AppointmentStatus.confirmed, payment: _record(), clearHold: true));
      await tester.pumpAndSettle();
      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('TXN-TEST-0001'), findsOneWidget);
    });

    testWidgets('a decline shows the reason, keeps the screen, does not give the time back, and Pay works again', (tester) async {
      var released = false;
      await _pump(
        tester,
        PaymentScreen(
          appointment: _held(),
          clock: _clock,
          hooks: hooks(release: (_) async => released = true, pay: (a, r, f) async => throw const ApiException('Your card was declined. Try another card or payment method.', statusCode: 402)),
        ),
      );
      await fillCard(tester);
      await tester.tap(find.text('Pay PKR 2,000'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your card was declined'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
      expect(released, isFalse);
      expect(payButton(tester).onPressed, isNotNull);
    });

    testWidgets('pay at clinic needs no details, says nothing is charged now, and confirms', (tester) async {
      PaymentRequest? sent;
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(pay: (a, r, f) async {
        sent = r;
        return _held().copyWith(status: AppointmentStatus.requested, payment: _record(method: PaymentMethod.clinic, status: PaymentStatus.payAtClinic), clearHold: true);
      })));
      await tester.tap(find.text('Pay at Clinic'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Card number'), findsNothing);
      expect(find.textContaining('Nothing is charged now'), findsOneWidget);
      expect(payButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Confirm, pay PKR 2,000 at clinic'));
      await tester.pumpAndSettle();
      expect(sent!.method, PaymentMethod.clinic);
      expect(find.text('Request sent'), findsWidgets);
      expect(find.text('To be paid at the clinic'), findsOneWidget);
    });

    testWidgets('a wallet needs a provider and a valid mobile number', (tester) async {
      PaymentRequest? sent;
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(pay: (a, r, f) async {
        sent = r;
        return _held().copyWith(status: AppointmentStatus.confirmed, payment: _record(method: PaymentMethod.wallet), clearHold: true);
      })));
      await tester.tap(find.text('JazzCash / EasyPaisa'));
      await tester.pumpAndSettle();
      expect(payButton(tester).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Wallet mobile number'), '0300 1234567');
      await tester.pumpAndSettle();
      expect(payButton(tester).onPressed, isNull); // still no provider
      await tester.tap(find.text('EasyPaisa'));
      await tester.pumpAndSettle();
      expect(payButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Pay PKR 2,000'));
      await tester.pumpAndSettle();
      expect(sent!.wallet, WalletProvider.easypaisa);
      expect(sent!.walletNumber, '0300 1234567');
    });

    testWidgets('a saved card asks only for its CVV and is paid by token, never by number', (tester) async {
      PaymentRequest? sent;
      const saved = SavedCard(id: 'c1', token: 'sbx_tok_abc', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030);
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(saved: const [saved], pay: (a, r, f) async {
        sent = r;
        return _held().copyWith(status: AppointmentStatus.confirmed, payment: _record(), clearHold: true);
      })));
      expect(find.text('Your saved cards'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Card number'), findsNothing);
      expect(payButton(tester).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'CVV for Visa ending 4242'), '123');
      await tester.pumpAndSettle();
      expect(payButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Pay PKR 2,000'));
      await tester.pumpAndSettle();
      expect(sent!.savedCard!.token, 'sbx_tok_abc');
      expect(sent!.card, isNull);
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(saved: const [saved])));
      await tester.tap(find.text('Use a new card'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Card number'), findsOneWidget);
    });

    testWidgets('an expired saved card is not offered', (tester) async {
      const old = SavedCard(id: 'c2', token: 'sbx_tok_y', brand: 'Visa', last4: '1111', expMonth: 1, expYear: 2024);
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(saved: const [old])));
      expect(find.text('Your saved cards'), findsNothing);
    });

    testWidgets('if the fee cannot be read there is an error and Pay stays disabled (FR37.2)', (tester) async {
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(order: (a) async => throw const ApiException('We could not read the consultation fee.'))));
      expect(find.textContaining('could not read the consultation fee'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Card number'), '4242424242424242');
      await tester.enterText(find.widgetWithText(TextField, 'Expiry (MM/YY)'), '1230');
      await tester.enterText(find.widgetWithText(TextField, 'CVV'), '123');
      await tester.enterText(find.widgetWithText(TextField, 'Cardholder name'), 'Ayesha Khan');
      await tester.pumpAndSettle();
      expect(payButton(tester).onPressed, isNull);
    });

    testWidgets('a hold that has run out says so, gives the time back, and nothing can be paid', (tester) async {
      var released = 0;
      final expired = _held(hold: const Duration(seconds: 1));
      var now = _now;
      await _pump(tester, PaymentScreen(appointment: expired, clock: () => now, hooks: hooks(release: (_) async => released++)));
      now = _now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('has run out'), findsOneWidget);
      expect(find.textContaining('Nothing was charged'), findsOneWidget);
      expect(released, 1);
    });

    testWidgets('leaving without paying gives the time back', (tester) async {
      var released = 0;
      await _pump(tester, PaymentScreen(appointment: _held(), clock: _clock, hooks: hooks(release: (_) async => released++)));
      await tester.pumpWidget(const SizedBox.shrink()); // the screen is removed, as when the member goes back
      await tester.pump();
      expect(released, 1);
    });
  });

  group('Payment success screen (FR-7)', () {
    testWidgets('shows the appointment and the payment details, and says plainly that a test payment took no money', (tester) async {
      final a = _held().copyWith(status: AppointmentStatus.confirmed, payment: _record(platform: 100), clearHold: true);
      await _pump(tester, PaymentSuccessScreen(appointment: a));
      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('Dr. Hina Malik'), findsOneWidget);
      expect(find.text('TXN-TEST-0001'), findsOneWidget);
      expect(find.text('What happens next'), findsOneWidget); // nothing is final until the specialist accepts
      expect(find.text('Copy meeting link'), findsNothing); // there is no video link yet
      expect(find.text('Visa ending 4242'), findsOneWidget);
      expect(find.text('PKR 2,100'), findsOneWidget);
      expect(find.text('Total paid'), findsOneWidget);
      expect(find.text('Test payment: no money was taken.'), findsOneWidget);
      expect(find.text('View my appointments'), findsOneWidget);
    });

    testWidgets('a live payment does not carry the test notice', (tester) async {
      final a = _held().copyWith(status: AppointmentStatus.confirmed, payment: _record(mode: 'live'), clearHold: true);
      await _pump(tester, PaymentSuccessScreen(appointment: a));
      expect(find.text('Test payment: no money was taken.'), findsNothing);
    });
  });
}

class _SlowGateway implements PaymentGateway {
  final Future<void> gate;
  _SlowGateway(this.gate);
  @override
  String get mode => 'sandbox';
  @override
  Future<GatewayResult> charge(PaymentRequest request, {DateTime? now}) async {
    await gate;
    return const GatewayResult.ok(reference: 'sbx_c_slow', brand: 'Visa', last4: '4242', mode: 'sandbox');
  }
}

import 'dart:math';
import '../models/payment.dart';
import 'payment_rules.dart';

/// Module 15, FR-5: what the app asks of a payment gateway, and what it gets back.
///
/// The scope names JazzCash (CI-5: payment "via secure server-side communication with the JazzCash API"; NFR-S9: card numbers and CVV
/// are not stored or transmitted by Baymax). A live JazzCash integration needs merchant credentials and a server that holds the secret
/// key, neither of which exist yet, so the app ships with [SandboxGateway]: the complete flow, no money moved, no card number leaving
/// the phone. To go live, write a `PaymentGateway` that calls that server (it must return the same [GatewayResult]), pass it where
/// [SandboxGateway] is used in `PaymentService`, and change the database rules so only the server can write `payment` (see README).

class PaymentRequest {
  final int amount;
  final PaymentMethod method;
  final CardInput? card;
  final bool saveCard;
  final SavedCard? savedCard;
  final String savedCardCvv;
  final WalletProvider? wallet;
  final String walletNumber;

  const PaymentRequest({
    required this.amount,
    required this.method,
    this.card,
    this.saveCard = false,
    this.savedCard,
    this.savedCardCvv = '',
    this.wallet,
    this.walletNumber = '',
  });
}

class GatewayResult {
  final bool success;

  /// The gateway's own id for the charge. Null on failure.
  final String? reference;
  final String? brand;
  final String? last4;
  final int? expMonth;
  final int? expYear;

  /// Only when the member asked to save the card: the gateway's token for it. Never the number.
  final String? cardToken;

  /// `sandbox` or `live`.
  final String mode;

  /// Why it failed, in words the member can act on.
  final String? message;

  const GatewayResult.ok({required String this.reference, this.brand, this.last4, this.expMonth, this.expYear, this.cardToken, required this.mode})
      : success = true,
        message = null;

  const GatewayResult.failed(String this.message, {required this.mode})
      : success = false,
        reference = null,
        brand = null,
        last4 = null,
        expMonth = null,
        expYear = null,
        cardToken = null;
}

abstract class PaymentGateway {
  String get mode;
  Future<GatewayResult> charge(PaymentRequest request, {DateTime? now});
}

/// A stand-in gateway for development and demonstration. It never sends anything anywhere.
///
/// To stop anyone typing a real card into a form that is not connected to a bank, it accepts only the published test cards:
/// 4242 4242 4242 4242 (Visa) and 5555 5555 5555 4444 (Mastercard) succeed, 4000 0000 0000 0002 is declined, anything else is
/// refused with an explanation. For wallets any valid mobile number succeeds, except numbers ending in 0000, which are declined.
class SandboxGateway implements PaymentGateway {
  final Duration delay;
  final Random _random;
  SandboxGateway({this.delay = const Duration(milliseconds: 900), Random? random}) : _random = random ?? Random.secure();

  static const successCards = {'4242424242424242', '5555555555554444'};
  static const declinedCard = '4000000000000002';
  static const testCardHint = 'Test mode: use the test card 4242 4242 4242 4242 (any future expiry, any 3-digit CVV).';

  @override
  String get mode => 'sandbox';

  String _id(String prefix) => '$prefix${List.generate(14, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[_random.nextInt(31)]).join()}';

  @override
  Future<GatewayResult> charge(PaymentRequest r, {DateTime? now}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (r.amount < 0) return GatewayResult.failed('The amount is not valid.', mode: mode);
    switch (r.method) {
      case PaymentMethod.clinic:
        return GatewayResult.failed('Pay at clinic does not go through the gateway.', mode: mode);
      case PaymentMethod.wallet:
        final number = PaymentRules.normalizeMobile(r.walletNumber);
        if (r.wallet == null || number == null) return GatewayResult.failed('The wallet details are not valid.', mode: mode);
        if (number.endsWith('0000')) return GatewayResult.failed('The wallet has insufficient balance. Try another wallet or method.', mode: mode);
        return GatewayResult.ok(reference: _id('sbx_w_'), last4: PaymentRules.last4(number), mode: mode);
      case PaymentMethod.card:
        final saved = r.savedCard;
        if (saved != null) {
          // A saved card is paid with its token and a fresh CVV, never with a number.
          if (!RegExp(r'^\d{3}$').hasMatch(r.savedCardCvv)) return GatewayResult.failed('Enter the 3-digit CVV of the saved card.', mode: mode);
          if (!saved.token.startsWith('sbx_tok_')) return GatewayResult.failed('This saved card was made with a different payment service and cannot be used.', mode: mode);
          return GatewayResult.ok(reference: _id('sbx_c_'), brand: saved.brand, last4: saved.last4, mode: mode);
        }
        final c = r.card;
        if (c == null) return GatewayResult.failed('The card details are missing.', mode: mode);
        final digits = PaymentRules.digitsOnly(c.number);
        if (digits == declinedCard) return GatewayResult.failed('Your card was declined. Try another card or payment method.', mode: mode);
        if (!successCards.contains(digits)) return GatewayResult.failed(testCardHint, mode: mode);
        final exp = PaymentRules.parseExpiry(c.expiry);
        return GatewayResult.ok(
          reference: _id('sbx_c_'),
          brand: PaymentRules.brandOf(digits),
          last4: PaymentRules.last4(digits),
          expMonth: exp?.month,
          expYear: exp?.year,
          cardToken: r.saveCard ? _id('sbx_tok_') : null,
          mode: mode,
        );
    }
  }
}

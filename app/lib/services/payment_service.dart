import 'dart:math';
import '../models/consultation.dart';
import '../models/payment.dart';
import 'api_client.dart' show ApiException;
import 'consultation_service.dart';
import 'payment_gateway.dart';
import 'payment_rules.dart';
import 'realtime_db.dart';

/// Module 15: takes a held booking through payment and sends it to the specialist as a request, and keeps the member's saved cards (tokens only).
class PaymentService {
  PaymentService._({PaymentGateway? gateway}) : gateway = gateway ?? SandboxGateway();
  static final PaymentService instance = PaymentService._();

  /// Swap this for a live gateway (see `payment_gateway.dart`).
  PaymentGateway gateway;

  final _inFlight = <String>{};

  /// A charge is not started with less than this left on the hold, so a payment cannot succeed after the time was given away.
  static const minHoldForCharge = Duration(seconds: 45);

  /// Pays for [appointment] and sends it to the specialist as a request (FR-5, FR-6). Throws [ApiException] with a message the member can act on when the hold has
  /// run out, the gateway declines, or the booking could not be confirmed. A decline leaves the hold in place so another method can be
  /// tried. A second call for the same booking while one is running is refused (FR37.8: no duplicate submissions).
  Future<Appointment> pay({
    required Appointment appointment,
    required PaymentRequest request,
    required int platformFee,
    DateTime? now,
    Future<Appointment> Function(Appointment, PaymentRecord)? confirm,
    Future<void> Function(SavedCard)? saveCard,
  }) async {
    final t = now ?? DateTime.now();
    if (!_inFlight.add(appointment.id)) throw const ApiException('A payment for this booking is already being processed.');
    try {
      final hold = appointment.holdUntil;
      if (appointment.status != AppointmentStatus.pendingPayment || hold == null) {
        throw const ApiException('This booking is no longer waiting for payment.');
      }
      if (PaymentRules.holdRemaining(hold, t) < minHoldForCharge) {
        throw const ApiException('The time you chose is no longer being held for you. Please go back and book again.', statusCode: 410);
      }
      final order = OrderSummary(consultationFee: appointment.fee, platformFee: platformFee);
      if (request.amount != order.total) throw const ApiException('The amount does not match the booking. Please go back and try again.');

      final txn = _transactionId();
      late final PaymentRecord record;
      if (request.method == PaymentMethod.clinic) {
        record = PaymentRecord(
          transactionId: txn,
          method: PaymentMethod.clinic,
          status: PaymentStatus.payAtClinic,
          consultationFee: order.consultationFee,
          platformFee: order.platformFee,
          reference: 'clinic-$txn',
          mode: gateway.mode,
          paidAt: t,
        );
      } else {
        final result = await gateway.charge(request, now: t);
        if (!result.success) throw ApiException(result.message ?? 'The payment did not go through.', statusCode: 402);
        record = PaymentRecord(
          transactionId: txn,
          method: request.method,
          status: PaymentStatus.paid,
          consultationFee: order.consultationFee,
          platformFee: order.platformFee,
          brand: result.brand,
          last4: result.last4,
          wallet: request.method == PaymentMethod.wallet ? request.wallet : null,
          reference: result.reference!,
          mode: result.mode,
          paidAt: t,
        );
        // Keep the card only if the member ticked the box, and only as the gateway's token.
        final token = result.cardToken;
        if (request.saveCard && token != null && result.brand != null && result.last4 != null && result.expMonth != null && result.expYear != null) {
          try {
            await (saveCard ?? this.saveCard)(SavedCard(id: '', token: token, brand: result.brand!, last4: result.last4!, expMonth: result.expMonth!, expYear: result.expYear!));
          } catch (_) {
            // The payment worked; failing to remember the card must not undo or hide that.
          }
        }
      }
      try {
        return await (confirm ?? ConsultationService.instance.submitRequest)(appointment, record);
      } catch (e) {
        // The charge succeeded but the booking could not be written. Say so, with the reference, so it can be put right.
        final detail = e is ApiException ? e.message : 'The booking could not be confirmed.';
        throw ApiException(
          record.status == PaymentStatus.paid
              ? 'Your payment went through (reference ${record.reference}) but we could not confirm the booking: $detail Please contact support with that reference.'
              : detail,
          statusCode: 500,
        );
      }
    } finally {
      _inFlight.remove(appointment.id);
    }
  }

  String _transactionId() {
    final r = Random.secure();
    return 'TXN-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-${List.generate(4, (_) => '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'[r.nextInt(34)]).join()}';
  }

  // ---- saved cards (FR37.5) -----------------------------------------------------------------------------------------------------

  Future<List<SavedCard>> loadSavedCards() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('savedCards').get();
      if (!snap.exists) return <SavedCard>[];
      final raw = RealtimeDb.plain(snap.value);
      if (raw is! Map) return <SavedCard>[];
      return [
        for (final e in raw.entries)
          if (SavedCard.fromJson(e.key as String, e.value) case final c?) c,
      ];
    });
  }

  Future<void> saveCard(SavedCard card) {
    return RealtimeDb.guard(() async {
      final ref = RealtimeDb.userRef('savedCards').push();
      await ref.set(card.toJson());
    });
  }

  Future<void> deleteCard(String id) => RealtimeDb.guard(() => RealtimeDb.userRef('savedCards/$id').remove());
}

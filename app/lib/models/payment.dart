import 'package:flutter/material.dart';

/// Module 15 (Payment Integration): the data shapes. Card numbers and CVV codes are never part of any of them: they exist only in the
/// payment screen's text fields and are handed to the gateway, which returns a reference, a brand and the last four digits.

/// FR-2, FR37.3.
enum PaymentMethod { card, wallet, clinic }

extension PaymentMethodInfo on PaymentMethod {
  String get id => name;

  String get label => const ['Credit / Debit Card', 'JazzCash / EasyPaisa', 'Pay at Clinic'][index];

  String get detail => const ['Visa or Mastercard', 'Pay from your mobile wallet', 'Pay the specialist at your visit'][index];

  IconData get icon => const [Icons.credit_card_rounded, Icons.phone_android_rounded, Icons.storefront_rounded][index];

  static PaymentMethod? fromId(Object? id) {
    for (final m in PaymentMethod.values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

enum WalletProvider { jazzcash, easypaisa }

extension WalletProviderInfo on WalletProvider {
  String get id => name;

  String get label => const ['JazzCash', 'EasyPaisa'][index];

  static WalletProvider? fromId(Object? id) {
    for (final w in WalletProvider.values) {
      if (w.id == id) return w;
    }
    return null;
  }
}

/// `paid`: the gateway took the money. `payAtClinic`: nothing was taken; the fee is due at the visit.
enum PaymentStatus { paid, payAtClinic }

extension PaymentStatusInfo on PaymentStatus {
  String get id => const ['paid', 'pay_at_clinic'][index];

  String get label => const ['Paid', 'Pay at clinic'][index];

  static PaymentStatus? fromId(Object? id) {
    for (final s in PaymentStatus.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// The fee breakdown (FR37.7). The total is always the sum, and the platform fee is shown even when it is zero.
class OrderSummary {
  final int consultationFee;
  final int platformFee;
  const OrderSummary({required this.consultationFee, this.platformFee = 0});

  int get total => consultationFee + platformFee;
}

/// What is kept about a payment, in `appointments/{id}/payment`: the transaction (scope entity "Payment Transaction").
class PaymentRecord {
  final String transactionId;
  final PaymentMethod method;
  final PaymentStatus status;
  final int consultationFee;
  final int platformFee;

  /// For a card: the brand and last four digits only. For a wallet: the provider and the last four digits of the number.
  final String? brand;
  final String? last4;
  final WalletProvider? wallet;

  /// The gateway's own reference for the charge. Never a card number.
  final String reference;

  /// `sandbox` means no money moved. A live gateway writes `live`.
  final String mode;
  final DateTime paidAt;

  const PaymentRecord({
    required this.transactionId,
    required this.method,
    required this.status,
    required this.consultationFee,
    this.platformFee = 0,
    this.brand,
    this.last4,
    this.wallet,
    required this.reference,
    this.mode = 'sandbox',
    required this.paidAt,
  });

  int get total => consultationFee + platformFee;

  bool get isTest => mode != 'live';

  /// "Visa ending 4242", "JazzCash 0300 ••• 1234", "Pay at clinic".
  String get description {
    switch (method) {
      case PaymentMethod.card:
        return '${brand ?? 'Card'} ending ${last4 ?? '••••'}';
      case PaymentMethod.wallet:
        return '${wallet?.label ?? 'Wallet'} account ending ${last4 ?? '••••'}';
      case PaymentMethod.clinic:
        return 'Pay at clinic';
    }
  }

  Map<String, Object?> toJson() => {
        'transactionId': transactionId,
        'method': method.id,
        'status': status.id,
        'consultationFee': consultationFee,
        'platformFee': platformFee,
        'total': total,
        if (brand != null) 'brand': brand,
        if (last4 != null) 'last4': last4,
        if (wallet != null) 'wallet': wallet!.id,
        'reference': reference,
        'mode': mode,
        'paidAt': paidAt.millisecondsSinceEpoch,
      };

  static PaymentRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final method = PaymentMethodInfo.fromId(raw['method']);
    final status = PaymentStatusInfo.fromId(raw['status']);
    if (method == null || status == null) return null;
    return PaymentRecord(
      transactionId: (raw['transactionId'] as String?) ?? '',
      method: method,
      status: status,
      consultationFee: ((raw['consultationFee'] as num?) ?? 0).toInt(),
      platformFee: ((raw['platformFee'] as num?) ?? 0).toInt(),
      brand: raw['brand'] as String?,
      last4: raw['last4'] as String?,
      wallet: WalletProviderInfo.fromId(raw['wallet']),
      reference: (raw['reference'] as String?) ?? '',
      mode: (raw['mode'] as String?) ?? 'sandbox',
      paidAt: DateTime.fromMillisecondsSinceEpoch(((raw['paidAt'] as num?) ?? 0).toInt()),
    );
  }
}

/// A card the member chose to keep (FR37.5). Only the gateway's token and what is printed on a receipt: never the number or the CVV.
class SavedCard {
  final String id;
  final String token;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;

  const SavedCard({required this.id, required this.token, required this.brand, required this.last4, required this.expMonth, required this.expYear});

  String get label => '$brand ending $last4';

  String get expiry => '${expMonth.toString().padLeft(2, '0')}/${(expYear % 100).toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {'token': token, 'brand': brand, 'last4': last4, 'expMonth': expMonth, 'expYear': expYear};

  static SavedCard? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'], brand = raw['brand'], last4 = raw['last4'], m = raw['expMonth'], y = raw['expYear'];
    if (token is! String || brand is! String || last4 is! String || m is! num || y is! num) return null;
    return SavedCard(id: id, token: token, brand: brand, last4: last4, expMonth: m.toInt(), expYear: y.toInt());
  }
}

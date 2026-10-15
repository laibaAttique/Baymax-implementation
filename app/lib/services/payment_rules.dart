import '../models/payment.dart';

/// Module 15: input checks and arithmetic for the payment screen, as pure functions.
///
/// Card numbers and CVV codes pass through these checks and then straight to the gateway. They are never stored, logged or sent
/// anywhere else (NFR-S9).
class CardInput {
  final String number;
  final String expiry;
  final String cvv;
  final String holder;
  const CardInput({this.number = '', this.expiry = '', this.cvv = '', this.holder = ''});
}

class PaymentRules {
  PaymentRules._();

  /// An unpaid booking keeps its time for this long (FR36.8).
  static const holdDuration = Duration(minutes: 10);

  // ---- card -------------------------------------------------------------------------------------------------------------------

  static String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// "4242424242424242" -> "4242 4242 4242 4242" (at most 16 digits).
  static String groupCardNumber(String raw) {
    final d = digitsOnly(raw);
    final t = d.length > 16 ? d.substring(0, 16) : d;
    return [for (var i = 0; i < t.length; i += 4) t.substring(i, i + 4 > t.length ? t.length : i + 4)].join(' ');
  }

  /// "1226" -> "12/26": the slash appears once two digits are typed.
  static String formatExpiry(String raw) {
    final d = digitsOnly(raw);
    final t = d.length > 4 ? d.substring(0, 4) : d;
    return t.length <= 2 ? t : '${t.substring(0, 2)}/${t.substring(2)}';
  }

  static bool luhn(String digits) {
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = int.parse(digits[i]);
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return digits.isNotEmpty && sum % 10 == 0;
  }

  /// Visa or Mastercard, which are the two brands the scope accepts. Null for anything else.
  static String? brandOf(String number) {
    final d = digitsOnly(number);
    if (d.startsWith('4')) return 'Visa';
    if (d.length >= 2) {
      final two = int.parse(d.substring(0, 2));
      if (two >= 51 && two <= 55) return 'Mastercard';
    }
    if (d.length >= 4) {
      final four = int.parse(d.substring(0, 4));
      if (four >= 2221 && four <= 2720) return 'Mastercard';
    }
    return null;
  }

  /// (month, year) of an "MM/YY" expiry, or null when it is not a real month.
  static ({int month, int year})? parseExpiry(String expiry) {
    final m = RegExp(r'^(0[1-9]|1[0-2])/(\d{2})$').firstMatch(expiry.trim());
    if (m == null) return null;
    return (month: int.parse(m.group(1)!), year: 2000 + int.parse(m.group(2)!));
  }

  /// A card works through the last day of its expiry month, so it is "in the past" only from the first day of the next month.
  static bool expiryInPast(String expiry, DateTime now) {
    final e = parseExpiry(expiry);
    if (e == null) return true;
    return !DateTime(e.year, e.month + 1, 1).isAfter(now);
  }

  /// Field errors for the card form (FR37.4): 16 digits that pass the check-digit test and are Visa or Mastercard, an expiry that
  /// is a real month and not in the past, a 3-digit CVV, a cardholder name. Empty map = valid.
  static Map<String, String> validateCard(CardInput c, DateTime now) {
    final errors = <String, String>{};
    final digits = digitsOnly(c.number);
    if (digits.length != 16) {
      errors['number'] = 'Enter the 16 digits on the front of the card.';
    } else if (!luhn(digits)) {
      errors['number'] = 'That card number is not valid. Check the digits.';
    } else if (brandOf(digits) == null) {
      errors['number'] = 'Only Visa and Mastercard cards are accepted.';
    }
    if (parseExpiry(c.expiry) == null) {
      errors['expiry'] = 'Enter the expiry as MM/YY.';
    } else if (expiryInPast(c.expiry, now)) {
      errors['expiry'] = 'This card has expired.';
    }
    if (!RegExp(r'^\d{3}$').hasMatch(c.cvv)) errors['cvv'] = 'The CVV is the 3 digits on the back.';
    final holder = c.holder.trim();
    if (holder.length < 2 || holder.length > 60 || !RegExp(r"^[A-Za-z][A-Za-z .'-]*$").hasMatch(holder)) {
      errors['holder'] = 'Enter the name as printed on the card.';
    }
    return errors;
  }

  // ---- wallet -----------------------------------------------------------------------------------------------------------------

  /// A Pakistani mobile number as 03XXXXXXXXX, from 03XX…, 3XX…, +923XX… or 923XX…; null when it is not one.
  static String? normalizeMobile(String raw) {
    var d = digitsOnly(raw);
    if (d.startsWith('92') && d.length == 12) d = '0${d.substring(2)}';
    if (d.length == 10 && d.startsWith('3')) d = '0$d';
    return RegExp(r'^03\d{9}$').hasMatch(d) ? d : null;
  }

  static String? validateWallet(WalletProvider? provider, String number) {
    if (provider == null) return 'Choose JazzCash or EasyPaisa.';
    if (normalizeMobile(number) == null) return 'Enter the mobile number of your wallet, like 0300 1234567.';
    return null;
  }

  // ---- the order --------------------------------------------------------------------------------------------------------------

  /// Whether the Pay button can be pressed (FR37.8): the chosen method's fields are all valid, and the fee could be read.
  static bool canPay({
    required PaymentMethod method,
    required DateTime now,
    required OrderSummary? order,
    CardInput card = const CardInput(),
    WalletProvider? wallet,
    String walletNumber = '',
    SavedCard? savedCard,
    String savedCardCvv = '',
  }) {
    if (order == null) return false; // FR37.2: no fee, no payment
    switch (method) {
      case PaymentMethod.card:
        if (savedCard != null) {
          return RegExp(r'^\d{3}$').hasMatch(savedCardCvv) && !expiryInPast(savedCard.expiry, now);
        }
        return validateCard(card, now).isEmpty;
      case PaymentMethod.wallet:
        return validateWallet(wallet, walletNumber) == null;
      case PaymentMethod.clinic:
        return true;
    }
  }

  // ---- the hold ---------------------------------------------------------------------------------------------------------------

  static Duration holdRemaining(DateTime holdUntil, DateTime now) {
    final d = holdUntil.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// "9:41"
  static String countdown(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// Last four digits of a number, for receipts.
  static String last4(String s) {
    final d = digitsOnly(s);
    return d.length <= 4 ? d : d.substring(d.length - 4);
  }
}

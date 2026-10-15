import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/consultation.dart';
import '../../models/payment.dart';
import '../../services/api_client.dart';
import '../../services/consultation_service.dart';
import '../../services/payment_gateway.dart';
import '../../services/payment_rules.dart';
import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/forms.dart';
import '../../widgets/glass.dart';
import 'payment_success_screen.dart';

/// The pieces the payment screen talks to. Tests and previews replace them; the app uses the defaults.
class PaymentHooks {
  /// Pays and confirms. Throws [ApiException] with a message for the member.
  final Future<Appointment> Function(Appointment appointment, PaymentRequest request, int platformFee)? pay;

  /// Gives the held time back.
  final Future<void> Function(Appointment appointment)? releaseHold;

  /// The fee breakdown. Throws when the fee cannot be read (FR37.2).
  final Future<OrderSummary> Function(Appointment appointment)? loadOrder;
  final Future<List<SavedCard>> Function()? loadSavedCards;

  /// True when the gateway is the test one (shows the test-mode notice).
  final bool? testMode;

  const PaymentHooks({this.pay, this.releaseHold, this.loadOrder, this.loadSavedCards, this.testMode});
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = PaymentRules.groupCardNumber(newValue.text);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Deleting the slash deletes the digit before it too, so backspace never gets stuck.
    var text = newValue.text;
    if (oldValue.text.length == 3 && text.length == 2 && oldValue.text.endsWith('/')) text = text.substring(0, 1);
    final t = PaymentRules.formatExpiry(text);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Module 15 (FR-1 to FR-6, mockup M37): the appointment, the fee, the method, the details, and Pay.
///
/// The booking's time is held for ten minutes (FR36.8). Leaving this screen without paying gives the time back.
class PaymentScreen extends StatefulWidget {
  final Appointment appointment;
  final PaymentHooks hooks;
  final DateTime Function()? clock;
  const PaymentScreen({Key? key, required this.appointment, this.hooks = const PaymentHooks(), this.clock}) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  OrderSummary? _order;
  String? _orderError;
  List<SavedCard> _saved = const [];

  PaymentMethod _method = PaymentMethod.card; // FR37.3: card is the default
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _holder = TextEditingController();
  final _walletNumber = TextEditingController();
  final _savedCvv = TextEditingController();
  bool _saveCard = false; // FR37.5: only if explicitly ticked
  SavedCard? _useSaved;
  WalletProvider? _wallet;

  bool _paying = false;
  bool _finished = false; // paid and replaced by the success screen, or time ran out
  bool _expired = false;
  String? _error;

  Timer? _ticker;
  Duration _remaining = PaymentRules.holdDuration;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  bool get _testMode => widget.hooks.testMode ?? PaymentService.instance.gateway.mode != 'live';

  @override
  void initState() {
    super.initState();
    for (final c in [_number, _expiry, _cvv, _holder, _walletNumber, _savedCvv]) {
      c.addListener(() => setState(() {}));
    }
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadOrder();
    _loadSaved();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in [_number, _expiry, _cvv, _holder, _walletNumber, _savedCvv]) {
      c.dispose();
    }
    // Leaving without paying gives the time back straight away (an unreleased hold would expire by itself).
    if (!_finished) unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    try {
      await (widget.hooks.releaseHold ?? ConsultationService.instance.releaseHold)(widget.appointment);
    } catch (_) {}
  }

  void _tick() {
    final hold = widget.appointment.holdUntil;
    final left = hold == null ? Duration.zero : PaymentRules.holdRemaining(hold, _now);
    if (!mounted) return;
    setState(() => _remaining = left);
    if (left == Duration.zero && !_expired && !_paying) {
      setState(() => _expired = true);
      _ticker?.cancel();
      _finished = true;
      unawaited(_release());
    }
  }

  Future<void> _loadOrder() async {
    setState(() => _orderError = null);
    try {
      final load = widget.hooks.loadOrder ??
          (Appointment a) async => OrderSummary(consultationFee: a.fee, platformFee: await ConsultationService.instance.loadPlatformFee());
      final order = await load(widget.appointment);
      if (mounted) setState(() => _order = order);
    } on ApiException catch (e) {
      if (mounted) setState(() => _orderError = e.message);
    } catch (_) {
      if (mounted) setState(() => _orderError = 'We could not read the consultation fee.');
    }
  }

  Future<void> _loadSaved() async {
    try {
      final cards = await (widget.hooks.loadSavedCards ?? PaymentService.instance.loadSavedCards)();
      final usable = cards.where((c) => !PaymentRules.expiryInPast(c.expiry, _now)).toList();
      if (mounted) {
        setState(() {
          _saved = usable;
          _useSaved = usable.isEmpty ? null : usable.first;
        });
      }
    } catch (_) {
      // No saved cards is a fine way to carry on.
    }
  }

  CardInput get _card => CardInput(number: _number.text, expiry: _expiry.text, cvv: _cvv.text, holder: _holder.text);

  bool get _canPay =>
      !_paying &&
      !_expired &&
      PaymentRules.canPay(
        method: _method,
        now: _now,
        order: _order,
        card: _card,
        wallet: _wallet,
        walletNumber: _walletNumber.text,
        savedCard: _method == PaymentMethod.card ? _useSaved : null,
        savedCardCvv: _savedCvv.text,
      );

  Future<void> _pay() async {
    if (!_canPay) return; // a second tap while paying, or a disabled button, does nothing
    final order = _order!;
    setState(() {
      _paying = true;
      _error = null;
    });
    final useSaved = _method == PaymentMethod.card ? _useSaved : null;
    final request = PaymentRequest(
      amount: order.total,
      method: _method,
      card: _method == PaymentMethod.card && useSaved == null ? _card : null,
      saveCard: _saveCard && useSaved == null,
      savedCard: useSaved,
      savedCardCvv: _savedCvv.text,
      wallet: _wallet,
      walletNumber: _walletNumber.text,
    );
    try {
      final pay = widget.hooks.pay ??
          (Appointment a, PaymentRequest r, int fee) => PaymentService.instance.pay(appointment: a, request: r, platformFee: fee);
      final confirmed = await pay(widget.appointment, request, order.platformFee);
      _finished = true;
      _ticker?.cancel();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PaymentSuccessScreen(appointment: confirmed)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.statusCode == 410) {
        // The time was given back: nothing more can be paid for here.
        _finished = true;
        _ticker?.cancel();
        setState(() => _expired = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'The payment could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  // ---- pieces -----------------------------------------------------------------------------------------------------------------

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: bold ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontSize: bold ? 16 : 14, color: AppTheme.textPrimary, fontWeight: bold ? FontWeight.w800 : FontWeight.w700))),
        ]),
      );

  Widget _methodTile(PaymentMethod m) {
    final selected = _method == m;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        tint: selected ? AppTheme.tint(AppTheme.primary, 0.16) : null,
        padding: const EdgeInsets.all(14),
        semanticLabel: '${m.label}, ${m.detail}${selected ? ', selected' : ''}',
        onTap: _paying
            ? null
            : () => setState(() {
                  _method = m;
                  _error = null;
                }),
        child: Row(children: [
          IconWell(icon: m.icon, size: 44, filled: selected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
              Text(m.detail, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppTheme.primary : AppTheme.textSecondary),
        ]),
      ),
    );
  }

  String? _fieldError(String key, String text, Map<String, String> errors) => text.isEmpty ? null : errors[key];

  Widget _cardForm() {
    final errors = PaymentRules.validateCard(_card, _now);
    final brand = PaymentRules.brandOf(_number.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_saved.isNotEmpty) ...[
        const Text('Your saved cards', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _saved) SelectChip(label: '${c.brand} ${c.last4}', selected: _useSaved?.id == c.id, onTap: () => setState(() => _useSaved = c)),
          SelectChip(label: 'Use a new card', selected: _useSaved == null, onTap: () => setState(() => _useSaved = null)),
        ]),
        const SizedBox(height: 12),
      ],
      if (_useSaved != null) ...[
        TextField(
          controller: _savedCvv,
          keyboardType: TextInputType.number,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          maxLength: 3,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_paying,
          decoration: InputDecoration(labelText: 'CVV for ${_useSaved!.label}', counterText: '', prefixIcon: const Icon(Icons.password_rounded)),
        ),
      ] else ...[
        TextField(
          controller: _number,
          keyboardType: TextInputType.number,
          enableSuggestions: false,
          autocorrect: false,
          inputFormatters: [_CardNumberFormatter()],
          enabled: !_paying,
          decoration: InputDecoration(
            labelText: 'Card number',
            hintText: '1234 5678 9012 3456',
            errorText: _fieldError('number', _number.text, errors),
            prefixIcon: const Icon(Icons.credit_card_rounded),
            suffixText: brand,
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _expiry,
              keyboardType: TextInputType.number,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: [_ExpiryFormatter()],
              enabled: !_paying,
              decoration: InputDecoration(labelText: 'Expiry (MM/YY)', hintText: 'MM/YY', errorText: _fieldError('expiry', _expiry.text, errors)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _cvv,
              keyboardType: TextInputType.number,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 3,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_paying,
              decoration: InputDecoration(labelText: 'CVV', counterText: '', errorText: _fieldError('cvv', _cvv.text, errors)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _holder,
          textCapitalization: TextCapitalization.words,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !_paying,
          decoration: InputDecoration(labelText: 'Cardholder name', errorText: _fieldError('holder', _holder.text, errors), prefixIcon: const Icon(Icons.person_rounded)),
        ),
        CheckboxListTile(
          value: _saveCard,
          onChanged: _paying ? null : (v) => setState(() => _saveCard = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Save card for future payments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
          subtitle: const Text('Only a secure token is kept, never the card number or CVV.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        ),
      ],
    ]);
  }

  Widget _walletForm() {
    final err = _walletNumber.text.isEmpty && _wallet == null ? null : PaymentRules.validateWallet(_wallet, _walletNumber.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final w in WalletProvider.values) SelectChip(label: w.label, selected: _wallet == w, onTap: () => setState(() => _wallet = w)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _walletNumber,
        keyboardType: TextInputType.phone,
        enabled: !_paying,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(16)],
        decoration: InputDecoration(
          labelText: 'Wallet mobile number',
          hintText: '0300 1234567',
          prefixIcon: const Icon(Icons.phone_android_rounded),
          errorText: _walletNumber.text.isEmpty ? null : (PaymentRules.normalizeMobile(_walletNumber.text) == null ? err : null),
        ),
      ),
      if (_wallet == null && _walletNumber.text.isNotEmpty)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose JazzCash or EasyPaisa.', style: TextStyle(color: AppTheme.error, fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final order = _order;
    final payLabel = order == null
        ? 'Pay'
        : _method == PaymentMethod.clinic
            ? 'Confirm, pay ${ConsultationService.pkr(order.total)} at clinic'
            : 'Pay ${ConsultationService.pkr(order.total)}';

    return PopScope(
      canPop: !_paying,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment'),
          actions: [
            // FR37.6: the padlock is in the app bar, so no scroll position can hide it.
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Semantics(label: 'Secure payment', child: const Icon(Icons.lock_rounded, color: AppTheme.teal)),
            ),
          ],
        ),
        body: _expired
            ? MessageState(
                icon: Icons.timer_off_rounded,
                message: 'Your time was held for ${PaymentRules.holdDuration.inMinutes} minutes and has run out, so it was given back. Nothing was charged. Please book again.',
                onRetry: () => Navigator.pop(context),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(20, 4, 20, AppTheme.navSpace(context)),
                children: [
                  // FR37.1: the booking, read only.
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconWell(icon: a.role.icon, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.specialistName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary)),
                            const SizedBox(height: 4),
                            InfoChip(a.role.label, icon: a.role.icon),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      _summaryRow('Date', ConsultationService.formatDate(a.startAt)),
                      _summaryRow('Time', ConsultationService.formatTime(a.startAt)),
                      _summaryRow('Type', a.type.label),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Semantics(
                      liveRegion: _remaining.inSeconds <= 60,
                      child: Row(children: [
                        Icon(Icons.timer_rounded, size: 18, color: _remaining.inSeconds <= 60 ? AppTheme.error : AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('Your time is held for ${PaymentRules.countdown(_remaining)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _remaining.inSeconds <= 60 ? AppTheme.error : AppTheme.textSecondary)),
                        ),
                      ]),
                    ),
                  ),
                  if (_testMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: GlassCard(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.science_rounded, color: AppTheme.warning),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Test mode. No money is taken and real cards are not accepted. Use test card 4242 4242 4242 4242 with any future expiry and any 3-digit CVV (4000 0000 0000 0002 is declined).',
                              style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  const SectionHeader('Payment method', padding: EdgeInsets.fromLTRB(2, 20, 0, 10)),
                  for (final m in PaymentMethod.values) _methodTile(m),
                  const SizedBox(height: 4),
                  if (_method == PaymentMethod.card) _cardForm(),
                  if (_method == PaymentMethod.wallet) _walletForm(),
                  if (_method == PaymentMethod.clinic)
                    const GlassCard(
                      child: Text(
                        'Nothing is charged now. Your appointment is confirmed and the fee is paid to the specialist at your visit.',
                        style: TextStyle(height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SectionHeader('Order summary', padding: EdgeInsets.fromLTRB(2, 20, 0, 8)),
                  if (_orderError != null)
                    MessageState(message: '$_orderError You cannot pay until it is shown.', onRetry: _loadOrder)
                  else if (order == null)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else
                    GlassCard(
                      child: Column(children: [
                        _summaryRow('Consultation fee', ConsultationService.pkr(order.consultationFee)),
                        _summaryRow('Platform fee', ConsultationService.pkr(order.platformFee)), // shown even when it is PKR 0
                        const Divider(height: 20),
                        _summaryRow('Total', ConsultationService.pkr(order.total), bold: true),
                      ]),
                    ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, height: 1.4))),
                    ),
                  GlowButton(label: payLabel, icon: Icons.lock_rounded, loading: _paying, onPressed: _canPay ? _pay : null),
                  const SizedBox(height: 12),
                  const Text(
                    'Card numbers and CVV codes are sent only to the payment service and are never stored by Baymax.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ],
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/consultation.dart';
import '../../models/payment.dart';
import '../../services/consultation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'my_appointments_screen.dart';

/// Module 15, FR-7: the receipt. Shown once the booking is confirmed, with the appointment and the payment.
class PaymentSuccessScreen extends StatelessWidget {
  final Appointment appointment;
  const PaymentSuccessScreen({Key? key, required this.appointment}) : super(key: key);

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 116, child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(value, textAlign: TextAlign.end, style: TextStyle(fontSize: bold ? 16 : 14, color: AppTheme.textPrimary, fontWeight: bold ? FontWeight.w800 : FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final p = a.payment;
    final atClinic = p?.status == PaymentStatus.payAtClinic;
    return PopScope(
      canPop: false, // the booking is done; going "back" into the payment form would be confusing
      child: Scaffold(
        appBar: AppBar(title: const Text('Request sent'), automaticallyImplyLeading: false),
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, AppTheme.navSpace(context)),
          children: [
            GlassCard(
              child: Column(children: [
                const IconWell(icon: Icons.check_circle_rounded, size: 64, color: AppTheme.success),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(atClinic ? 'Request sent' : 'Payment successful', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 6),
                Text(
                  atClinic
                      ? 'Your request is with ${a.specialistName}. Pay ${ConsultationService.pkr(a.fee + (p?.platformFee ?? 0))} at your visit.'
                      : 'Your request is with ${a.specialistName}. Nothing is final until they accept.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SectionHeader('Appointment', padding: EdgeInsets.fromLTRB(2, 20, 0, 8)),
            GlassCard(
              child: Column(children: [
                _row('Specialist', a.specialistName),
                _row('Role', a.role.label),
                _row('Date', ConsultationService.formatDate(a.startAt)),
                _row('Time', ConsultationService.formatTime(a.startAt)),
                _row('Type', a.type.label),
              ]),
            ),
            if (p != null) ...[
              const SectionHeader('Payment', padding: EdgeInsets.fromLTRB(2, 20, 0, 8)),
              GlassCard(
                child: Column(children: [
                  _row('Transaction', p.transactionId),
                  _row('Method', p.description),
                  _row('Status', atClinic ? 'To be paid at the clinic' : 'Paid'),
                  _row('Consultation fee', ConsultationService.pkr(p.consultationFee)),
                  _row('Platform fee', ConsultationService.pkr(p.platformFee)),
                  const Divider(height: 20),
                  _row(atClinic ? 'Total due' : 'Total paid', ConsultationService.pkr(p.total), bold: true),
                  if (p.isTest)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.science_rounded, size: 18, color: AppTheme.warning),
                        SizedBox(width: 8),
                        Expanded(child: Text('Test payment: no money was taken.', style: TextStyle(fontSize: 13, color: AppTheme.warning, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                ]),
              ),
            ],
            const SectionHeader('What happens next', padding: EdgeInsets.fromLTRB(2, 20, 0, 8)),
            const GlassCard(
              child: Text(
                'The specialist reviews your request. When they accept, you get a notification and the video link appears in My appointments. If they cannot take it, the time is released and you are told, so you can book another.',
                style: TextStyle(height: 1.45, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),
            GlowButton(
              label: 'View my appointments',
              icon: Icons.event_note_rounded,
              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MyAppointmentsScreen()), (r) => r.isFirst),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('Back to home')),
          ],
        ),
      ),
    );
  }
}

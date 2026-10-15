import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        appBar: AppBar(title: const Text('Booking confirmed'), automaticallyImplyLeading: false),
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, AppTheme.navSpace(context)),
          children: [
            GlassCard(
              child: Column(children: [
                const IconWell(icon: Icons.check_circle_rounded, size: 64, color: AppTheme.success),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(atClinic ? 'Appointment confirmed' : 'Payment successful', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 6),
                Text(
                  atClinic ? 'Pay ${ConsultationService.pkr(a.fee + (p?.platformFee ?? 0))} to the specialist at your visit.' : 'Your appointment is booked. A confirmation is in your notifications.',
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
            const SectionHeader('Meeting room', padding: EdgeInsets.fromLTRB(2, 20, 0, 8)),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('The room opens 5 minutes before your appointment. You can find this link again in My appointments.', style: TextStyle(height: 1.4, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                SelectableText(a.meetingLink, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: a.meetingLink));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting link copied.')));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy meeting link'),
                ),
              ]),
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

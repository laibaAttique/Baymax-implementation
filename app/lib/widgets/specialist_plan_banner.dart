import 'package:flutter/material.dart';
import '../models/specialist_plan.dart';
import '../services/api_client.dart';
import '../services/consultation_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Module 14 (FR-5, FR-9, FR-10): shows that a specialist reviewed or changed this plan, who and when, and lets the member switch
/// between the specialist's plan and Baymax's own. Shows nothing when no specialist has set a plan of this kind.
class SpecialistPlanBanner extends StatefulWidget {
  /// True for the nutrition plan, false for the workout plan.
  final bool diet;
  const SpecialistPlanBanner({Key? key, required this.diet}) : super(key: key);

  @override
  State<SpecialistPlanBanner> createState() => _SpecialistPlanBannerState();
}

class _SpecialistPlanBannerState extends State<SpecialistPlanBanner> {
  bool _busy = false;

  Future<void> _toggle(bool follow) async {
    setState(() => _busy = true);
    try {
      await UserSession.instance.setPlanChoice(diet: widget.diet ? follow : null, workout: widget.diet ? null : follow);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your choice. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final plans = session.specialistPlans;
    final by = widget.diet ? plans.diet?.by : plans.workout?.by;
    if (by == null) return const SizedBox.shrink();
    final approved = widget.diet ? plans.diet!.approvedAsIs : plans.workout!.approvedAsIs;
    final at = widget.diet ? plans.diet!.at : plans.workout!.at;
    final note = widget.diet ? plans.diet!.note : plans.workout!.note;
    final following = widget.diet ? session.planChoices.specialistDiet : session.planChoices.specialistWorkout;
    final kind = widget.diet ? 'nutrition' : 'workout';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: GlassCard(
        tint: AppTheme.tint(AppTheme.teal, 0.12),
        semanticLabel: '${approved ? 'Reviewed' : 'Adjusted'} by ${by.label}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconWell(icon: approved ? Icons.verified_rounded : Icons.edit_note_rounded, size: 40, color: AppTheme.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(approved ? 'Reviewed by ${by.label}' : 'Adjusted by ${by.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  approved
                      ? 'They looked at your $kind plan on ${ConsultationService.formatDate(at)} and approved it as it is.'
                      : following
                          ? 'Since ${ConsultationService.formatDate(at)} you are following their $kind plan.'
                          : 'You are using Baymax\'s own $kind plan. Their plan from ${ConsultationService.formatDate(at)} is saved.',
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
          ]),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('"$note"', style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppTheme.textPrimary, fontStyle: FontStyle.italic)),
          ],
          if (!approved) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _toggle(!following),
              child: Text(following ? 'Use Baymax\'s plan instead' : 'Use ${by.name}\'s plan'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The nutritionist's verdict on one day of the food log (FR-9).
class DietReviewCard extends StatelessWidget {
  final DietReview review;
  const DietReviewCard({Key? key, required this.review}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = review.approved ? AppTheme.success : AppTheme.warning;
    return GlassCard(
      tint: AppTheme.tint(color, 0.12),
      semanticLabel: review.approved ? 'Food log approved by ${review.reviewer}' : 'Food log flagged by ${review.reviewer}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconWell(icon: review.approved ? Icons.check_circle_rounded : Icons.flag_rounded, size: 40, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(review.approved ? 'Approved by ${review.reviewer}' : 'Flagged by ${review.reviewer}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(
              review.note.isNotEmpty ? review.note : (review.approved ? 'Your nutritionist reviewed this day and it looks fine.' : 'Your nutritionist marked this day for attention.'),
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ]),
    );
  }
}

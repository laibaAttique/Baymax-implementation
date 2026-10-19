import '../../models/plan.dart';
import 'safety_rule_engine.dart';

/// Module 4 knowledge base, part 3: the training profile for each Module 2 health classification. DATA ONLY, plus the
/// small calculation that measures a generated week against its profile.
///
/// A profile says what kind of week suits the classification: the highest intensity band to schedule (from the
/// exercise's Compendium MET, see [IntensityBand]), the weekly aerobic, strength and flexibility targets, and the most
/// rest days in a row. It never relaxes a safety rule: the band cap is merged by the rule engine with the same
/// "most restrictive wins" logic, and an exercise without a MET value is not scheduled under a capped profile.
///
/// The targets restate published recommendations (WHO 2020 for adults, ADA 2016 for diabetes, ACSM for flexibility);
/// the band caps for Obese, At-Risk and Cardiac are team precautions. Every profile is `pending` professional review.
/// Changing a profile: edit it here, bump [ClassificationProfiles.version], note it in PROGRESS.md.
class ClassificationProfile {
  final String id;

  /// Module 2 category (`ClassificationResult.category`).
  final String category;
  final IntensityBand maxBand;

  /// Moderate-equivalent aerobic minutes per week.
  final int aerobicMin;
  final int aerobicMax;
  final int strengthDays;
  final int flexibilityDays;

  /// Most days in a row without a workout, or null for no limit.
  final int? maxRestDaysInRow;

  /// Shown to the user.
  final String emphasis;

  /// Why the band cap is what it is.
  final RuleBasis bandBasis;
  final List<String> evidence;
  final String reviewStatus;

  const ClassificationProfile({
    required this.id,
    required this.category,
    required this.maxBand,
    this.aerobicMin = 150,
    this.aerobicMax = 300,
    this.strengthDays = 2,
    this.flexibilityDays = 2,
    this.maxRestDaysInRow,
    required this.emphasis,
    required this.bandBasis,
    required this.evidence,
    this.reviewStatus = 'pending',
  });
}

/// A note added to the profile summary when its condition holds (explanations only, no restriction).
class ProfileNote {
  final String id;
  final List<Pred> when;
  final String text;
  final List<String> evidence;
  final String reviewStatus;
  const ProfileNote({required this.id, required this.when, required this.text, required this.evidence, this.reviewStatus = 'pending'});
}

class ClassificationProfiles {
  ClassificationProfiles._();

  static const version = 'profiles-2026.10.1';

  /// Used for a category this repository does not know: the most conservative of the non-cardiac profiles.
  static const fallbackCategory = 'At-Risk';

  static const all = <ClassificationProfile>[
    ClassificationProfile(
      id: 'PRF-HEALTHY',
      category: 'Healthy',
      maxBand: IntensityBand.vigorous,
      emphasis: 'A balanced week of aerobic and muscle-strengthening work.',
      bandBasis: RuleBasis.guideline,
      evidence: ['who2020', 'acsm11'],
    ),
    ClassificationProfile(
      id: 'PRF-OVERWEIGHT',
      category: 'Overweight',
      maxBand: IntensityBand.vigorous,
      emphasis: 'Regular aerobic work with strength training to support weight management.',
      bandBasis: RuleBasis.guideline,
      evidence: ['who2020', 'acsm11'],
    ),
    ClassificationProfile(
      id: 'PRF-OBESE',
      category: 'Obese',
      maxBand: IntensityBand.moderate,
      emphasis: 'Low-impact aerobic work at a moderate effort, with strength training, built up gradually.',
      bandBasis: RuleBasis.teamPrecaution,
      evidence: ['who2020', 'acsm11'],
    ),
    ClassificationProfile(
      id: 'PRF-AT-RISK',
      category: 'At-Risk',
      maxBand: IntensityBand.moderate,
      emphasis: 'A gentle start at moderate effort, increased step by step as you get fitter.',
      bandBasis: RuleBasis.teamPrecaution,
      evidence: ['who2020', 'acsm11'],
    ),
    ClassificationProfile(
      id: 'PRF-DIABETIC',
      category: 'Diabetic',
      maxBand: IntensityBand.vigorous,
      maxRestDaysInRow: 2,
      emphasis: 'Activity spread across the week, with no more than two days in a row without exercise, plus strength training.',
      bandBasis: RuleBasis.guideline,
      evidence: ['ada2016', 'who2020'],
    ),
    ClassificationProfile(
      id: 'PRF-CARDIAC',
      category: 'Cardiac',
      maxBand: IntensityBand.moderate,
      emphasis: 'Steady, low-impact aerobic work at a moderate effort. Follow the advice of your doctor or cardiac rehabilitation team.',
      bandBasis: RuleBasis.teamPrecaution,
      evidence: ['aha2024', 'acsm11', 'who2020'],
    ),
  ];

  static const notes = <ProfileNote>[
    ProfileNote(
      id: 'PN-STAT-RISK',
      when: [Pred(Fact.statisticalRisk, Op.eq, true)],
      text: 'You reported no condition, but Module 2\'s screening model puts people like you at higher than average risk, '
          'so your plan starts at a moderate effort. This is a screening estimate, not a diagnosis.',
      evidence: ['who2020'],
    ),
    ProfileNote(
      id: 'PN-PCOS',
      when: [Pred(Fact.conditions, Op.contains, 'PCOS')],
      text: 'PCOS: regular aerobic activity and strength training on two or more days a week are recommended. '
          'Your plan follows the same weekly targets.',
      evidence: ['pcos2023'],
    ),
    ProfileNote(
      id: 'PN-RISK-HIGH',
      when: [Pred(Fact.riskLevel, Op.eq, 'High')],
      text: 'Module 2 rated your health risk as high: build up slowly and talk to your doctor before increasing the effort.',
      evidence: ['riebe2015'],
    ),
  ];

  static ClassificationProfile forCategory(String category) =>
      all.where((p) => p.category == category).firstOrNull ?? all.firstWhere((p) => p.category == fallbackCategory);

  /// The longest run of days without a workout, counting across the end of the week into the next one.
  static int longestRest(List<bool> workoutDays) {
    if (!workoutDays.contains(true)) return workoutDays.length;
    var longest = 0;
    var run = 0;
    for (var i = 0; i < workoutDays.length * 2; i++) {
      if (workoutDays[i % workoutDays.length]) {
        run = 0;
      } else {
        run++;
        if (run > longest) longest = run;
      }
    }
    return longest.clamp(0, workoutDays.length);
  }

  /// Measures [week] against [profile]. [extraNotes] are explanations from the generator (e.g. an added training day);
  /// the [notes] whose conditions hold for [facts] are added (none when [facts] is null).
  static PlanProfileSummary summarize(ClassificationProfile profile, List<WorkoutDay?> week, HealthFacts? facts,
      {List<String> extraNotes = const []}) {
    var aerobic = 0.0;
    var strength = 0;
    var flexibility = 0;
    for (final d in week) {
      if (d == null) continue;
      var strengthDay = false;
      var flexibilityDay = false;
      for (final p in d.exercises) {
        final e = p.exercise;
        if (e.group == 'cardio') {
          final band = e.intensityBand;
          if (band == IntensityBand.moderate) aerobic += p.activeSeconds / 60;
          if (band == IntensityBand.vigorous) aerobic += 2 * p.activeSeconds / 60;
        } else if (const {'legs', 'push', 'back', 'core'}.contains(e.group)) {
          strengthDay = true;
        } else if (e.group == 'mobility' && !e.tags.contains('dynamic') && !e.tags.contains('balance')) {
          flexibilityDay = true;
        }
      }
      if (strengthDay) strength++;
      if (flexibilityDay) flexibility++;
    }
    final minutes = aerobic.round();
    final notes = <String>[
      ...extraNotes,
      if (facts != null)
        for (final n in ClassificationProfiles.notes)
          if (n.when.every(facts.test)) '${n.text} (${n.id})',
    ];
    if (minutes < profile.aerobicMin) {
      final restDays = week.where((d) => d == null).length;
      final gap = profile.aerobicMin - minutes;
      final perDay = restDays == 0 ? 0 : (((gap / restDays) / 5).ceil() * 5);
      notes.add(restDays == 0
          ? 'Your sessions give about $minutes aerobic minutes a week; the recommended minimum is ${profile.aerobicMin}. '
              'Daily brisk walking counts towards it. (${profile.id})'
          : 'Your sessions give about $minutes aerobic minutes a week; the recommended minimum is ${profile.aerobicMin}. '
              'A brisk walk of about $perDay minutes on each day without a workout would close the gap. (${profile.id})');
    }
    return PlanProfileSummary(
      profileId: profile.id,
      category: profile.category,
      emphasis: profile.emphasis,
      maxBand: profile.maxBand,
      aerobicMinutes: minutes,
      aerobicTargetMin: profile.aerobicMin,
      aerobicTargetMax: profile.aerobicMax,
      strengthDays: strength,
      strengthTarget: profile.strengthDays,
      flexibilityDays: flexibility,
      flexibilityTarget: profile.flexibilityDays,
      notes: notes,
      evidence: profile.evidence,
    );
  }
}

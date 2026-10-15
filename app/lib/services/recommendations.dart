import 'package:flutter/material.dart';
import '../models/health_profile.dart';
import '../models/plan.dart';
import 'health_classifier.dart';

/// One recommended action shown on the classification result screen (Module 2, mockup M8 FR8.5).
class RecommendedAction {
  final IconData icon;
  final String title;
  final String detail;
  const RecommendedAction(this.icon, this.title, this.detail);
}

/// Actions that follow from the user's classification, goal and plan. Every figure comes from the plan or the profile (the calorie
/// target, the workout days, the water target); the salt limit is the WHO sodium guideline listed on the Sources screen. Advice that
/// depends on a medical condition is general and always points to the user's doctor for anything specific.
List<RecommendedAction> recommendedActions(HealthProfile p, ClassificationResult cls, PersonalizedPlan plan) {
  final out = <RecommendedAction>[];

  out.add(RecommendedAction(
    Icons.directions_run_rounded,
    '${plan.intensity} exercise ${plan.workoutDays}x a week',
    'Your weekly plan is built for your health category. Moves that would be unsafe for you are left out.',
  ));

  final maintain = p.calorieTargets.maintain;
  final target = plan.nutrition.targetKcal;
  final gap = ((maintain - target).abs() / 10).round() * 10;
  if (target < maintain - 50) {
    out.add(RecommendedAction(Icons.trending_down_rounded, 'Calorie deficit of about $gap kcal a day', 'Aim for about $target kcal a day. A modest deficit is easier to keep up than a harsh one.'));
  } else if (target > maintain + 50) {
    out.add(RecommendedAction(Icons.trending_up_rounded, 'Calorie surplus of about $gap kcal a day', 'Aim for about $target kcal a day, with enough protein, to support muscle gain.'));
  } else {
    out.add(RecommendedAction(Icons.balance_rounded, 'Eat around $target kcal a day', 'That matches what your body uses, which keeps your weight steady.'));
  }

  out.add(RecommendedAction(Icons.water_drop_rounded, 'Drink about ${plan.nutrition.waterLitres.toStringAsFixed(1)} L of water a day', 'Sip through the day, and a little more when you sweat.'));

  if (p.hasCondition('Diabetes')) {
    out.add(const RecommendedAction(Icons.restaurant_rounded, 'Spread carbohydrates across your meals', 'Choose slow-digesting carbs such as whole grains and pulses, and monitor your blood sugar as your doctor advises.'));
  }
  if (cls.isCardiac || p.hasCondition('Hypertension')) {
    out.add(const RecommendedAction(Icons.no_food_rounded, 'Keep salt under 5 g a day', 'About one teaspoon in total, including salt already in packaged food (WHO guideline).'));
  }
  if (p.hasCondition('Asthma')) {
    out.add(const RecommendedAction(Icons.air_rounded, 'Warm up well and keep your reliever close', 'Start gently, and keep your prescribed inhaler with you when you train.'));
  }
  if (p.bmi >= 30) {
    out.add(const RecommendedAction(Icons.directions_walk_rounded, 'Start with low-impact exercise', 'Walking, cycling and swimming are kind to your joints while you build up.'));
  } else if (p.bmi > 0 && p.bmi < 18.5) {
    out.add(const RecommendedAction(Icons.lunch_dining_rounded, 'Add nutrient-dense snacks', 'Nuts, yoghurt and fruit add calories and nutrients without large meals.'));
  }
  if (cls.isCardiac || cls.isDiabetic || cls.riskLevel == 'High') {
    out.add(const RecommendedAction(Icons.medical_services_rounded, 'Talk to your doctor before you begin', 'Baymax is decision support, not medical care. Check that this plan suits you.'));
  }
  return out;
}

/// Convenience for the insight text: the single most important next step, in one sentence.
String firstStep(List<RecommendedAction> actions) => actions.isEmpty ? '' : actions.first.title;

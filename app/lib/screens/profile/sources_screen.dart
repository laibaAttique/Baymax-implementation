import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class _Source {
  final String topic;
  final String howWeUseIt;
  final List<String> references;
  final String? caveat;
  const _Source(this.topic, this.howWeUseIt, this.references, {this.caveat});
}

/// Where every number in the app comes from, and what its limits are.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({Key? key}) : super(key: key);

  static const _sources = <_Source>[
    _Source(
      'BMI & health classification',
      'BMI = weight (kg) ÷ height (m)². Bands: under 18.5 underweight, 18.5–24.9 normal, 25–29.9 overweight, 30 and above obese. '
          'Medical conditions you report (heart disease, diabetes, hypertension, asthma, PCOS) override BMI when choosing your category.',
      [
        'WHO. Obesity: preventing and managing the global epidemic. WHO Technical Report Series 894, 2000.',
        'WHO Expert Consultation. Appropriate body-mass index for Asian populations and its implications for policy and intervention strategies. The Lancet 2004; 363: 157–163.',
      ],
      caveat: 'The app uses the international WHO cut-offs. The 2004 WHO consultation found that risk can rise at lower BMI in Asian populations '
          '(from about 23), so your result may understate risk. The category rules themselves are a screening tool built by the project team, not a diagnosis.',
    ),
    _Source(
      'Statistical risk estimate (machine learning)',
      'A Logistic Regression model, trained on about 250,000 adults in a CDC health survey, estimates how common diabetes and heart disease are among people with your BMI, age, sex and activity level. '
          'If no condition is reported and the estimate is far above average (about the highest 15% of the survey), you are shown as At-Risk. The model never labels anyone Diabetic or Cardiac; only a reported diagnosis does.',
      [
        'CDC Diabetes Health Indicators dataset, from the CDC Behavioral Risk Factor Surveillance System (BRFSS). UCI Machine Learning Repository, dataset 891, doi 10.24432/C53919.',
      ],
      caveat: 'Survey data from US adults, self-reported, and the survey year is stated inconsistently by its distributors (2014 vs 2015). Using only four inputs, the model ranks people moderately well '
          '(ROC-AUC about 0.73 for diabetes and 0.76 for heart disease on held-out data) and is not validated for South Asian populations. It is a screening guide, not a diagnosis.',
    ),
    _Source(
      'Calories (BMR and daily needs)',
      'Resting energy (BMR) uses the Mifflin–St Jeor equation. Daily needs multiply BMR by an activity factor: 1.2 sedentary, 1.375 lightly active, 1.55 moderately active, 1.725 very active, 1.9 athlete.',
      [
        'Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 1990; 51(2): 241–247.',
        'FAO/WHO/UNU. Human energy requirements. Food and Nutrition Technical Report Series 1, 2004 (physical activity levels).',
      ],
      caveat: 'The activity factors are the conventional multipliers used with this equation, not values taken from a single WHO table. '
          'The goal adjustments (−500 kcal to lose weight, +300 kcal to gain) and the safety floors (1,200 kcal women, 1,500 kcal men) are project design choices based on common practice. '
          'Predictions are averages and can be off by a few hundred kcal for an individual.',
    ),
    _Source(
      'Protein, fat, carbohydrate and water',
      'Protein 1.2–1.8 g per kg of body weight depending on goal (lower if you have heart disease, diabetes or hypertension). Fat about 27% of calories. Carbohydrate is the remainder (capped at 40% of calories if you have diabetes). Water about 35 ml per kg.',
      [
        'Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports Nutrition Position Stand: protein and exercise. J Int Soc Sports Nutr 2017; 14: 20.',
        'Institute of Medicine. Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids. National Academies Press, 2005 (acceptable macronutrient distribution ranges).',
        'Evert AB, et al. Nutrition therapy for adults with diabetes or prediabetes: a consensus report. Diabetes Care 2019; 42(5): 731–754.',
        'EFSA Panel on Dietetic Products, Nutrition and Allergies. Scientific opinion on dietary reference values for water. EFSA Journal 2010; 8(3): 1459.',
        'WHO. Guideline: Sodium intake for adults and children, 2012 (less than 5 g of salt per day).',
      ],
      caveat: 'The sports-nutrition position stand recommends about 1.4–2.0 g of protein per kg for most exercising people; the 1.6–1.8 g/kg used for weight loss and muscle gain falls inside that range, '
          'while the 1.2 g/kg used for maintenance (and the lower caps for heart disease, diabetes and hypertension) is a project choice above the general dietary allowance. '
          'The diabetes consensus report finds no single ideal carbohydrate percentage and advises individualising it, so the 40% cap is a conservative default chosen by the team. '
          'People with diabetes or kidney or heart disease should have their targets set by a doctor or dietitian.',
    ),
    _Source(
      'Workout plans and safety rules',
      'Weekly volume follows general adult activity guidance (150–300 minutes of moderate activity plus muscle-strengthening on at least 2 days). '
          'Exercises are chosen by your health category: high-impact moves are removed for BMI 30+, heart disease, hypertension and age 55+; high-intensity intervals are removed for heart disease, hypertension, diabetes and asthma; '
          'static holds (planks, wall sits) are removed for heart disease and capped at 20 seconds for hypertension; balance training is added from age 65.',
      [
        'WHO. Guidelines on physical activity and sedentary behaviour. Geneva, 2020 (weekly volume; balance and strength training for adults 65+).',
        'American College of Sports Medicine. ACSM\'s Guidelines for Exercise Testing and Prescription, 11th ed. Wolters Kluwer, 2021.',
        'Paluch AE, et al. Resistance exercise training in individuals with and without cardiovascular disease: 2023 update — a scientific statement from the American Heart Association. Circulation 2024; 149: e217–e231.',
        'Colberg SR, et al. Physical activity/exercise and diabetes: a position statement of the American Diabetes Association. Diabetes Care 2016; 39(11): 2065–2079.',
        'Pescatello LS, et al. Exercise and hypertension (ACSM position stand). Med Sci Sports Exerc 2004; 36(3): 533–553.',
      ],
      caveat: 'These guidelines say resistance and aerobic exercise are generally beneficial and advise medical clearance for people with heart disease, diabetes or high blood pressure. '
          'The specific exclusions and caps above (for example no static holds with heart disease, the 20-second hold cap, no HIIT with asthma, the age-55 impact limit) are conservative precautions chosen by the project team; '
          'they are not quoted from those documents and have not been reviewed by a clinician.',
    ),
    _Source(
      'Exercise library',
      'The exercises are stored in Cloud Firestore so they can be corrected or extended without an app update, with an offline copy bundled in the app. '
          'Each exercise records its energy value (Compendium code), its muscle groups, and where its technique text comes from. '
          '15 of the 32 entries are matched to the free-exercise-db open dataset for muscles and technique; the other 17 (for example brisk walking, jumping jacks, burpees, wall sit, bird dog) have no suitable entry and are written by the team.',
      [
        'free-exercise-db — open public-domain (Unlicense) exercise dataset, github.com/yuhonas/free-exercise-db.',
        'Herrmann SD, et al. 2024 Adult Compendium of Physical Activities. J Sport Health Sci 2024; 13(1): 6–12 (energy values).',
      ],
      caveat: 'free-exercise-db is community-maintained, not clinically reviewed, and its wording is written for gym training (for example it says to hold a plank "as long as possible"), so the cues are rewritten here for the prescribed dosage. '
          'The team-written cues should be reviewed by a qualified trainer or physiotherapist before release.',
    ),
    _Source(
      'Calories burned in workouts',
      'Calories = MET value × your weight (kg) × time (hours). Each exercise uses the MET value of the matching entry in the Compendium; the code is shown on the exercise page. '
          'A trailing * means the exact exercise is not listed, so the closest listed activity was used (marching in place, step-ups, high knees, mountain climbers, shadow boxing, single-leg balance).',
      [
        'Herrmann SD, Willis EA, Ainsworth BE, et al. 2024 Adult Compendium of Physical Activities: a third update of the energy costs of human activities. J Sport Health Sci 2024; 13(1): 6–12. (pacompendium.com)',
      ],
      caveat: 'MET values are averages from study samples. Your real energy use depends on fitness, body composition and effort.',
    ),
    _Source(
      'Food calories and nutrients',
      'Foods marked "USDA" use values from USDA FoodData Central (Foundation and SR Legacy data, per 100 g) scaled to the portion you log. '
          'Foods marked "estimate" are typical-serving figures compiled by the project team and have not yet been checked against a food-composition table.',
      [
        'U.S. Department of Agriculture, Agricultural Research Service. FoodData Central. fdc.nal.usda.gov.',
        'Food Composition Table for Pakistan (revised 2001). Department of Agricultural Chemistry and Human Nutrition, NWFP Agricultural University Peshawar; UNICEF Islamabad; Ministry of Planning and Development, Government of Pakistan. Listed by FAO/INFOODS.',
      ],
      caveat: 'Mixed home-cooked dishes (biryani, karahi, daal, etc.) vary widely with recipe and oil used. The Pakistan table exists only on paper, so values for those dishes are estimates and are labelled as such.',
    ),
    _Source(
      'Allergen detection',
      'Your allergies are matched against the ingredient text using a synonym list (for example "whey" and "casein" for dairy), tolerance for scanning errors, and a separate warning for "may contain" statements. '
          'The allergen groups follow the major food allergens in the Codex labelling standard.',
      [
        'Codex Alimentarius. General Standard for the Labelling of Prepackaged Foods (CXS 1-1985), foods and ingredients known to cause hypersensitivity.',
        'Google Cloud Vision API (text recognition used to read label photos).',
      ],
      caveat: 'Text recognition can misread a label and the synonym list cannot cover every ingredient name. Always read the printed label if your allergy is serious.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sources & methodology')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Baymax is a decision-support tool, not a medical device. It does not diagnose or treat any condition, and it does not replace advice from a doctor, dietitian or qualified trainer.',
              style: TextStyle(color: AppTheme.warning, height: 1.4, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          for (final s in _sources) _card(s),
        ],
      ),
    );
  }

  Widget _card(_Source s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.topic, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(s.howWeUseIt, style: const TextStyle(color: AppTheme.textPrimary, height: 1.4, fontSize: 13)),
          const SizedBox(height: 10),
          const Text('REFERENCES', style: TextStyle(fontSize: 10, letterSpacing: 1, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          for (final r in s.references)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $r', style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 12)),
            ),
          if (s.caveat != null) ...[
            const SizedBox(height: 10),
            Text('Limits: ${s.caveat}', style: const TextStyle(color: AppTheme.warning, height: 1.4, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

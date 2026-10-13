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
          'The library has 73 bodyweight exercises: 32 written by the team (15 of them matched to the free-exercise-db open dataset for muscles) and 41 curated from that dataset. '
          'For the curated ones only the exercise, its muscles and its difficulty come from the dataset; the technique cues are written by the team, because several of the dataset\'s own instructions assume gym equipment or maximal effort. '
          'Of 188 no-equipment entries reviewed, those needing a bar, bench, machine or partner, expert-level moves and athletic drills were left out.',
      [
        'free-exercise-db — open public-domain (Unlicense) exercise dataset, github.com/yuhonas/free-exercise-db.',
        'Herrmann SD, et al. 2024 Adult Compendium of Physical Activities. J Sport Health Sci 2024; 13(1): 6–12 (energy values).',
      ],
      caveat: 'free-exercise-db is community-maintained and not clinically reviewed. The curated exercises have no exact Compendium entry of their own: each uses the energy value of the closest movement class already used in the library (marked *). '
          'The body-load fields (which joints a move stresses, whether you need to get down to the floor, how much coordination it needs) are assigned by the team. '
          'All team-written cues and these fields should be reviewed by a qualified trainer or physiotherapist before release.',
    ),
    _Source(
      'How exercises are chosen for you',
      'First the safety rules remove every exercise that is not allowed for you (your conditions, BMI and age). Then the remaining exercises for each part of the session are ranked using your answers: '
          'your fitness capacity (from your activity level, lowered a little for age 50+ and for BMI 30+) against each exercise\'s difficulty; your goal (weight loss favours higher energy use, muscle gain favours strength moves); '
          'which joints the movement loads against your BMI and age; whether the exercise needs you to get down to the floor (age 65+ or BMI 35+); coordination demand (age 60+); and variety across the week. '
          'Your height and weight also set your calorie estimates, and your gender only affects the energy calculation, not which exercises you get. After training, the cool-down picks static stretches for the body regions you worked. Each choice shows the reason.',
      [
        'WHO. Guidelines on physical activity and sedentary behaviour. Geneva, 2020 (balance training for adults 65+).',
        'Project team design: the ranking weights, the capacity scale and the joint-load values are not from a published formula.',
      ],
      caveat: 'The safety rules always come first; the ranking only orders what is already allowed. The weights are team choices and have not been validated against outcomes or reviewed by a trainer. '
          'The profile does not ask about injuries or joint pain, so the app cannot adjust for them: stop any exercise that hurts, and see a professional for a problem.',
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
      'Food photo recognition (machine learning)',
      'An EfficientNetV2-B0 image classifier, fine-tuned from ImageNet weights and running on your phone, suggests up to three catalogue foods for a photo. You always confirm the food and the portion; nothing is logged automatically. '
          'It knows 22 foods: 13 from Food-101 (samosa also has Kaggle photos) and 9 South-Asian dishes (aloo gobi, bhindi, butter chicken, chicken biryani, chicken tikka, haleem, paratha, roti, chai) from a Kaggle "Pakistani Dishes" dataset.',
      [
        'Bossard L, Guillaumin M, Van Gool L. Food-101 — mining discriminative components with random forests. ECCV 2014.',
        'Kaggle "Pakistani Dishes Dataset" (useractivated/dataset). Web-collected images; licence not verified by the team.',
        'Tan M, Le QV. EfficientNetV2: smaller models and faster training. ICML 2021.',
      ],
      caveat: 'On held-out test photos it picked the right food about 93% of the time overall, but only about 85% and 76% on the test photos from the two Kaggle sets, which come from the same web collections as their training photos; '
          'phone photos will be harder. Aloo gobi and paratha were right only about 65% of the time, below the team\'s 70% bar, so the model has NOT passed the team\'s release gate: it is available in test builds only, and release builds ask you to pick the food. '
          'Photos are processed on the device. The model recognises the dish, not the portion size.',
    ),
    _Source(
      'Personalised calorie target',
      'Your starting estimate is the Mifflin–St Jeor formula times your activity factor. Once you have logged your weight at least 4 times over 14 or more days and fully logged your food on at least 10 of those days, the app also works out what your own data implies: '
          'average calories eaten minus the daily weight change (from a straight line fitted to your weigh-ins) times about 7,700 kcal per kg. The two estimates are combined in proportion to how reliable each is (a Bayesian update), '
          'so noisy weights count for less. The result may raise the formula estimate by at most 15% and lower it by at most 10%, never gives the data more than 70% of the say, is ignored if it is more than 30% away from the formula, and is switched off for under-18s and for anyone who reported heart disease or diabetes. '
          'The usual minimum intake (1,200 kcal women, 1,500 kcal men) and the no-deficit rule for underweight still apply.',
      [
        'Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 1990; 51(2): 241–247.',
        'Wishnofsky M. Caloric equivalents of gained or lost weight. Am J Clin Nutr 1958; 6(5): 542–546 (the 3,500 kcal per pound rule of thumb).',
        'Hall KD, Sacks G, Chandramohan D, et al. Quantification of the effect of energy imbalance on bodyweight. Lancet 2011; 378: 826–837 (why the rule of thumb is only approximate).',
      ],
      caveat: 'The 7,700 kcal per kg figure is an approximation; real energy changes depend on what is gained or lost and shift over time. The assumed 10% uncertainty of the formula and of calorie logging, the 28-day window, the 60%-of-BMR "fully logged day" rule and the safety limits are choices made by the project team, not published values. '
          'Under-logging food makes your needs look lower than they are; the limits above are there to contain that. This is NOT the Gradient Boosting model named in the project scope: that needs measured daily-energy data (the IAEA doubly-labelled-water database is released on request), which the team does not have yet.',
    ),
    _Source(
      'Fitness score, levels, badges and leaderboard',
      'Your weekly fitness score (0–100) is 50% workouts you marked completed out of the planned workout days so far this week, 25% days on which you logged food, and 25% of your logged days that landed within 15% of your calorie target. '
          'Your level is the average of your recent weekly scores: Beginner below 40, Intermediate 40–69, Advanced 70 and above. Badges follow fixed rules over your last four weeks of logs. '
          'The weekly leaderboard is opt-in. With at least 15 participants the app groups them as beginner, intermediate or advanced with K-Means clustering (3 groups, using score, workouts and logging days); with fewer people it uses the score thresholds above and says so.',
      [
        'Project team design: no published standard defines these weights, tolerances or thresholds, and they are not clinically validated.',
        'Lloyd SP. Least squares quantization in PCM. IEEE Transactions on Information Theory 1982; 28(2): 129–137 (the K-Means algorithm).',
        'Arthur D, Vassilvitskii S. k-means++: the advantages of careful seeding. Proceedings of SODA 2007: 1027–1035 (cluster seeding).',
      ],
      caveat: 'Only workouts you tick off and meals you log are counted; there is no link to a fitness tracker. A day with only some meals logged will usually miss the calorie window. '
          'Scores are calculated on each phone, so a modified app could submit a false score: the ranking is for motivation, not a verified result.',
    ),
    _Source(
      'Reminders and inactivity alerts',
      'If you turn them on, the app schedules a reminder on your phone at your chosen time on each planned workout day. You are treated as inactive when at least 3 days have passed since your last workout and at least one planned workout day has gone by without one; '
          'rest days alone never count. The alert is a single notification, and notifications never show health details on the lock screen.',
      [
        'Project team design (3-day threshold and wording).',
      ],
      caveat: 'Reminders are scheduled on the phone, so they need no internet, but Android may delay them to save battery. Push notifications sent from a server are not part of this version.',
    ),
    _Source(
      'Accounts and roles',
      'Every account is a standard member who can see and change only their own data. Doctor, nutritionist, trainer and administrator roles exist in the app, but a role can only be set by an administrator in the Firebase console, never from the app.',
      [
        'Project team design (role list from the project scope, Module 14).',
      ],
      caveat: 'Today the security rules give nobody access to another person\'s data: assigning patients to clinicians belongs to the consultation module, which is not built yet. '
          'The app does not add its own AES encryption layer on top of the database; that part of the scope is not implemented in this version.',
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

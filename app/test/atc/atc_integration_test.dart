// Automated INTEGRATION test cases (report section 5.4). Each case chains several modules the way the app does and checks the final result.
// IDs: ATC-INT-<nn>. Run: flutter test test/atc/atc_integration_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart' hide same;
import 'package:app/models/consultation.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/payment.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/specialist_plan.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/diet_summary.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/food_parser.dart';
import 'package:app/services/gamification.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/inbox_service.dart';
import 'package:app/services/ml/health_risk_model.dart';
import 'package:app/services/payment_gateway.dart';
import 'package:app/services/payment_rules.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/specialist_plan_apply.dart';
import 'package:app/services/user_settings_service.dart';
import 'package:app/models/app_notification.dart';
import 'atc_helper.dart';

HealthProfile _p({String gender = 'Female', double weight = 72, int age = 28, List<String> conditions = const [], List<String> allergies = const [], String goal = 'Lose Weight', int freq = 4}) => HealthProfile(
    fullName: 'Test User', dob: '${DateTime.now().year - age}-01-01', gender: gender, heightValue: 165, weightValue: weight, medicalConditions: conditions,
    foodAllergies: allergies, primaryGoal: goal, activityLevel: 'Lightly Active', workoutFrequency: freq);

void main() {
  late FoodDatabase db;
  late HybridHealthClassifier hybrid;

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
    hybrid = HybridHealthClassifier(const RuleBasedClassifier(), HealthRiskModel.fromJsonString(File('assets/models/health_classifier.json').readAsStringSync()));
  });

  atc('ATC-INT-01', req: 'M2-FR10, M4-FR1, M9-FR6', objective: 'A diabetic user with a dairy allergy gets a safe plan from profile to meals', input: 'Female, 165 cm, 72 kg, Diabetes, Dairy allergy, goal Lose Weight',
      expected: 'Category Diabetic; meals have no dairy, no high-sugar or refined food; macros agree with the calorie target', run: () {
        final p = _p(conditions: ['Diabetes'], allergies: ['Dairy']);
        final cls = hybrid.classify(p);
        final plan = PlanGenerator(db).generate(p, cls);
        final items = plan.nutrition.meals.values.expand((l) => l);
        final dairy = items.where((i) => i.food.conflictsWith(p.allergies).isNotEmpty).length;
        final sugar = items.where((i) => i.food.tags.contains('highSugar') || i.food.tags.contains('refined')).length;
        final n = plan.nutrition;
        final macroKcal = n.proteinG * 4 + n.carbsG * 4 + n.fatG * 9;
        return check(cls.category == 'Diabetic' && dairy == 0 && sugar == 0 && items.isNotEmpty && (macroKcal - n.targetKcal).abs() < 40,
            'Category ${cls.category}; ${items.length} meal items; dairy items $dairy; high-sugar or refined items $sugar; macros give $macroKcal kcal against a target of ${n.targetKcal}');
      });

  atc('ATC-INT-02', req: 'M2-FR10, M4-FR3, M9-FR1', objective: 'A cardiac user gets a low-intensity plan and a calorie target above the safe floor', input: 'Male, 165 cm, 100 kg, Heart Disease, goal Lose Weight, asks for 6 days',
      expected: 'Category Cardiac; intensity Low; at most 4 workout days; no HIIT; target not below 1500 kcal for a man', run: () {
        final p = _p(gender: 'Male', weight: 100, conditions: ['Heart Disease'], freq: 6);
        final cls = hybrid.classify(p);
        final plan = PlanGenerator(db).generate(p, cls);
        final hiit = plan.week.whereType<WorkoutDay>().expand((d) => d.exercises).where((e) => e.exercise.tags.contains('hiit')).length;
        return check(cls.category == 'Cardiac' && plan.intensity == 'Low' && plan.workoutDays <= 4 && hiit == 0 && plan.nutrition.targetKcal >= 1500,
            'Category ${cls.category}; intensity ${plan.intensity}; ${plan.workoutDays} workout days; $hiit HIIT exercises; target ${plan.nutrition.targetKcal} kcal');
      });

  atc('ATC-INT-03', req: 'M8-FR8, M8-FR13', objective: 'Typed meals become a daily summary with the correct totals and a fair verdict', input: 'Breakfast "2 rotis", Lunch "a bowl of daal"; burned 150 kcal; goal Lose Weight; target 1800; BMR 1400',
      expected: 'Consumed 450, net 300, verdict not claiming a surplus', run: () {
        final parser = FoodParser(db);
        FoodEntry entry(String meal, ParsedFood f) => FoodEntry(date: '2026-10-15', meal: meal, name: f.item!.name, quantity: f.servings, unit: 'serving', kcal: f.kcal, protein: f.protein, carbs: f.carbs, fat: f.fat);
        final entries = [entry('Breakfast', parser.parse('2 rotis').single), entry('Lunch', parser.parse('a bowl of daal').single)];
        final by = kcalByMeal(entries);
        final consumed = by.values.fold(0.0, (a, b) => a + b);
        final net = netKcal(consumed: consumed, burned: 150);
        final verdict = dailyVerdict(goal: 'Lose Weight', consumed: consumed, target: 1800, bmr: 1400);
        return check((consumed - 450).abs() < 1 && (net - 300).abs() < 1 && !verdict.contains('surplus'), 'Consumed ${consumed.round()} kcal (Breakfast ${by['Breakfast']!.round()}, Lunch ${by['Lunch']!.round()}); net ${net.round()}; verdict: "$verdict"');
      });

  atc('ATC-INT-04', req: 'M12-FR6, M12-FR8, M16-FR5', objective: 'A week of activity earns a badge and raises no inactivity alert; a long gap raises one', input: '7 consecutive active days; then no activity for 6 days with a plan for Mon/Wed/Fri',
      expected: '7-day streak badge earned and no "We miss you" notice; with the gap, a "We miss you" notice', run: () {
        final today = DateTime(2026, 10, 15);
        String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final active = {for (var i = 0; i < 7; i++) key(today.subtract(Duration(days: i))): ActivityEntry(key(today.subtract(Duration(days: i))), 30, 200)};
        final busy = ProgressSnapshot.build(today: today, plannedWeekdays: {1, 3, 5}, targetKcal: 2000, activity: active, kcalByDate: const {});
        const s = UserSettings(inactivityAlerts: true);
        final noAlert = !InboxService.dueItems(now: today.add(const Duration(hours: 12)), progress: busy, settings: s).any((n) => n.type == NotificationType.inactivity);
        final lastWorkout = {key(today.subtract(const Duration(days: 6))): ActivityEntry(key(today.subtract(const Duration(days: 6))), 30, 200)};
        final idle = ProgressSnapshot.build(today: today, plannedWeekdays: {1, 3, 5}, targetKcal: 2000, activity: lastWorkout, kcalByDate: const {});
        final alert = InboxService.dueItems(now: today.add(const Duration(hours: 12)), progress: idle, settings: s).any((n) => n.type == NotificationType.inactivity);
        return check(busy.earnedNow.contains('daily_7') && busy.activeStreak >= 7 && noAlert && alert, 'Busy week: streak ${busy.activeStreak}, badge daily_7 ${busy.earnedNow.contains('daily_7')}, inactivity alert raised ${!noAlert}; idle week: alert raised $alert');
      });

  atc('ATC-INT-05', req: 'M14-FR2, M15-FR5', objective: 'A booking is checked, paid through the test gateway and becomes a cancellable request without a video link', input: 'Valid slot on Monday 10:00, video, PKR 2,000 + PKR 150 platform fee, card 4242 4242 4242 4242',
      expected: 'No booking problem; total PKR 2,150; payment succeeds with a reference; request is upcoming, cancellable, and cannot be joined yet', run: () async {
        final now = DateTime.utc(2026, 10, 19, 3);
        final s = Specialist(id: 's', name: 'Sara Khan', type: SpecialistType.nutritionist, specialty: 'Weight', rating: 4.8, reviewCount: 40, videoFee: 2000, chatFee: 1200);
        final slot = DateTime.utc(2026, 10, 19, 5);
        final problem = ConsultationRules.bookingProblem(specialist: s, slot: slot, notes: '', now: now);
        const order = OrderSummary(consultationFee: 2000, platformFee: 150);
        const card = CardInput(number: '4242 4242 4242 4242', expiry: '12/30', cvv: '123', holder: 'Ayesha Khan');
        final canPay = PaymentRules.canPay(method: PaymentMethod.card, now: now, order: order, card: card);
        final r = await SandboxGateway(delay: Duration.zero).charge(const PaymentRequest(amount: 2150, method: PaymentMethod.card, card: card));
        final a = Appointment(id: 'a', patientId: 'p', patientName: 'P', specialistId: 's', specialistName: 'Sara Khan', role: SpecialistType.nutritionist, startAt: slot, durationMinutes: 30,
            type: ConsultType.video, status: AppointmentStatus.requested, fee: 2000, meetingLink: '', createdAt: now);
        return check(problem == null && canPay && order.total == 2150 && r.success && (r.reference ?? '').isNotEmpty && ConsultationRules.isUpcoming(a, now) && ConsultationRules.canCancel(a, now) && !ConsultationRules.canJoin(a, slot),
            'Booking problem: ${problem ?? 'none'}; Pay enabled $canPay; total PKR ${order.total}; payment ${r.success ? 'succeeded' : 'failed'} (reference ${r.reference}); upcoming ${ConsultationRules.isUpcoming(a, now)}; cancellable ${ConsultationRules.canCancel(a, now)}; joinable at the start ${ConsultationRules.canJoin(a, slot)}');
      });

  atc('ATC-INT-06', req: 'M14-FR5, M9-FR6', objective: 'A specialist\'s diet plan changes the calorie target but never puts an allergen back into the meals', input: 'Baymax plan for a user allergic to Dairy and Nuts; nutritionist sets 1800 kcal',
      expected: 'Target 1800 kcal; meals identical to Baymax\'s; still no allergen', run: () {
        final p = _p(allergies: ['Dairy', 'Nuts']);
        final base = PlanGenerator(db).generate(p, hybrid.classify(p));
        final diet = SpecialistDietPlan(approvedAsIs: false, note: 'x', targetKcal: 1800, proteinG: 120, carbsG: 200, fatG: 55, by: const PlanAuthor('Sara Khan', 'nutritionist'), at: DateTime(2026, 10, 19));
        final warm = ExerciseLibrary.byId('warmup')!, cool = ExerciseLibrary.byId('cooldown')!;
        final out = applySpecialistPlans(base, SpecialistPlans(diet: diet), PlanChoices.defaults, exercise: ExerciseLibrary.byId, warmUp: warm, coolDown: cool);
        final items = out.nutrition.meals.values.expand((l) => l);
        final conflicts = items.where((i) => i.food.conflictsWith(p.allergies).isNotEmpty).length;
        return check(out.nutrition.targetKcal == 1800 && out.nutrition.meals == base.nutrition.meals && conflicts == 0 && items.isNotEmpty, 'Target ${out.nutrition.targetKcal} kcal; meals unchanged ${out.nutrition.meals == base.nutrition.meals}; allergen items $conflicts of ${items.length}');
      });

  atc('ATC-INT-07', req: 'M13-FR3', objective: 'The chatbot answers calories left from the user\'s own plan and food log', input: 'Plan target for a Lose Weight user; 600 kcal logged; "how many calories left"',
      expected: 'The answer contains target minus 600', run: () {
        final p = _p();
        final cls = hybrid.classify(p);
        final plan = PlanGenerator(db).generate(p, cls);
        final ctx = ChatContext(profile: p, classification: cls, plan: plan, db: db, consumedKcal: 600, now: DateTime(2026, 10, 12, 13));
        final r = const ChatbotEngine().respond('how many calories left', ctx);
        final left = plan.nutrition.targetKcal - 600;
        return check(r.text.contains('$left'), 'Target ${plan.nutrition.targetKcal} kcal; expected "$left" in the answer; answer starts: "${r.text.split('\n').first}"');
      });
}

// Automated BUSINESS-RULE test cases (report section 5.3). Every table below is a decision table: the conditions are the columns of
// the report's table, one case per rule (column). IDs: ATC-M<module>-B<nn>. Run: flutter test test/atc/atc_rules_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart' hide same;
import 'package:app/models/app_notification.dart';
import 'package:app/models/consultation.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/payment.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/specialist_plan.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/gamification.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/inbox_service.dart';
import 'package:app/services/payment_rules.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/specialist_plan_apply.dart';
import 'package:app/services/user_settings_service.dart';
import 'atc_helper.dart';

final _now = DateTime.utc(2026, 10, 19, 3, 0); // Monday 08:00 in Pakistan

HealthProfile _p({double weight = 70, List<String> conditions = const [], List<String> allergies = const []}) => HealthProfile(
    fullName: 'Test User', dob: '${DateTime.now().year - 30}-01-01', gender: 'Male', heightValue: 175, weightValue: weight, medicalConditions: conditions,
    foodAllergies: allergies, primaryGoal: 'Maintain & Stay Fit', activityLevel: 'Moderately Active', workoutFrequency: 4);

Specialist _spec({bool available = true}) => Specialist(id: 's', name: 'Sara Khan', type: SpecialistType.nutritionist, specialty: 'Weight management', rating: 4.8, reviewCount: 40, videoFee: 2000, chatFee: 1200, available: available);

Appointment _appt(AppointmentStatus status, DateTime start, {String link = 'https://meet.example/room'}) => Appointment(
    id: 'a', patientId: 'p', patientName: 'P', specialistId: 's', specialistName: 'Dr', role: SpecialistType.doctor, startAt: start, durationMinutes: 30,
    type: ConsultType.video, status: status, fee: 2000, meetingLink: link, createdAt: _now);

void main() {
  late FoodDatabase db;
  const rules = RuleBasedClassifier();

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  // ---------------------------------------------------------------- DT-1 Health category (Module 2)
  group('DT-M2-1 health category', () {
    void rule(String id, String reported, String bmiBand, double weight, List<String> conditions, String want) => atc(id,
        req: 'M2-FR10', objective: 'Health category: $reported, BMI $bmiBand', input: 'Reported "$reported"; BMI band $bmiBand (175 cm, ${weight.round()} kg)', expected: 'Category "$want"',
        table: 'DT-M2-1 Health category (reported conditions always override BMI)', conds: {'Reported condition': reported, 'BMI band': bmiBand}, actions: want,
        run: () { final c = rules.classify(_p(weight: weight, conditions: conditions)).category; return same(c, want, say: 'Category = "$c"'); });
    rule('ATC-M2-B01', 'None', 'Normal', 70, [], 'Healthy');
    rule('ATC-M2-B02', 'None', 'Overweight', 85, [], 'Overweight');
    rule('ATC-M2-B03', 'None', 'Obese', 100, [], 'Obese');
    rule('ATC-M2-B04', 'None', 'Underweight', 50, [], 'At-Risk');
    rule('ATC-M2-B05', 'Hypertension', 'Normal', 70, ['Hypertension'], 'At-Risk');
    rule('ATC-M2-B06', 'Diabetes', 'Normal', 70, ['Diabetes'], 'Diabetic');
    rule('ATC-M2-B07', 'Diabetes', 'Obese', 100, ['Diabetes'], 'Diabetic');
    rule('ATC-M2-B08', 'Heart disease', 'Normal', 70, ['Heart Disease'], 'Cardiac');
    rule('ATC-M2-B09', 'Heart disease and diabetes', 'Obese', 100, ['Heart Disease', 'Diabetes'], 'Cardiac');
  });

  // ---------------------------------------------------------------- DT-2 Allergen verdict (Module 10)
  group('DT-M10-1 allergen verdict', () {
    void rule(String id, String listed, String direct, String trace, String label, List<String> allergies, String verdict) => atc(id,
        req: 'M10-FR3', objective: 'Allergen verdict: listed $listed, in ingredients $direct, "may contain" $trace', input: 'Label "$label"; allergies: ${allergies.isEmpty ? 'none' : allergies.join(', ')}',
        expected: verdict, table: 'DT-M10-1 Allergen verdict (errs toward warning)', conds: {'Allergy listed': listed, 'Allergen in ingredients': direct, '"May contain" statement': trace}, actions: verdict,
        run: () {
          final r = AllergenMatcher.analyze(label, allergies);
          final got = r.hasDirectHit ? 'Not safe: ingredient found' : (r.traceAllergens.isNotEmpty ? 'Not safe: possible trace' : 'Safe');
          return same(got, verdict, say: 'Verdict = "$got" (safe = ${r.isSafe})');
        });
    rule('ATC-M10-B01', 'Yes', 'Yes', 'No', 'Ingredients: wheat flour, milk powder, salt', ['Dairy'], 'Not safe: ingredient found');
    rule('ATC-M10-B02', 'Yes', 'No', 'Yes', 'Ingredients: rice, salt. May contain traces of milk.', ['Dairy'], 'Not safe: possible trace');
    rule('ATC-M10-B03', 'Yes', 'No', 'No', 'Ingredients: rice, salt, water', ['Dairy'], 'Safe');
    rule('ATC-M10-B04', 'No', 'Yes', 'No', 'Ingredients: wheat flour, milk powder, salt', ['Nuts'], 'Safe');
    rule('ATC-M10-B05', 'Yes', 'Yes', 'Yes', 'Ingredients: milk powder, salt. May contain traces of milk.', ['Dairy'], 'Not safe: ingredient found');
    rule('ATC-M10-B06', 'No', 'No', 'Yes', 'Ingredients: rice, salt. May contain traces of milk.', ['Nuts'], 'Safe');
  });

  // ---------------------------------------------------------------- DT-3 Pay button (Module 15)
  group('DT-M15-1 Pay button enabled', () {
    const goodCard = CardInput(number: '4242 4242 4242 4242', expiry: '12/30', cvv: '123', holder: 'Ayesha Khan');
    const badCard = CardInput(number: '4242 4242 4242 4241', expiry: '12/30', cvv: '123', holder: 'Ayesha Khan');
    const order = OrderSummary(consultationFee: 2000);
    const fresh = SavedCard(id: 'c', token: 't', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030);
    const old = SavedCard(id: 'c', token: 't', brand: 'Visa', last4: '1111', expMonth: 1, expYear: 2024);
    void rule(String id, String method, String fields, String fee, bool want, bool Function() calc) => atc(id,
        req: 'M15-FR3', objective: 'Pay button for $method, fields $fields, fee $fee', input: 'Method $method; details $fields; consultation fee readable: $fee', expected: want ? 'Pay enabled' : 'Pay disabled',
        table: 'DT-M15-1 Pay button state', conds: {'Method': method, 'Details valid': fields, 'Fee could be read': fee}, actions: want ? 'Pay enabled' : 'Pay disabled',
        run: () { final got = calc(); return check(got == want, 'Pay ${got ? 'enabled' : 'disabled'}'); });
    rule('ATC-M15-B01', 'Card', 'Valid', 'Yes', true, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: order, card: goodCard));
    rule('ATC-M15-B02', 'Card', 'Invalid (check digit)', 'Yes', false, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: order, card: badCard));
    rule('ATC-M15-B03', 'Card', 'Valid', 'No', false, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: null, card: goodCard));
    rule('ATC-M15-B04', 'Wallet (JazzCash)', 'Valid number', 'Yes', true, () => PaymentRules.canPay(method: PaymentMethod.wallet, now: _now, order: order, wallet: WalletProvider.jazzcash, walletNumber: '0300 1234567'));
    rule('ATC-M15-B05', 'Wallet (JazzCash)', 'Invalid number', 'Yes', false, () => PaymentRules.canPay(method: PaymentMethod.wallet, now: _now, order: order, wallet: WalletProvider.jazzcash, walletNumber: '123'));
    rule('ATC-M15-B06', 'Pay at clinic', 'Not needed', 'Yes', true, () => PaymentRules.canPay(method: PaymentMethod.clinic, now: _now, order: order));
    rule('ATC-M15-B07', 'Pay at clinic', 'Not needed', 'No', false, () => PaymentRules.canPay(method: PaymentMethod.clinic, now: _now, order: null));
    rule('ATC-M15-B08', 'Saved card', 'CVV entered, not expired', 'Yes', true, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: order, savedCard: fresh, savedCardCvv: '123'));
    rule('ATC-M15-B09', 'Saved card', 'CVV missing', 'Yes', false, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: order, savedCard: fresh));
    rule('ATC-M15-B10', 'Saved card', 'Card expired', 'Yes', false, () => PaymentRules.canPay(method: PaymentMethod.card, now: _now, order: order, savedCard: old, savedCardCvv: '123'));
  });

  // ---------------------------------------------------------------- DT-4 Booking validity (Module 14)
  group('DT-M14-1 booking validity', () {
    // Monday 19 Oct 2026, 08:00 in Pakistan; slots are 30 minutes, 09:00-17:00 (04:00-12:00 UTC).
    final ok = DateTime.utc(2026, 10, 19, 5);
    void rule(String id, Map<String, String> conds, String want, Specialist s, DateTime? slot, {String notes = '', Set<int> booked = const {}}) => atc(id,
        req: 'M14-FR2', objective: 'Booking check: ${conds.entries.map((e) => '${e.key} ${e.value}').join(', ')}', input: conds.entries.map((e) => '${e.key}: ${e.value}').join('; '), expected: want,
        table: 'DT-M14-1 Can this booking go ahead?', conds: conds, actions: want,
        run: () { final p = ConsultationRules.bookingProblem(specialist: s, slot: slot, notes: notes, now: _now, booked: booked); final got = p == null ? 'Booking allowed' : 'Refused: $p'; return same(got, want, say: got); });
    const cols = ['Taking bookings', 'Time chosen', 'Time free', '15+ min ahead', 'Within working hours', 'Note 500 or less'];
    Map<String, String> c(List<String> v) => {for (var i = 0; i < cols.length; i++) cols[i]: v[i]};
    rule('ATC-M14-B01', c(['Yes', 'Yes', 'Yes', 'Yes', 'Yes', 'Yes']), 'Booking allowed', _spec(), ok);
    rule('ATC-M14-B02', c(['No', 'Yes', 'Yes', 'Yes', 'Yes', 'Yes']), 'Refused: This specialist is not taking bookings right now.', _spec(available: false), ok);
    rule('ATC-M14-B03', c(['Yes', 'No', '-', '-', '-', 'Yes']), 'Refused: Choose a date and a time.', _spec(), null);
    rule('ATC-M14-B04', c(['Yes', 'Yes', 'No', 'Yes', 'Yes', 'Yes']), 'Refused: That time was just taken. Please choose another.', _spec(), ok, booked: {ok.millisecondsSinceEpoch});
    rule('ATC-M14-B05', c(['Yes', 'Yes', 'Yes', 'No', 'Yes', 'Yes']), 'Refused: That time is too soon. Please choose a later one.', _spec(), DateTime.utc(2026, 10, 19, 3, 10));
    rule('ATC-M14-B06', c(['Yes', 'Yes', 'Yes', 'Yes', 'No', 'Yes']), "Refused: That time is outside the specialist's working hours.", _spec(), DateTime.utc(2026, 10, 19, 13));
    rule('ATC-M14-B07', c(['Yes', 'Yes', 'Yes', 'Yes', 'Yes', 'No']), 'Refused: Notes can be at most 500 characters.', _spec(), ok, notes: 'x' * 501);
  });

  // ---------------------------------------------------------------- DT-5 Join and cancel (Module 14)
  group('DT-M14-2 join and cancel windows', () {
    final start = DateTime.utc(2026, 10, 20, 5);
    void rule(String id, String status, String when, String link, AppointmentStatus st, Duration offset, bool join, bool cancel, {bool hasLink = true}) => atc(id,
        req: 'M14-FR3', objective: 'Appointment $status, $when', input: 'Status "$status"; video link: $link; time: $when', expected: 'Join ${join ? 'allowed' : 'not allowed'}; cancel ${cancel ? 'allowed' : 'not allowed'}',
        table: 'DT-M14-2 Join and cancel by status and time', conds: {'Status': status, 'Video link': link, 'Time': when}, actions: 'Join ${join ? 'yes' : 'no'}; cancel ${cancel ? 'yes' : 'no'}',
        run: () {
          final a = _appt(st, start, link: hasLink ? 'https://meet.example/room' : '');
          final now = start.add(offset);
          final j = ConsultationRules.canJoin(a, now), x = ConsultationRules.canCancel(a, now);
          return check(j == join && x == cancel, 'Join ${j ? 'allowed' : 'not allowed'}; cancel ${x ? 'allowed' : 'not allowed'}');
        });
    rule('ATC-M14-B08', 'Confirmed', '6 minutes before start', 'Yes', AppointmentStatus.confirmed, const Duration(minutes: -6), false, true);
    rule('ATC-M14-B09', 'Confirmed', '5 minutes before start', 'Yes', AppointmentStatus.confirmed, const Duration(minutes: -5), true, true);
    rule('ATC-M14-B10', 'Confirmed', '10 minutes after start', 'Yes', AppointmentStatus.confirmed, const Duration(minutes: 10), true, false);
    rule('ATC-M14-B11', 'Confirmed', 'after the slot ended', 'Yes', AppointmentStatus.confirmed, const Duration(minutes: 31), false, false);
    rule('ATC-M14-B12', 'Requested', '30 minutes before start', 'No', AppointmentStatus.requested, const Duration(minutes: -30), false, true, hasLink: false);
    rule('ATC-M14-B13', 'Requested', 'at the start time', 'No', AppointmentStatus.requested, Duration.zero, false, false, hasLink: false);
    rule('ATC-M14-B14', 'Declined', '30 minutes before start', 'No', AppointmentStatus.declined, const Duration(minutes: -30), false, false, hasLink: false);
    rule('ATC-M14-B15', 'Completed', '1 hour after start', 'Yes', AppointmentStatus.completed, const Duration(hours: 1), false, false);
  });

  // ---------------------------------------------------------------- DT-6 Whose plan applies (Module 14)
  group('DT-M14-3 whose diet plan applies', () {
    Exercise ex(String id, {String group = 'legs', bool timed = false}) => Exercise(id: id, name: id, icon: '', group: group, muscles: const [], impact: 'low', level: 1, met: 4, steps: const [], timed: timed, baseReps: 12, baseSeconds: 30);
    final lib = {for (final e in [ex('warmup', group: 'mobility', timed: true), ex('cooldown', group: 'mobility', timed: true), ex('squat')]) e.id: e};
    PersonalizedPlan base() => PersonalizedPlan(category: 'Normal', intensity: 'Moderate', variant: 0, week: [WorkoutDay(name: 'Baymax day', focus: 'Full body', exercises: [PlannedExercise(exercise: lib['squat']!, sets: 3, reps: 10, seconds: 0, restSeconds: 45)]), null, null, null, null, null, null],
        restrictionNotes: const [], nutrition: const NutritionPlan(goalLabel: 'Lose weight', targetKcal: 2000, proteinG: 110, carbsG: 230, fatG: 65, waterLitres: 2.5, meals: {}, avoid: ['Sugary drinks'], tips: ['Walk after meals']));
    SpecialistDietPlan diet({required bool asIs}) => SpecialistDietPlan(approvedAsIs: asIs, note: 'x', targetKcal: asIs ? null : 1800, proteinG: asIs ? null : 120, carbsG: asIs ? null : 200, fatG: asIs ? null : 55, by: const PlanAuthor('Sara Khan', 'nutritionist'), at: DateTime(2026, 10, 19));
    void rule(String id, String plan, String choice, int want, SpecialistPlans plans, PlanChoices choices) => atc(id,
        req: 'M14-FR5', objective: 'Diet plan: specialist plan $plan, member chose $choice', input: 'Baymax target 2000 kcal; specialist plan: $plan; member chose: $choice', expected: 'Daily target $want kcal',
        table: 'DT-M14-3 Whose diet plan applies', conds: {'Specialist plan': plan, "Member's choice": choice}, actions: 'Target $want kcal',
        run: () { final n = applySpecialistPlans(base(), plans, choices, exercise: (i) => lib[i], warmUp: lib['warmup']!, coolDown: lib['cooldown']!).nutrition; return same(n.targetKcal, want, say: 'Daily target ${n.targetKcal} kcal'); });
    rule('ATC-M14-B16', 'None', 'Specialist', 2000, const SpecialistPlans(), PlanChoices.defaults);
    rule('ATC-M14-B17', 'None', 'Baymax', 2000, const SpecialistPlans(), const PlanChoices(specialistDiet: false));
    rule('ATC-M14-B18', 'Approved as is', 'Specialist', 2000, SpecialistPlans(diet: diet(asIs: true)), PlanChoices.defaults);
    rule('ATC-M14-B19', 'Changed (1800 kcal)', 'Specialist', 1800, SpecialistPlans(diet: diet(asIs: false)), PlanChoices.defaults);
    rule('ATC-M14-B20', 'Changed (1800 kcal)', 'Baymax', 2000, SpecialistPlans(diet: diet(asIs: false)), const PlanChoices(specialistDiet: false));
  });

  // ---------------------------------------------------------------- DT-7 Reminders (Module 16)
  group('DT-M16-1 workout and meal reminders', () {
    final today = DateTime(2026, 10, 15, 19, 0);
    ProgressSnapshot snap({required bool planned, required bool done, required bool logged}) {
      final t = Gamification.dateOnly(today);
      final days = [DayRecord(date: t, planned: planned, workoutDone: done, foodLogged: logged, kcal: logged ? 2000 : null, targetKcal: 2000)];
      return ProgressSnapshot(today: t, days: days, week: Gamification.weeklyScore(days), weeks: const [], level: FitnessLevel.beginner, workoutStreak: 0, loggingStreak: 0, activeStreak: 0,
          lastWorkout: null, inactivity: null, earnedNow: const {}, earned: const {}, newBadges: const {});
    }
    void workout(String id, String enabled, String planned, String done, String time, bool want, UserSettings s, ProgressSnapshot p) => atc(id,
        req: 'M16-FR3', objective: 'Workout reminder: switch $enabled, planned day $planned, workout done $done, time passed $time', input: 'Reminder switch $enabled; planned today: $planned; workout done: $done; 18:00 reached (now 19:00 or 17:00): $time',
        expected: want ? 'Reminder raised' : 'No reminder', table: 'DT-M16-1 Workout reminder due', conds: {'Reminder switched on': enabled, 'Planned today': planned, 'Workout done': done, 'Reminder time passed': time}, actions: want ? 'Raise reminder' : 'Nothing',
        run: () { final got = InboxService.dueItems(now: time == 'Yes' ? today : DateTime(2026, 10, 15, 17), progress: p, settings: s).any((n) => n.type == NotificationType.workoutReminder); return check(got == want, got ? 'Reminder raised' : 'No reminder'); });
    const on = UserSettings(reminderEnabled: true, reminderHour: 18);
    workout('ATC-M16-B01', 'Yes', 'Yes', 'No', 'Yes', true, on, snap(planned: true, done: false, logged: true));
    workout('ATC-M16-B02', 'No', 'Yes', 'No', 'Yes', false, const UserSettings(), snap(planned: true, done: false, logged: true));
    workout('ATC-M16-B03', 'Yes', 'No', 'No', 'Yes', false, on, snap(planned: false, done: false, logged: true));
    workout('ATC-M16-B04', 'Yes', 'Yes', 'Yes', 'Yes', false, on, snap(planned: true, done: true, logged: true));
    workout('ATC-M16-B05', 'Yes', 'Yes', 'No', 'No', false, on, snap(planned: true, done: false, logged: true));

    void meal(String id, String enabled, String logged, String time, bool want, UserSettings s, ProgressSnapshot p) => atc(id,
        req: 'M16-FR3', objective: 'Meal reminder: switch $enabled, food logged $logged, time passed $time', input: 'Meal reminder switch $enabled; food logged today: $logged; 20:00 reached (now 21:00 or 19:00): $time',
        expected: want ? 'Reminder raised' : 'No reminder', table: 'DT-M16-2 Meal log reminder due', conds: {'Reminder switched on': enabled, 'Food logged today': logged, 'Reminder time passed': time}, actions: want ? 'Raise reminder' : 'Nothing',
        run: () { final got = InboxService.dueItems(now: time == 'Yes' ? DateTime(2026, 10, 15, 21) : DateTime(2026, 10, 15, 19), progress: p, settings: s).any((n) => n.type == NotificationType.mealReminder); return check(got == want, got ? 'Reminder raised' : 'No reminder'); });
    const mealOn = UserSettings(mealReminderEnabled: true, mealReminderHour: 20);
    meal('ATC-M16-B06', 'Yes', 'No', 'Yes', true, mealOn, snap(planned: false, done: false, logged: false));
    meal('ATC-M16-B07', 'No', 'No', 'Yes', false, const UserSettings(), snap(planned: false, done: false, logged: false));
    meal('ATC-M16-B08', 'Yes', 'Yes', 'Yes', false, mealOn, snap(planned: false, done: false, logged: true));
    meal('ATC-M16-B09', 'Yes', 'No', 'No', false, mealOn, snap(planned: false, done: false, logged: false));
  });

  // ---------------------------------------------------------------- DT-8 Chatbot safety order (Module 13)
  group('DT-M13-1 chatbot answers safety first', () {
    late ChatContext ctx;
    setUp(() {
      final p = _p(allergies: ['Dairy']);
      final cls = rules.classify(p);
      ctx = ChatContext(profile: p, classification: cls, plan: PlanGenerator(db).generate(p, cls), db: db, consumedKcal: 600, now: DateTime(2026, 10, 12, 13));
    });
    void rule(String id, String says, String want, String text) => atc(id,
        req: 'M13-FR4', objective: 'Chatbot: message about $says', input: 'User types "$text"', expected: 'Intent "$want"', table: 'DT-M13-1 Which answer comes first', conds: {'Message is about': says}, actions: 'Intent $want',
        run: () { final r = const ChatbotEngine().respond(text, ctx); return same(r.intent, want, say: 'Intent = "${r.intent}"'); });
    rule('ATC-M13-B01', 'a possible emergency', 'emergency', 'I have chest pain');
    rule('ATC-M13-B02', 'an emergency and an exercise', 'emergency', 'I have chest pain after squats');
    rule('ATC-M13-B03', 'a symptom', 'health_concern', 'my knee hurts after squats');
    rule('ATC-M13-B04', 'BMI', 'bmi', 'what is my bmi');
    rule('ATC-M13-B05', 'no known topic', 'fallback', 'asdfgh qwerty');
  });
}

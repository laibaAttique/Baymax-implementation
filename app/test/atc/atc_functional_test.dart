// Automated FUNCTIONAL test cases (report section 5.2). Each case opens a real screen, does what a user would do (type, tap, scroll)
// and checks what appears. IDs: ATC-M<module>-F<nn>. Run: flutter test test/atc/atc_functional_test.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide same;
import 'package:app/models/app_notification.dart';
import 'package:app/models/consultation.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/payment.dart';
import 'package:app/screens/allergy/allergen_result_screen.dart';
import 'package:app/screens/analytics/analytics_screen.dart';
import 'package:app/screens/auth/signup_screen.dart';
import 'package:app/screens/community/my_badges_screen.dart';
import 'package:app/screens/diet/daily_summary_screen.dart';
import 'package:app/screens/diet/food_text_log.dart';
import 'package:app/screens/dashboard/home_dashboard.dart';
import 'package:app/screens/health_profiling/bmi_result.dart';
import 'package:app/services/inbox_service.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/screens/health_profiling/health_classification.dart';
import 'package:app/screens/notifications/notifications_screen.dart';
import 'package:app/screens/nutrition/nutrition_plan_screen.dart';
import 'package:app/screens/specialists/book_appointment_screen.dart';
import 'package:app/screens/specialists/my_appointments_screen.dart';
import 'package:app/screens/specialists/payment_screen.dart';
import 'package:app/screens/specialists/specialists_screen.dart';
import 'package:app/screens/workout_and_exercise/workout_plan.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/allergen_matcher.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/consultation_rules.dart';
import 'package:app/services/consultation_service.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/payment_rules.dart';
import 'package:app/services/payment_gateway.dart';
import 'package:app/services/payment_service.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/user_session.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/services/xp_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/glass.dart';
import 'atc_helper.dart';

// Monday 19 Oct 2026, 08:00 in Pakistan (UTC+5) = 03:00 UTC.
final _now = DateTime.utc(2026, 10, 19, 3, 0);
DateTime _clock() => _now;

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 9000); // tall, so long lists are built in full
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: screen));
  await tester.pumpAndSettle();
}

HealthProfile _profile({List<String> conditions = const [], List<String> allergies = const ['Dairy', 'Nuts']}) => HealthProfile(
    fullName: 'Aamna Khan', dob: '2000-03-15', gender: 'Female', heightValue: 165, weightValue: 72, medicalConditions: conditions,
    foodAllergies: allergies, primaryGoal: 'Lose Weight', activityLevel: 'Lightly Active', workoutFrequency: 4);

Specialist _spec(String id, String name, {SpecialistType type = SpecialistType.nutritionist, String specialty = 'Weight management', double rating = 4.8, int reviews = 40, bool available = true, bool emergency = false}) =>
    Specialist(id: id, name: name, type: type, specialty: specialty, rating: rating, reviewCount: reviews, videoFee: 2000, chatFee: 1200, available: available, emergency: emergency);

Appointment _appt(String id, {DateTime? start, AppointmentStatus status = AppointmentStatus.confirmed, ConsultationNote? note, DateTime? holdUntil, PaymentRecord? payment}) => Appointment(
    id: id, patientId: 'p1', patientName: 'Ayesha', specialistId: 's1', specialistName: 'Dr. Hina Malik', role: SpecialistType.doctor, specialty: 'General medicine',
    startAt: start ?? _now.add(const Duration(days: 1)), durationMinutes: 30, type: ConsultType.video, status: status, fee: 2000, meetingLink: 'https://meet.example/baymax-abc',
    createdAt: _now, consultation: note, holdUntil: holdUntil, payment: payment);

Appointment _held() => _appt('held', status: AppointmentStatus.pendingPayment, holdUntil: _now.add(const Duration(minutes: 10)));
const _testHooks = PaymentHooks(testMode: true);

AppNotification _n(String id, NotificationType t, String title, {bool read = false}) =>
    AppNotification(id: id, type: t, title: title, body: 'body of $title', createdAt: DateTime.now().subtract(const Duration(hours: 1)), read: read, route: 'workout');

void main() {
  tearDown(() => UserSession.instance.clear());

  // ------------------------------------------------------------ Module 1
  group('Module 1 sign-up screen', () {
    GlowButton button(WidgetTester t) => t.widget<GlowButton>(find.widgetWithText(GlowButton, 'Create account'));
    Future<void> type(WidgetTester t, String label, String text) async {
      final f = find.widgetWithText(TextField, label);
      await t.ensureVisible(f);
      await t.enterText(f, text);
      await t.pump();
    }

    atcWidget('ATC-M1-F01', req: 'M1-FR4', objective: 'Create account is disabled on an empty form', input: 'Open the sign-up screen and type nothing',
        expected: 'The Create account button is disabled', run: (t) async {
          await _pump(t, const SignupScreen());
          return check(button(t).onPressed == null, 'Button enabled = ${button(t).onPressed != null}');
        });
    atcWidget('ATC-M1-F02', req: 'M1-FR5', objective: 'A weak password is explained and blocks sign-up', input: 'Name "Aamna Khan", email "aamna@example.com", password and confirmation "weak"',
        expected: 'Message "Use at least 8 characters." shown; button disabled', run: (t) async {
          await _pump(t, const SignupScreen());
          await type(t, 'Full name', 'Aamna Khan');
          await type(t, 'Email', 'aamna@example.com');
          await type(t, 'Password', 'weak');
          await type(t, 'Confirm password', 'weak');
          final msg = find.text('Use at least 8 characters.').evaluate().length;
          return check(msg == 1 && button(t).onPressed == null, 'Message shown = ${msg == 1}; button enabled = ${button(t).onPressed != null}');
        });
    atcWidget('ATC-M1-F03', req: 'M1-FR4', objective: 'Terms must be accepted before the account can be created', input: 'All fields valid, terms not ticked; then terms ticked',
        expected: 'Disabled before ticking, enabled after', run: (t) async {
          await _pump(t, const SignupScreen());
          await type(t, 'Full name', 'Aamna Khan');
          await type(t, 'Email', 'aamna@example.com');
          await type(t, 'Password', 'Strong1!pass');
          await type(t, 'Confirm password', 'Strong1!pass');
          final before = button(t).onPressed != null;
          await t.ensureVisible(find.byType(Checkbox));
          await t.tap(find.byType(Checkbox));
          await t.pump();
          final after = button(t).onPressed != null;
          return check(!before && after, 'Enabled before ticking = $before; after ticking = $after');
        });
    atcWidget('ATC-M1-F04', req: 'M1-FR5', objective: 'A different confirmation password disables sign-up again', input: 'Valid form, then confirmation changed to "Different1!"',
        expected: 'Message "The two passwords do not match." shown; button disabled', run: (t) async {
          await _pump(t, const SignupScreen());
          await type(t, 'Full name', 'Aamna Khan');
          await type(t, 'Email', 'aamna@example.com');
          await type(t, 'Password', 'Strong1!pass');
          await type(t, 'Confirm password', 'Strong1!pass');
          await t.ensureVisible(find.byType(Checkbox));
          await t.tap(find.byType(Checkbox));
          await t.pump();
          await type(t, 'Confirm password', 'Different1!');
          final msg = find.text('The two passwords do not match.').evaluate().length;
          return check(msg == 1 && button(t).onPressed == null, 'Message shown = ${msg == 1}; button enabled = ${button(t).onPressed != null}');
        });
  });

  // ------------------------------------------------------------ Module 2 / 4 / 9
  group('Module 2, 4 and 9 result screens', () {
    Future<void> session(WidgetTester t, HealthProfile p) => t.runAsync(() => UserSession.instance.setProfile(p));

    atcWidget('ATC-M2-F01', req: 'M2-FR2', objective: 'The BMI screen shows the computed BMI, the BMR method and the calorie deficit', input: 'Profile: female, 165 cm, 72 kg, Lose Weight',
        expected: 'BMI 26.4 and the words "Mifflin-St Jeor" and "Deficit" on screen', run: (t) async {
          final p = _profile();
          await session(t, p);
          await _pump(t, BmiResult(profile: p));
          final bmi = find.text(p.bmi.toStringAsFixed(1)).evaluate().length;
          final method = find.textContaining('Mifflin-St Jeor').evaluate().length;
          final deficit = find.text('Deficit').evaluate().length;
          return check(bmi == 1 && method == 1 && deficit == 1 && t.takeException() == null, 'BMI ${p.bmi.toStringAsFixed(1)} shown = ${bmi == 1}; method shown = ${method == 1}; deficit shown = ${deficit == 1}');
        });
    atcWidget('ATC-M2-F02', req: 'M2-FR10', objective: 'The classification screen lists the reported condition as a risk factor', input: 'Profile with condition "Hypertension"',
        expected: '"Hypertension" and "View workout plan" on screen', run: (t) async {
          await session(t, _profile(conditions: ['Hypertension']));
          await _pump(t, const HealthClassification());
          final hyper = find.textContaining('Hypertension').evaluate().length;
          final next = find.text('View workout plan').evaluate().length;
          return check(hyper > 0 && next == 1 && t.takeException() == null, '"Hypertension" appears $hyper time(s); "View workout plan" button shown = ${next == 1}');
        });
    atcWidget('ATC-M4-F01', req: 'M4-FR5', objective: 'A cardiac workout plan shows the category, warm-up, and a rest day when a day is tapped', input: 'Profile with "Heart Disease"; tap Sunday',
        expected: 'Title, "Cardiac", "Dynamic Warm-Up"; Sunday says rest day', run: (t) async {
          // Module 4 screening: a heart condition needs the readiness answers with a doctor's clearance first
          // (blocked case: ATC-M4-F02 and test/screens_test.dart).
          UserSession.instance.readiness = const WorkoutReadiness(clearance: true);
          await session(t, _profile(conditions: ['Heart Disease']));
          await _pump(t, const WorkoutPlan());
          final head = find.text('Your workout plan').evaluate().length;
          final cat = find.text('Cardiac').evaluate().length;
          final warm = find.text('Dynamic Warm-Up').evaluate().length;
          await t.tap(find.text('S').last);
          await t.pumpAndSettle();
          final rest = find.textContaining('rest day').evaluate().length;
          return check(head == 1 && cat == 1 && warm > 0 && rest == 1, 'Title $head, category label $cat, warm-up $warm, rest-day text $rest');
        });
    atcWidget('ATC-M4-F02', req: 'M4-FR1', objective: 'A heart condition without clearance from a doctor gets no automatic plan, and the reason is shown', input: 'Profile with "Heart Disease"; readiness: clearance "No"',
        expected: 'The clearance message, no warm-up listed', run: (t) async {
          UserSession.instance.readiness = const WorkoutReadiness(clearance: false);
          await session(t, _profile(conditions: ['Heart Disease']));
          await _pump(t, const WorkoutPlan());
          final gate = find.textContaining('clearance comes first').evaluate().length;
          final warm = find.text('Dynamic Warm-Up').evaluate().length;
          return check(gate == 1 && warm == 0, 'Clearance message $gate, warm-up items $warm');
        });
    atcWidget('ATC-M9-F01', req: 'M9-FR6', objective: 'The nutrition plan shows the calorie target and lists the user\'s allergen foods under "avoid"', input: 'Profile with Dairy and Nuts allergies',
        expected: 'The target number and "Dairy products" on screen', run: (t) async {
          await session(t, _profile());
          await _pump(t, const NutritionPlanScreen());
          final target = UserSession.instance.plan!.nutrition.targetKcal;
          final a = find.text('$target').evaluate().length;
          final b = find.text('Dairy products').evaluate().length;
          return check(a == 1 && b == 1 && t.takeException() == null, 'Target $target kcal shown = ${a == 1}; "Dairy products" under avoid = ${b == 1}');
        });
  });


  // ------------------------------------------------------------ Module 3
  group('Module 3 home dashboard', () {
    setUpAll(() => ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync()));
    Future<int Function()> openHome(WidgetTester t, {bool profile = true}) async {
      if (profile) await t.runAsync(() => UserSession.instance.setProfile(_profile()));
      var tab = -1;
      await _pump(t, HomeDashboard(onNavigateTab: (i) => tab = i));
      return () => tab;
    }
    List<String> texts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((x) => x.data).whereType<String>().toList();
    String greetingNow() { final h = DateTime.now().hour; return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening'); }
    String motivationNow() { final h = DateTime.now().hour; return h < 12 ? 'A good start to the day makes the rest easier.' : (h < 17 ? 'Keep the momentum going. Small steps add up.' : 'Finish strong. Log your meals and wind down well.'); }

    atcWidget('ATC-M3-F01', req: 'M3-FR1', objective: 'The greeting names the user and follows the time of day', input: 'Open Home for "Aamna Khan"; the clock decides morning, afternoon or evening',
        expected: 'The greeting for the current hour, the first name "Aamna" and the matching motivational line', run: (t) async {
          await openHome(t);
          final x = texts(t);
          return check(x.contains(greetingNow()) && x.contains('Aamna') && x.contains(motivationNow()), 'Greeting "${greetingNow()}" shown ${x.contains(greetingNow())}; first name shown ${x.contains('Aamna')}; motivational line shown ${x.contains(motivationNow())}');
        });
    atcWidget('ATC-M3-F02', req: 'M3-FR1', objective: 'With no profile Home says "Welcome back" and asks for the health profile instead of inventing a plan', input: 'Open Home with no profile loaded',
        expected: '"Welcome back", "No plan yet" and "Complete your health profile"', run: (t) async {
          await openHome(t, profile: false);
          final x = texts(t);
          return check(x.contains('Welcome back') && x.contains('No plan yet') && x.contains('Complete your health profile'), 'Welcome back ${x.contains('Welcome back')}; "No plan yet" ${x.contains('No plan yet')}; prompt ${x.contains('Complete your health profile')}');
        });
    atcWidget('ATC-M3-F03', req: 'M3-FR2', objective: 'The activity cards show calories burned, active minutes and an honest steps card', input: 'Open Home with no workout done today',
        expected: '"Calories burned" and "Active minutes" with 0; steps card says "Steps (no sensor)" with a dash, not a made-up number', run: (t) async {
          await openHome(t);
          final x = texts(t);
          return check(x.contains('Calories burned') && x.contains('Active minutes') && x.where((s) => s == '0').length >= 2 && x.contains('Steps (no sensor)') && x.contains('—'),
              'Calories burned ${x.contains('Calories burned')}; Active minutes ${x.contains('Active minutes')}; zeros shown ${x.where((s) => s == '0').length}; steps card "${x.contains('Steps (no sensor)') ? 'Steps (no sensor)' : 'missing'}" with dash ${x.contains('—')}');
        });
    atcWidget('ATC-M3-F04', req: 'M3-FR3', objective: 'The workout card shows today\'s session from the user\'s plan and Open goes to the Workout tab', input: 'Open Home with a generated plan and tap Open',
        expected: 'Today\'s workout name with minutes and kcal, or "Rest day"; Open selects tab 2', run: (t) async {
          final tab = await openHome(t);
          final plan = UserSession.instance.plan!;
          final today = plan.workoutFor(DateTime.now());
          final x = texts(t);
          final shown = today == null ? x.contains('Rest day') : (x.contains(today.name) && x.any((s) => s.contains('${today.durationMin} min') && s.contains('${today.kcal(UserSession.instance.profile!.weightKg)} kcal')));
          await t.tap(find.text('Open'));
          await t.pump();
          return check(x.contains("TODAY'S WORKOUT") && shown && tab() == 2, 'Card shown ${x.contains("TODAY'S WORKOUT")}; today is ${today == null ? 'a rest day' : '"${today.name}"'}, shown correctly $shown; tapping Open selected tab ${tab()}');
        });
    atcWidget('ATC-M3-F05', req: 'M3-FR4', objective: 'The mood selector shows the chosen mood with a gentle suggestion, and tapping it again clears it', input: 'Tap "Sad", then tap "Sad" again',
        expected: 'Label "Sad" and the suggestion appear; both disappear after the second tap', run: (t) async {
          await openHome(t);
          final prompt = find.text('How are you feeling today?').evaluate().length;
          await t.tap(find.byIcon(Icons.sentiment_dissatisfied_rounded));
          await t.pumpAndSettle();
          final on = find.text('Sad').evaluate().length, hint = find.textContaining('Be kind to yourself').evaluate().length;
          await t.tap(find.byIcon(Icons.sentiment_dissatisfied_rounded));
          await t.pumpAndSettle();
          final off = find.text('Sad').evaluate().length + find.textContaining('Be kind to yourself').evaluate().length;
          return check(prompt == 1 && on == 1 && hint == 1 && off == 0, 'Prompt shown ${prompt == 1}; after the first tap label $on, suggestion $hint; after the second tap $off left');
        });
    atcWidget('ATC-M3-F06', req: 'M3-FR5', objective: 'Quick Access lists the eight areas the report names', input: 'Open Home and read the Quick access grid',
        expected: 'Workout plan, Diet tracker, Posture check, Body transform, Leaderboard, Allergy scanner, AI chatbot, Find a specialist', run: (t) async {
          await openHome(t);
          final want = ['Workout\nplan', 'Diet\ntracker', 'Posture\ncheck', 'Body\ntransform', 'Leader-\nboard', 'Allergy\nscanner', 'AI\nchatbot', 'Find a\nspecialist'];
          final x = texts(t);
          final missing = want.where((w) => !x.contains(w)).map((w) => w.replaceAll('\n', ' ')).toList();
          return check(x.contains('Quick access') && missing.isEmpty, missing.isEmpty ? 'All 8 tiles shown' : 'Missing: ${missing.join(', ')}');
        });
    atcWidget('ATC-M3-F07', req: 'M3-FR5', objective: 'Quick Access tiles that belong to a tab switch to that tab', input: 'Tap the "Workout plan" tile, then the "Diet tracker" tile',
        expected: 'Tab 2 (Workout), then tab 1 (Diet)', run: (t) async {
          final tab = await openHome(t);
          await t.ensureVisible(find.text('Workout\nplan'));
          await t.tap(find.text('Workout\nplan'));
          await t.pump();
          final a = tab();
          await t.ensureVisible(find.text('Diet\ntracker'));
          await t.tap(find.text('Diet\ntracker'));
          await t.pump();
          return check(a == 2 && tab() == 1, 'Workout plan tile selected tab $a; Diet tracker tile selected tab ${tab()}');
        });
    atcWidget('ATC-M3-F08', req: 'M3-FR1', objective: 'The profile avatar shows the user\'s initial and opens the Profile tab', input: 'Tap the avatar in the top bar',
        expected: 'Initial "A"; tab 4 (Profile) selected', run: (t) async {
          final tab = await openHome(t);
          final initial = find.text('A').evaluate().length;
          await t.tap(find.bySemanticsLabel('Open your profile'));
          await t.pump();
          return check(initial == 1 && tab() == 4, 'Initial shown ${initial == 1}; tab selected ${tab()}');
        });
    atcWidget('ATC-M3-F09', req: 'M3-FR8', objective: 'The notification bell shows the unread count and caps it at 9+', input: 'Set the unread count to 3, then to 12',
        expected: 'Badge "3" with tooltip "Notifications, 3 unread"; then badge "9+"', run: (t) async {
          await openHome(t);
          InboxService.instance.unread.value = 3;
          await t.pump();
          final three = find.text('3').evaluate().length, tip = find.byTooltip('Notifications, 3 unread').evaluate().length;
          InboxService.instance.unread.value = 12;
          await t.pump();
          final nine = find.text('9+').evaluate().length;
          InboxService.instance.unread.value = 0;
          return check(three == 1 && tip == 1 && nine == 1, 'Badge "3" ${three == 1}; tooltip ${tip == 1}; badge "9+" ${nine == 1}');
        });
    atcWidget('ATC-M3-F10', req: 'M3-FR7', objective: 'The bottom navigation bar has the five labelled tabs and each reports its index', input: 'Tap Diet, Workout, Analytics, Profile and Home in the bar',
        expected: 'Indexes 1, 2, 3, 4, 0', run: (t) async {
          var tapped = -1;
          final got = <int>[];
          await _pump(t, Scaffold(bottomNavigationBar: GlassNavBar(currentIndex: 0, onTap: (i) => tapped = i, items: const [
            NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'), NavItem(Icons.restaurant_outlined, Icons.restaurant_rounded, 'Diet'),
            NavItem(Icons.fitness_center_outlined, Icons.fitness_center_rounded, 'Workout'), NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Analytics'),
            NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile')])));
          for (final label in ['Diet', 'Workout', 'Analytics', 'Profile', 'Home']) {
            await t.tap(find.text(label));
            await t.pump();
            got.add(tapped);
          }
          return check(got.join(',') == '1,2,3,4,0', 'Indexes reported: ${got.join(', ')}');
        });
  });

  // ------------------------------------------------------------ Module 8
  group('Module 8 diet screens', () {
    FoodEntry e(String meal, String name, double kcal, double p, double c, double f) =>
        FoodEntry(date: '2026-10-15', meal: meal, name: name, quantity: 1, unit: 'serving', kcal: kcal, protein: p, carbs: c, fat: f);
    DailySummaryData data({List<FoodEntry>? entries, int burned = 250}) => DailySummaryData(
          date: DateTime(2026, 10, 15), entries: entries ?? [e('Breakfast', 'Oats', 300, 10, 50, 6), e('Lunch', 'Chicken and rice', 700, 40, 80, 20)],
          burnedKcal: burned, weekKcal: const [1800, null, 2100, 1900, null, 2000, 1000], targetKcal: 2000, proteinTarget: 120, carbsTarget: 250, fatTarget: 65, goal: 'Lose Weight', bmr: 1500);

    atcWidget('ATC-M8-F01', req: 'M8-FR13', objective: 'The daily summary shows consumed, burned and net calories with a verdict', input: 'Logged 1000 kcal, burned 250, goal Lose Weight, BMR 1500',
        expected: 'Consumed 1000, burned 250, net +750 and the words "very low intake"', run: (t) async {
          await _pump(t, DailySummaryScreen(date: DateTime(2026, 10, 15), loader: (_) async => data()));
          final c = find.text('1000').evaluate().length, b = find.text('250').evaluate().length, n = find.text('+750').evaluate().length, v = find.textContaining('very low intake').evaluate().length;
          return check(c > 0 && b > 0 && n == 1 && v == 1, 'Consumed shown ${c > 0}; burned shown ${b > 0}; net "+750" shown ${n == 1}; verdict shown ${v == 1}');
        });
    atcWidget('ATC-M8-F02', req: 'M8-FR13', objective: 'An empty day says nothing is logged and invents no macro split', input: 'Day with no food entries',
        expected: '"Nothing is logged" and the prompt to log food', run: (t) async {
          await _pump(t, DailySummaryScreen(date: DateTime(2026, 10, 15), loader: (_) async => data(entries: const [], burned: 0)));
          final a = find.textContaining('Nothing is logged').evaluate().length, b = find.text('Log food to see your protein, carbs and fat split.').evaluate().length;
          return check(a == 1 && b == 1, '"Nothing is logged" shown ${a == 1}; prompt shown ${b == 1}');
        });

    group('food search', () {
      setUpAll(() => FoodDatabase.useForTest(FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync(), bulkJson: File('assets/data/foods_bulk.json').readAsStringSync())));
      tearDownAll(() => FoodDatabase.useForTest(null));
      Future<void> open(WidgetTester t) => _pump(t, FoodTextLog(date: DateTime(2026, 10, 15), startInSearch: true));

      atcWidget('ATC-M8-F03', req: 'M8-FR7', objective: 'Typing a local name finds the food by its other name', input: 'Type "chawal"',
          expected: 'Suggestions with "Also called" and kcal values', run: (t) async {
            await open(t);
            await t.enterText(find.byType(TextField), 'chawal');
            await t.pumpAndSettle();
            final a = find.textContaining('Also called').evaluate().length, b = find.textContaining('kcal').evaluate().length;
            return check(a > 0 && b > 0, '"Also called" appears $a time(s); kcal shown $b time(s)');
          });
      atcWidget('ATC-M8-F04', req: 'M8-FR8', objective: 'Picking a suggestion adds it to the meal and closes the list', input: 'Type "banana", tap the add button of the first result',
          expected: '"Your meal" appears and the add buttons disappear', run: (t) async {
            await open(t);
            await t.enterText(find.byType(TextField), 'banana');
            await t.pumpAndSettle();
            final before = find.text('Your meal').evaluate().length;
            await t.tap(find.byIcon(Icons.add_circle_rounded).first);
            await t.pumpAndSettle();
            final after = find.text('Your meal').evaluate().length, adds = find.byIcon(Icons.add_circle_rounded).evaluate().length;
            return check(before == 0 && after == 1 && adds == 0, '"Your meal" before: $before, after: $after; add buttons left: $adds');
          });
      atcWidget('ATC-M8-F05', req: 'M8-FR7', objective: 'A food that matches the user\'s allergy is flagged in the search results', input: 'User allergic to Dairy types "milk"',
          expected: '"on your allergy list" warning with a warning icon', run: (t) async {
            await t.runAsync(() => UserSession.instance.setProfile(_profile(allergies: ['Dairy'])));
            await open(t);
            await t.enterText(find.byType(TextField), 'milk');
            await t.pumpAndSettle();
            final a = find.textContaining('on your allergy list').evaluate().length, b = find.byIcon(Icons.warning_amber_rounded).evaluate().length;
            return check(a > 0 && b > 0, 'Allergy warning shown $a time(s); warning icons $b');
          });
      atcWidget('ATC-M8-F06', req: 'M8-FR7', objective: 'A search with no result says so instead of showing an empty box', input: 'Type "qqzzxx"',
          expected: '"No matching foods"', run: (t) async {
            await open(t);
            await t.enterText(find.byType(TextField), 'qqzzxx');
            await t.pumpAndSettle();
            final a = find.textContaining('No matching foods').evaluate().length;
            return check(a == 1, 'Message shown = ${a == 1}');
          });
    });
  });

  // ------------------------------------------------------------ Module 10
  group('Module 10 allergy result screen', () {
    atcWidget('ATC-M10-F01', req: 'M10-FR6', objective: 'An allergen found on a label raises an alert dialog and then lists the ingredients', input: 'Label with wheat, milk powder, peanut butter; allergies Dairy and Nuts',
        expected: '"ALLERGEN DETECTED" dialog; after OK: "2 allergens found" and "milk powder"', run: (t) async {
          final r = AllergenMatcher.analyze('Ingredients: Wheat flour, sugar, milk powder, peanut butter, salt', ['Dairy', 'Nuts']);
          await _pump(t, AllergenResultScreen(result: r));
          final alert = find.text('ALLERGEN DETECTED').evaluate().length;
          await t.tap(find.text('OK, Got It'));
          await t.pumpAndSettle();
          final count = find.text('2 allergens found').evaluate().length, milk = find.text('milk powder').evaluate().length;
          return check(alert == 1 && count == 1 && milk == 1, 'Dialog shown ${alert == 1}; "2 allergens found" ${count == 1}; "milk powder" ${milk == 1}');
        });
    atcWidget('ATC-M10-F02', req: 'M10-FR5', objective: 'A safe label shows no alert and a clear "No allergens found"', input: 'Label "rice, salt, water"; allergy Dairy',
        expected: 'No dialog; "No allergens found"', run: (t) async {
          await _pump(t, AllergenResultScreen(result: AllergenMatcher.analyze('Ingredients: rice, salt, water', ['Dairy'])));
          final alert = find.text('ALLERGEN DETECTED').evaluate().length, safe = find.text('No allergens found').evaluate().length;
          return check(alert == 0 && safe == 1, 'Dialog shown $alert time(s); safe message shown ${safe == 1}');
        });
  });

  // ------------------------------------------------------------ Module 12
  group('Module 12 badges screen', () {
    final progress = ProgressSnapshot.build(today: DateTime(2026, 10, 14), plannedWeekdays: {1, 3, 5}, targetKcal: 2000,
        activity: {'2026-10-12': const ActivityEntry('2026-10-12', 40, 250)}, kcalByDate: {'2026-10-12': 2000, '2026-10-13': 1500});
    atcWidget('ATC-M12-F01', req: 'M12-FR9', objective: 'My badges shows the level, XP and the unlock rule of a locked badge', input: 'Open My badges with 1 workout day, 2 meal days and 1 badge',
        expected: 'Level 1, 170 XP, 30 XP to level 2, and the "30-Day Streak" badge listed', run: (t) async {
          await _pump(t, MyBadgesScreen(loader: () async => MyBadgesData(progress, const XpSnapshot(workoutDays: 1, mealDays: 2, badges: 1))));
          final a = find.text('Level 1').evaluate().length, b = find.text('170 XP in total').evaluate().length, c = find.text('30 XP to reach level 2').evaluate().length;
          await t.scrollUntilVisible(find.text('30-Day Streak'), 300, scrollable: find.byType(Scrollable).first);
          final d = find.text('30-Day Streak').evaluate().length;
          return check(a == 1 && b == 1 && c == 1 && d == 1, 'Level ${a == 1}; XP ${b == 1}; XP to next ${c == 1}; locked badge listed ${d == 1}');
        });
    atcWidget('ATC-M12-F02', req: 'M12-FR7', objective: 'A failed load shows no invented numbers', input: 'The data loader throws "offline"',
        expected: '"Level 1" is not shown', run: (t) async {
          await _pump(t, MyBadgesScreen(loader: () async => throw Exception('offline')));
          final a = find.text('Level 1').evaluate().length;
          return check(a == 0, '"Level 1" shown $a time(s)');
        });
  });

  // ------------------------------------------------------------ Module 16
  group('Module 16 notifications screen', () {
    final items = [
      _n('1', NotificationType.workoutReminder, 'Workout reminder'),
      _n('2', NotificationType.mealReminder, 'Meal log reminder'),
      _n('3', NotificationType.allergenAlert, 'Allergen found in a scanned product'),
      _n('4', NotificationType.badgeEarned, 'New badge: 7-Day Streak', read: true),
    ];
    atcWidget('ATC-M16-F01', req: 'M16-FR8', objective: 'Notifications show unread counts per tab and filter by tab', input: '4 notifications (3 unread); tap the Diet tab',
        expected: '"All (3)" and "Diet (1)"; Diet shows only the meal reminder', run: (t) async {
          await _pump(t, NotificationsScreen(loader: () async => items, onMarkRead: (_) async {}, onMarkAllRead: (_) async {}));
          final all = find.text('All (3)').evaluate().length, diet = find.text('Diet (1)').evaluate().length;
          await t.ensureVisible(find.text('Diet (1)'));
          await t.pumpAndSettle();
          await t.tap(find.text('Diet (1)'));
          await t.pumpAndSettle();
          final meal = find.text('Meal log reminder').evaluate().length, work = find.text('Workout reminder').evaluate().length;
          return check(all == 1 && diet == 1 && meal == 1 && work == 0, '"All (3)" ${all == 1}; "Diet (1)" ${diet == 1}; meal reminder shown $meal; workout reminder shown $work');
        });
    atcWidget('ATC-M16-F02', req: 'M16-FR9', objective: 'Mark all read reports exactly the unread items', input: 'Tap "Mark all read"',
        expected: 'The callback receives 3 unread items', run: (t) async {
          List<AppNotification>? marked;
          await _pump(t, NotificationsScreen(loader: () async => items, onMarkRead: (_) async {}, onMarkAllRead: (l) async => marked = l));
          await t.tap(find.text('Mark all read'));
          await t.pumpAndSettle();
          final n = marked?.where((x) => !x.read).length;
          return check(n == 3, 'Callback received ${marked?.length} item(s), $n unread');
        });
    atcWidget('ATC-M16-F03', req: 'M16-FR8', objective: 'A failed load shows an error, not an empty inbox', input: 'The loader throws "offline"',
        expected: '"Could not load your notifications." and no "No notifications yet"', run: (t) async {
          await _pump(t, NotificationsScreen(loader: () async => throw Exception('offline')));
          final a = find.text('Could not load your notifications.').evaluate().length, b = find.textContaining('No notifications yet').evaluate().length;
          return check(a == 1 && b == 0, 'Error shown ${a == 1}; empty-inbox text shown $b time(s)');
        });
  });

  // ------------------------------------------------------------ Module 17
  group('Module 17 analytics screen', () {
    ProgressSnapshot snapshot() => ProgressSnapshot.build(today: DateTime(2026, 10, 14), plannedWeekdays: {1, 3, 5}, targetKcal: 2000,
        activity: {'2026-10-12': const ActivityEntry('2026-10-12', 40, 250)}, kcalByDate: {'2026-10-12': 2000, '2026-10-13': 1500, '2026-10-14': 1900});
    atcWidget('ATC-M17-F01', req: 'M17-FR2', objective: 'Analytics shows the calorie chart, the weekly score and an honest scope note', input: 'Open analytics with 6 weigh-ins',
        expected: '"Calories vs your target", "Weekly fitness score", and the note "not part of this version"', run: (t) async {
          final weights = [for (var i = 0; i < 6; i++) WeightPoint(DateTime(2026, 10, 1 + i * 2), 60 - i * 0.2)];
          await _pump(t, AnalyticsScreen(loader: () async => AnalyticsData(snapshot(), weights)));
          final a = find.text('Calories vs your target').evaluate().length, b = find.text('Weekly fitness score').evaluate().length;
          await t.scrollUntilVisible(find.textContaining('not part of this version'), 300);
          final c = find.textContaining('not part of this version').evaluate().length;
          return check(a == 1 && b == 1 && c == 1 && t.takeException() == null, 'Calorie chart ${a == 1}; weekly score ${b == 1}; scope note ${c == 1}');
        });
    atcWidget('ATC-M17-F02', req: 'M17-FR2', objective: 'A failed analytics load offers a retry', input: 'The loader throws',
        expected: '"Could not load your analytics." and a "Try again" button', run: (t) async {
          await _pump(t, AnalyticsScreen(loader: () async => throw Exception('x')));
          final a = find.text('Could not load your analytics.').evaluate().length, b = find.text('Try again').evaluate().length;
          return check(a == 1 && b == 1, 'Error shown ${a == 1}; retry button shown ${b == 1}');
        });
  });

  // ------------------------------------------------------------ Module 14
  group('Module 14 specialist list, booking and appointments', () {
    final doc = _spec('d', 'Hina Malik', type: SpecialistType.doctor, specialty: 'General medicine', rating: 4.9, reviews: 80, emergency: true);
    final nut = _spec('n', 'Sara Khan', specialty: 'Sports nutrition', rating: 4.2, reviews: 10);
    final closed = _spec('c', 'Omar Closed', type: SpecialistType.trainer, specialty: 'Yoga', available: false);
    final data = SpecialistsData([doc, nut, closed], {'d': DateTime.utc(2026, 10, 19, 5), 'n': DateTime.utc(2026, 10, 20, 5), 'c': null});
    final s = _spec('s1', 'Sara Khan');

    atcWidget('ATC-M14-F01', req: 'M14-FR1', objective: 'The specialist list shows a count and disables Book for a specialist who is not taking bookings', input: 'Open "Find a specialist" with 3 specialists (1 closed)',
        expected: '"3 Specialists Found", "Not taking bookings", 3 Book buttons of which 1 is disabled', run: (t) async {
          await _pump(t, SpecialistsScreen(loader: () async => data, clock: _clock));
          final count = find.text('3 Specialists Found').evaluate().length, closedText = find.text('Not taking bookings').evaluate().length;
          final books = t.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Book')).toList();
          final off = books.where((b) => b.onPressed == null).length;
          return check(count == 1 && closedText == 1 && books.length == 3 && off == 1, 'Count text ${count == 1}; "Not taking bookings" ${closedText == 1}; Book buttons ${books.length}, disabled $off');
        });
    atcWidget('ATC-M14-F02', req: 'M14-FR1', objective: 'The type chip filters the list', input: 'Tap the "Nutritionist" chip',
        expected: '"1 Nutritionist Found"; only Sara Khan remains', run: (t) async {
          await _pump(t, SpecialistsScreen(loader: () async => data, clock: _clock));
          await t.tap(find.widgetWithText(ChoiceChip, 'Nutritionist'));
          await t.pumpAndSettle();
          final a = find.text('1 Nutritionist Found').evaluate().length, b = find.text('Sara Khan').evaluate().length, c = find.text('Dr. Hina Malik').evaluate().length;
          return check(a == 1 && b == 1 && c == 0, 'Count text ${a == 1}; Sara Khan shown $b; Dr. Hina Malik shown $c');
        });
    atcWidget('ATC-M14-F03', req: 'M14-FR1', objective: 'Search by specialty finds the trainer', input: 'Type "yoga" with the type filter on All',
        expected: '"1 Specialist Found" and Omar Closed', run: (t) async {
          await _pump(t, SpecialistsScreen(loader: () async => data, clock: _clock));
          await t.enterText(find.byType(TextField), 'yoga');
          await t.pumpAndSettle();
          final a = find.text('1 Specialist Found').evaluate().length, b = find.text('Omar Closed').evaluate().length;
          return check(a == 1 && b == 1, 'Count text ${a == 1}; Omar Closed shown ${b == 1}');
        });
    atcWidget('ATC-M14-F04', req: 'M14-FR1', objective: 'A specialist with no reviews is shown as New and not hidden', input: 'One specialist with 0 reviews',
        expected: '"Newly Joined" listed with a "New" tag', run: (t) async {
          final fresh = _spec('f', 'Newly Joined', reviews: 0, rating: 0);
          await _pump(t, SpecialistsScreen(loader: () async => SpecialistsData([fresh], {'f': DateTime.utc(2026, 10, 19, 5)}), clock: _clock));
          final a = find.text('Newly Joined').evaluate().length, b = find.text('New').evaluate().length;
          return check(a == 1 && b == 1, 'Name shown ${a == 1}; "New" tag shown ${b == 1}');
        });
    atcWidget('ATC-M14-F05', req: 'M14-FR1', objective: 'A failed load is explained and can be retried', input: 'The first load fails; tap "Try again"',
        expected: 'Error text, then "3 Specialists Found"', run: (t) async {
          var calls = 0;
          await _pump(t, SpecialistsScreen(loader: () async {
            calls++;
            if (calls == 1) throw const ApiException('Could not reach the database. Check your internet connection.');
            return data;
          }, clock: _clock));
          final err = find.textContaining('Could not reach the database').evaluate().length;
          await t.tap(find.text('Try again'));
          await t.pumpAndSettle();
          final ok = find.text('3 Specialists Found').evaluate().length;
          return check(err == 1 && ok == 1, 'Error shown ${err == 1}; after retry list shown ${ok == 1}');
        });
    atcWidget('ATC-M14-F06', req: 'M14-FR2', objective: 'Confirm booking stays disabled until a time is chosen, and nothing is shared by default', input: 'Open the booking screen and choose nothing',
        expected: 'Confirm disabled; "Not chosen yet"; every sharing tick box off', run: (t) async {
          await _pump(t, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}));
          await t.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
          final glow = find.ancestor(of: find.text('Confirm booking'), matching: find.byType(GlowButton));
          final disabled = t.widget<GlowButton>(glow).onPressed == null;
          final boxes = t.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).toList();
          final anyTicked = boxes.any((c) => c.value == true);
          final notChosen = find.text('Not chosen yet').evaluate().length;
          return check(disabled && notChosen == 1 && boxes.isNotEmpty && !anyTicked, 'Confirm disabled $disabled; "Not chosen yet" $notChosen; sharing boxes ${boxes.length}, any ticked $anyTicked');
        });
    atcWidget('ATC-M14-F07', req: 'M14-FR2', objective: 'Booking sends exactly the chosen time, type, shares and note, then opens the payment screen', input: 'Pick the first time (09:00), "Chat only", share "Diet log, last 7 days", note "Help with a meal plan", tap Confirm',
        expected: 'Slot 04:00 UTC, chat, diet log shared only, note kept; the Payment screen opens', run: (t) async {
          DateTime? bookedSlot;
          ConsultType? bookedType;
          SharePrefs? bookedShares;
          String? bookedNotes;
          await _pump(t, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}, paymentHooks: _testHooks,
              book: ({required specialist, required slot, required type, required shares, required notes}) async {
                bookedSlot = slot;
                bookedType = type;
                bookedShares = shares;
                bookedNotes = notes;
                return _held();
              }));
          final first = DateTime.utc(2026, 10, 19, 4, 0);
          await t.tap(find.text(ConsultationService.formatTime(first)).first);
          await t.pumpAndSettle();
          await t.tap(find.text('Chat only'));
          await t.pumpAndSettle();
          await t.tap(find.text('Diet log, last 7 days'));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), 'Help with a meal plan');
          await t.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
          final fee = find.text('PKR 1,200').evaluate().length;
          await t.tap(find.text('Confirm booking'));
          await t.pumpAndSettle();
          final pay = find.text('Payment').evaluate().length, order = find.text('Order summary').evaluate().length;
          final ok = bookedSlot == first && bookedType == ConsultType.chat && bookedShares!.foodLog7d && !bookedShares!.healthSummary && !bookedShares!.activity30d && bookedNotes == 'Help with a meal plan';
          return check(ok && fee > 0 && pay == 1 && order == 1, 'Slot ${bookedSlot?.toIso8601String()}; type ${bookedType?.name}; diet log shared ${bookedShares?.foodLog7d}, health summary shared ${bookedShares?.healthSummary}; chat fee shown ${fee > 0}; Payment screen opened ${pay == 1}');
        });
    atcWidget('ATC-M14-F08', req: 'M14-FR2', objective: 'A time someone else just took is refused and the screen stays', input: 'Choose a time; the booking call answers "just taken"',
        expected: 'The message "just taken by someone else" and the booking screen still open', run: (t) async {
          await _pump(t, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{},
              book: ({required specialist, required slot, required type, required shares, required notes}) async =>
                  throw const ApiException('That time was just taken by someone else. Please choose another.', statusCode: 409)));
          await t.tap(find.text(ConsultationService.formatTime(DateTime.utc(2026, 10, 19, 4, 0))).first);
          await t.pumpAndSettle();
          await t.scrollUntilVisible(find.text('Confirm booking'), 400, scrollable: find.byType(Scrollable).first);
          await t.tap(find.text('Confirm booking'));
          await t.pumpAndSettle();
          final msg = find.textContaining('just taken by someone else').evaluate().length, stay = find.text('Book appointment').evaluate().length;
          return check(msg == 1 && stay == 1, 'Message shown ${msg == 1}; still on the booking screen ${stay == 1}');
        });
    atcWidget('ATC-M14-F09', req: 'M14-FR2', objective: 'A time that is already booked is not offered', input: 'The 09:00 slot is booked by someone else',
        expected: '09:00 is not listed, 09:30 is', run: (t) async {
          final taken = DateTime.utc(2026, 10, 19, 4, 0);
          await _pump(t, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => {taken.millisecondsSinceEpoch}));
          final a = find.text(ConsultationService.formatTime(taken)).evaluate().length, b = find.text(ConsultationService.formatTime(DateTime.utc(2026, 10, 19, 4, 30))).evaluate().length;
          return check(a == 0 && b > 0, '09:00 listed $a time(s); 09:30 listed $b time(s)');
        });
    atcWidget('ATC-M14-F10', req: 'M14-FR2', objective: 'The notes box stops at 500 characters', input: 'Paste 600 characters into the note',
        expected: 'Only 500 characters are kept', run: (t) async {
          await _pump(t, BookAppointmentScreen(specialist: s, clock: _clock, loadBooked: (_) async => <int>{}));
          await t.enterText(find.byType(TextField), 'x' * 600);
          await t.pump();
          final len = t.widget<TextField>(find.byType(TextField)).controller!.text.length;
          return same(len, 500, say: 'Characters kept: $len');
        });
    final upcoming = _appt('u1', start: _now.add(const Duration(days: 1)));
    final past = _appt('p1', start: _now.subtract(const Duration(days: 3)), status: AppointmentStatus.completed, note: ConsultationNote(notes: 'Eat more protein.', prescription: 'Iron tablets', updatedAt: _now));
    atcWidget('ATC-M14-F11', req: 'M14-FR3', objective: 'My appointments separates upcoming from past and shows the specialist\'s notes only under Past', input: 'One upcoming and one completed appointment; open the Past tab',
        expected: '"Upcoming (1)"; notes hidden first, visible under Past with "Completed"', run: (t) async {
          await _pump(t, MyAppointmentsScreen(loader: () async => [upcoming, past], clock: _clock));
          final tab = find.text('Upcoming (1)').evaluate().length, hidden = find.text('Notes from specialist').evaluate().length;
          await t.tap(find.text('Past'));
          await t.pumpAndSettle();
          final shown = find.text('Notes from specialist').evaluate().length, done = find.text('Completed').evaluate().length;
          return check(tab == 1 && hidden == 0 && shown == 1 && done == 1, 'Upcoming tab ${tab == 1}; notes before $hidden, after $shown; "Completed" $done');
        });
    atcWidget('ATC-M14-F12', req: 'M14-FR3', objective: 'A request shows as awaiting acceptance, has no video link and can be cancelled', input: 'Appointment with status "requested"',
        expected: '"Awaiting acceptance", "Waiting for your specialist", no meeting room, a Cancel request button', run: (t) async {
          final req = _appt('req', start: _now.add(const Duration(days: 1)), status: AppointmentStatus.requested).copyWith(meetingLink: '');
          await _pump(t, MyAppointmentsScreen(loader: () async => [req], clock: _clock));
          final a = find.text('Awaiting acceptance').evaluate().length;
          await _pump(t, AppointmentDetailScreen(appointment: req, clock: _clock));
          final w = find.text('Waiting for your specialist').evaluate().length, room = find.text('Meeting room').evaluate().length;
          await t.scrollUntilVisible(find.text('Cancel request'), 300, scrollable: find.byType(Scrollable).first);
          final c = find.text('Cancel request').evaluate().length;
          return check(a == 1 && w == 1 && room == 0 && c == 1, 'Awaiting label ${a == 1}; waiting text ${w == 1}; meeting room shown $room; cancel button ${c == 1}');
        });
    atcWidget('ATC-M14-F13', req: 'M14-FR3', objective: 'A declined request shows the reason and offers no cancel', input: 'Appointment declined with reason "On leave that day"',
        expected: '"Not accepted" and the reason; no Cancel appointment button', run: (t) async {
          final declined = Appointment.fromJson('d', {..._appt('d', start: _now.add(const Duration(days: 1)), status: AppointmentStatus.declined).toJson(), 'declineReason': 'On leave that day'})!;
          await _pump(t, AppointmentDetailScreen(appointment: declined, clock: _clock));
          final a = find.text('Not accepted').evaluate().length, b = find.textContaining('On leave that day').evaluate().length, c = find.text('Cancel appointment').evaluate().length;
          return check(a == 1 && b == 1 && c == 0, '"Not accepted" ${a == 1}; reason shown ${b == 1}; cancel button $c');
        });
    atcWidget('ATC-M14-F14', req: 'M14-FR3', objective: 'A confirmed appointment shows the meeting link and the join window rule', input: 'Confirmed appointment tomorrow',
        expected: 'Meeting room, the link and "opens 5 minutes before"', run: (t) async {
          await _pump(t, AppointmentDetailScreen(appointment: upcoming, clock: _clock));
          final a = find.text('Meeting room').evaluate().length, b = find.text('https://meet.example/baymax-abc').evaluate().length, c = find.textContaining('opens 5 minutes before').evaluate().length;
          return check(a == 1 && b == 1 && c == 1, 'Meeting room ${a == 1}; link ${b == 1}; join rule text ${c == 1}');
        });
    atcWidget('ATC-M14-F15', req: 'M14-FR3', objective: 'The room is announced as open inside the join window', input: 'Confirmed appointment starting in 3 minutes',
        expected: '"The room is open now"', run: (t) async {
          await _pump(t, AppointmentDetailScreen(appointment: _appt('live', start: _now.add(const Duration(minutes: 3))), clock: _clock));
          final a = find.textContaining('The room is open now').evaluate().length;
          return check(a == 1, 'Room-open text shown ${a == 1}');
        });
    atcWidget('ATC-M14-F16', req: 'M14-FR2', objective: 'Cancelling asks for confirmation first and then shows the new status', input: 'Tap Cancel appointment, choose "Keep it", then cancel again and confirm',
        expected: 'Nothing cancelled after "Keep it"; afterwards status "Cancelled" and no cancel button', run: (t) async {
          Appointment? cancelled;
          await _pump(t, AppointmentDetailScreen(appointment: upcoming, clock: _clock, onCancel: (a) async => cancelled = a));
          await t.scrollUntilVisible(find.text('Cancel appointment'), 300, scrollable: find.byType(Scrollable).first);
          await t.tap(find.text('Cancel appointment'));
          await t.pumpAndSettle();
          final ask = find.text('Cancel this appointment?').evaluate().length;
          await t.tap(find.text('Keep it'));
          await t.pumpAndSettle();
          final kept = cancelled == null;
          await t.tap(find.text('Cancel appointment'));
          await t.pumpAndSettle();
          await t.tap(find.widgetWithText(FilledButton, 'Cancel appointment'));
          await t.pumpAndSettle();
          final st = find.text('Cancelled').evaluate().length, btn = find.text('Cancel appointment').evaluate().length;
          return check(ask == 1 && kept && cancelled?.id == 'u1' && st == 1 && btn == 0, 'Confirmation asked ${ask == 1}; nothing cancelled after "Keep it" $kept; cancelled id ${cancelled?.id}; status shown ${st == 1}; cancel button left $btn');
        });
    atcWidget('ATC-M14-F17', req: 'M14-FR3', objective: 'An appointment that has already started has no cancel button', input: 'Confirmed appointment that started 5 minutes ago',
        expected: 'No Cancel appointment button', run: (t) async {
          await _pump(t, AppointmentDetailScreen(appointment: _appt('s', start: _now.subtract(const Duration(minutes: 5))), clock: _clock));
          final a = find.text('Cancel appointment').evaluate().length;
          return check(a == 0, 'Cancel button shown $a time(s)');
        });
  });

  // ------------------------------------------------------------ Module 15
  group('Module 15 payment screens', () {
    PaymentHooks hooks({Future<Appointment> Function(Appointment, PaymentRequest, int)? pay, Future<void> Function(Appointment)? release, Future<OrderSummary> Function(Appointment)? order, List<SavedCard> saved = const []}) =>
        PaymentHooks(pay: pay, releaseHold: release ?? (_) async {}, loadOrder: order ?? (a) async => OrderSummary(consultationFee: a.fee), loadSavedCards: () async => saved, testMode: true);
    PaymentRecord record({PaymentMethod method = PaymentMethod.card, PaymentStatus status = PaymentStatus.paid, int platform = 0, String mode = 'sandbox'}) => PaymentRecord(
        transactionId: 'TXN-TEST-0001', method: method, status: status, consultationFee: 2000, platformFee: platform, brand: 'Visa', last4: '4242', reference: 'sbx_c_abc', mode: mode, paidAt: _now);
    Future<void> fill(WidgetTester t, {String number = '4242424242424242', String expiry = '1230', String cvv = '123', String holder = 'Ayesha Khan'}) async {
      await t.enterText(find.widgetWithText(TextField, 'Card number'), number);
      await t.enterText(find.widgetWithText(TextField, 'Expiry (MM/YY)'), expiry);
      await t.enterText(find.widgetWithText(TextField, 'CVV'), cvv);
      await t.enterText(find.widgetWithText(TextField, 'Cardholder name'), holder);
      await t.pumpAndSettle();
    }
    GlowButton payButton(WidgetTester t) => t.widget<GlowButton>(find.byType(GlowButton).last);
    Appointment held({Duration hold = const Duration(minutes: 10)}) => _appt('a1', status: AppointmentStatus.pendingPayment, holdUntil: _now.add(hold));

    atcWidget('ATC-M15-F01', req: 'M15-FR1', objective: 'The payment screen shows the booking, the fee breakdown with an explicit zero platform fee and the test-mode notice', input: 'Open the payment screen for a held PKR 2,000 booking',
        expected: 'Specialist, "Doctor", "Video call", fees PKR 2,000 and PKR 0, a padlock, the 10:00 countdown and "Test mode"', run: (t) async {
          await _pump(t, PaymentScreen(appointment: held(), hooks: hooks(), clock: _clock));
          final r = [
            find.text('Dr. Hina Malik').evaluate().length == 1, find.text('Doctor').evaluate().length == 1, find.text('Video call').evaluate().length == 1,
            find.text('Platform fee').evaluate().length == 1, find.text('PKR 0').evaluate().length == 1, find.text('PKR 2,000').evaluate().isNotEmpty,
            find.byIcon(Icons.lock_rounded).evaluate().isNotEmpty, find.text('Your time is held for 10:00').evaluate().length == 1, find.textContaining('Test mode').evaluate().length == 1,
          ];
          return check(r.every((x) => x), 'Checks (specialist, role, type, platform fee label, PKR 0, PKR 2,000, padlock, countdown, test mode): ${r.join(', ')}');
        });
    atcWidget('ATC-M15-F02', req: 'M15-FR4', objective: 'The total includes the platform fee', input: 'Platform fee PKR 150',
        expected: '"PKR 150" and a total of "PKR 2,150"', run: (t) async {
          await _pump(t, PaymentScreen(appointment: held(), hooks: hooks(order: (a) async => OrderSummary(consultationFee: a.fee, platformFee: 150)), clock: _clock));
          final a = find.text('PKR 150').evaluate().length, b = find.text('PKR 2,150').evaluate().length;
          return check(a == 1 && b == 1, '"PKR 150" shown $a time(s); "PKR 2,150" shown $b time(s)');
        });
    atcWidget('ATC-M15-F03', req: 'M15-FR3', objective: 'Pay stays disabled until all card fields are valid, the CVV is hidden and the number is grouped as typed', input: 'Enter a number failing the check digit, then an expired card, then a good card',
        expected: 'Disabled with "not valid" and "This card has expired."; enabled with the good card; CVV obscured; "4242 4242 4242 4242"', run: (t) async {
          await _pump(t, PaymentScreen(appointment: held(), hooks: hooks(), clock: _clock));
          final start = payButton(t).onPressed == null;
          await t.enterText(find.widgetWithText(TextField, 'Card number'), '4242424242424241');
          await t.pumpAndSettle();
          final notValid = find.textContaining('not valid').evaluate().length;
          await fill(t, expiry: '0925');
          final expired = find.text('This card has expired.').evaluate().length, stillOff = payButton(t).onPressed == null;
          await fill(t);
          final on = payButton(t).onPressed != null, label = find.text('Pay PKR 2,000').evaluate().length;
          final obscured = t.widget<TextField>(find.widgetWithText(TextField, 'CVV')).obscureText;
          final grouped = t.widget<TextField>(find.widgetWithText(TextField, 'Card number')).controller!.text;
          return check(start && notValid == 1 && expired == 1 && stillOff && on && label == 1 && obscured && grouped == '4242 4242 4242 4242',
              'Initially disabled $start; "not valid" $notValid; "expired" $expired; disabled with expired card $stillOff; enabled with good card $on; CVV hidden $obscured; number shown as "$grouped"');
        });
    atcWidget('ATC-M15-F04', req: 'M15-FR6', objective: 'Paying sends exactly the card and amount, blocks a second tap while running, then shows the receipt', input: 'Fill a good card, tap Pay twice while the payment is in progress',
        expected: 'One payment call of PKR 2,000 by card, button loading, then "Payment successful" with the transaction id', run: (t) async {
          final gate = Completer<Appointment>();
          var calls = 0;
          PaymentRequest? sent;
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks(pay: (a, r, f) { calls++; sent = r; return gate.future; })));
          await fill(t);
          await t.tap(find.text('Pay PKR 2,000'));
          await t.pump();
          final loading = payButton(t).loading, off = payButton(t).onPressed == null;
          await t.tap(find.byType(GlowButton).last, warnIfMissed: false);
          await t.pump();
          gate.complete(held().copyWith(status: AppointmentStatus.confirmed, payment: record(), clearHold: true));
          await t.pumpAndSettle();
          final done = find.text('Payment successful').evaluate().length, txn = find.text('TXN-TEST-0001').evaluate().length;
          return check(calls == 1 && loading && off && sent!.amount == 2000 && sent!.method == PaymentMethod.card && sent!.card!.number == '4242 4242 4242 4242' && done == 1 && txn == 1,
              'Payment calls $calls; button loading $loading; duplicate tap blocked ${calls == 1}; amount ${sent?.amount}; receipt shown ${done == 1}; transaction id shown ${txn == 1}');
        });
    atcWidget('ATC-M15-F05', req: 'M15-FR5', objective: 'A declined card shows the reason, keeps the screen and does not give the time back', input: 'Pay with a card the gateway declines',
        expected: '"Your card was declined"; still on Payment; hold not released; Pay usable again', run: (t) async {
          var released = false;
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks(release: (_) async => released = true,
              pay: (a, r, f) async => throw const ApiException('Your card was declined. Try another card or payment method.', statusCode: 402))));
          await fill(t);
          await t.tap(find.text('Pay PKR 2,000'));
          await t.pumpAndSettle();
          final msg = find.textContaining('Your card was declined').evaluate().length, stay = find.text('Payment').evaluate().length;
          return check(msg == 1 && stay == 1 && !released && payButton(t).onPressed != null, 'Message shown ${msg == 1}; still on Payment ${stay == 1}; time released $released; Pay enabled ${payButton(t).onPressed != null}');
        });
    atcWidget('ATC-M15-F06', req: 'M15-FR2', objective: 'Pay at clinic needs no details and says nothing is charged now', input: 'Choose "Pay at Clinic"',
        expected: 'No card fields; "Nothing is charged now"', run: (t) async {
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks()));
          await t.tap(find.text('Pay at Clinic'));
          await t.pumpAndSettle();
          final fields = find.widgetWithText(TextField, 'Card number').evaluate().length, note = find.textContaining('Nothing is charged now').evaluate().length;
          return check(fields == 0 && note == 1, 'Card number fields $fields; note shown ${note == 1}');
        });
    atcWidget('ATC-M15-F07', req: 'M15-FR2', objective: 'A saved card asks only for its CVV and is charged by token', input: 'One saved Visa ending 4242; type CVV 123 and pay',
        expected: 'No card number box; Pay enabled only after the CVV; the request carries the token and no card number', run: (t) async {
          const saved = SavedCard(id: 'c1', token: 'sbx_tok_abc', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030);
          PaymentRequest? sent;
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks(saved: const [saved], pay: (a, r, f) async { sent = r; return held().copyWith(status: AppointmentStatus.confirmed, payment: record(), clearHold: true); })));
          final list = find.text('Your saved cards').evaluate().length, noBox = find.widgetWithText(TextField, 'Card number').evaluate().length, offBefore = payButton(t).onPressed == null;
          await t.enterText(find.widgetWithText(TextField, 'CVV for Visa ending 4242'), '123');
          await t.pumpAndSettle();
          final onAfter = payButton(t).onPressed != null;
          await t.tap(find.text('Pay PKR 2,000'));
          await t.pumpAndSettle();
          return check(list == 1 && noBox == 0 && offBefore && onAfter && sent?.savedCard?.token == 'sbx_tok_abc' && sent?.card == null,
              'Saved cards listed ${list == 1}; card number box $noBox; disabled before CVV $offBefore; enabled after $onAfter; token sent ${sent?.savedCard?.token}; card number sent ${sent?.card != null}');
        });
    atcWidget('ATC-M15-F08', req: 'M15-FR4', objective: 'If the fee cannot be read there is an error and Pay stays disabled', input: 'The fee loader fails; fill a good card',
        expected: '"could not read the consultation fee"; Pay disabled', run: (t) async {
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks(order: (a) async => throw const ApiException('We could not read the consultation fee.'))));
          final msg = find.textContaining('could not read the consultation fee').evaluate().length;
          await fill(t);
          return check(msg == 1 && payButton(t).onPressed == null, 'Error shown ${msg == 1}; Pay enabled ${payButton(t).onPressed != null}');
        });
    atcWidget('ATC-M15-F09', req: 'M15-FR6', objective: 'A hold that ran out says nothing was charged and gives the time back', input: 'Hold of 1 second, clock moved on 5 seconds',
        expected: '"has run out" and "Nothing was charged"; released once', run: (t) async {
          var released = 0;
          var now = _now;
          await _pump(t, PaymentScreen(appointment: held(hold: const Duration(seconds: 1)), clock: () => now, hooks: hooks(release: (_) async => released++)));
          now = _now.add(const Duration(seconds: 5));
          await t.pump(const Duration(seconds: 2));
          await t.pumpAndSettle();
          final a = find.textContaining('has run out').evaluate().length, b = find.textContaining('Nothing was charged').evaluate().length;
          return check(a == 1 && b == 1 && released == 1, '"has run out" ${a == 1}; "Nothing was charged" ${b == 1}; releases $released');
        });
    atcWidget('ATC-M15-F10', req: 'M15-FR6', objective: 'Leaving the payment screen without paying gives the time back', input: 'Close the payment screen',
        expected: 'The hold is released once', run: (t) async {
          var released = 0;
          await _pump(t, PaymentScreen(appointment: held(), clock: _clock, hooks: hooks(release: (_) async => released++)));
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          return same(released, 1, say: 'Releases: $released');
        });
  });
}

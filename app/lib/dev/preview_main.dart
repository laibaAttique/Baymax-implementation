// DEVELOPMENT ONLY: opens screens with a demo profile and demo data so the UI can be checked without signing in.
//   flutter run -t lib/dev/preview_main.dart -d <device> --dart-define=PREVIEW_SCREEN=analytics
// PREVIEW_SCREEN: home (default) | diet | workout | analytics | profile | community | calorie | body | specialists | appointments | payment | settings | nutrition |
//   sources | chatbot | allergy | posture | voice | exercise | login | signup | splash | step1 | step2 | step3 | classification | bmi | drawer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../main.dart' show baymaxShell;
import '../models/health_profile.dart';
import '../screens/allergy/allergy_scanner.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/analytics/body_transform_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/chatbot/chatbot_screen.dart';
import '../screens/community/community_screen.dart';
import '../screens/dashboard/main_navigation.dart';
import '../screens/health_profiling/bmi_result.dart';
import '../screens/health_profiling/health_classification.dart';
import '../screens/health_profiling/step1_personal_info.dart';
import '../screens/health_profiling/step2_medical_history.dart';
import '../screens/health_profiling/step3_fitness_goals.dart';
import '../screens/nutrition/calorie_target_screen.dart';
import '../screens/nutrition/nutrition_plan_screen.dart';
import '../screens/diet/food_scan_screen.dart';
import '../screens/posture_detection/camera_detection.dart';
import '../screens/posture_detection/manual_guidance.dart';
import '../screens/posture_detection/posture_feedback.dart';
import '../screens/posture_detection/posture_mode.dart';
import '../models/workout_session.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/sources_screen.dart';
import '../models/consultation.dart';
import '../models/payment.dart';
import '../screens/specialists/my_appointments_screen.dart';
import '../screens/specialists/payment_screen.dart';
import '../screens/specialists/specialists_screen.dart';
import '../screens/voice_assistant/voice_assistant_screen.dart';
import '../screens/workout_and_exercise/exercise_detail.dart';
import '../services/activity_service.dart';
import '../models/food.dart';
import '../services/calorie_optimizer.dart';
import '../services/chat_history.dart';
import '../services/community_service.dart';
import '../services/progress_service.dart';
import '../services/realtime_db.dart';
import '../services/user_session.dart';
import '../services/user_settings_service.dart';
import '../services/weight_projection.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';

ProgressSnapshot _demoProgress() {
  final today = DateTime.now();
  final activity = <String, ActivityEntry>{};
  final kcal = <String, double>{};
  for (var i = 0; i < 28; i++) {
    final d = today.subtract(Duration(days: i));
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (i % 3 != 2) activity[key] = ActivityEntry(key, 35, 220);
    if (i % 4 != 3) kcal[key] = 1750.0 + (i * 37) % 500;
  }
  return ProgressSnapshot.build(today: today, plannedWeekdays: {1, 3, 5, 6}, targetKcal: 2010, activity: activity, kcalByDate: kcal, storedBadges: {'first_workout', 'streak_3'});
}

List<WeightPoint> _demoWeights() {
  final today = DateTime.now();
  return [for (var i = 0; i < 14; i++) WeightPoint(DateTime(today.year, today.month, today.day).subtract(Duration(days: 27 - i * 2)), 60.2 - i * 0.12 + (i.isEven ? 0.25 : -0.15))];
}

Widget _screen(String name) {
  final progress = _demoProgress();
  final weights = _demoWeights();
  switch (name) {
    case 'diet':
      return const MainNavigation(initialIndex: 1);
    case 'workout':
      return const MainNavigation(initialIndex: 2);
    case 'analytics':
      return AnalyticsScreen(loader: () async => AnalyticsData(progress, weights));
    case 'profile':
      return const MainNavigation(initialIndex: 4);
    case 'community':
      return CommunityScreen(
        loader: () async {
          final entries = [
            const LeaderboardEntry('u1', 'Sara', 88, 4, 7),
            const LeaderboardEntry('me', 'Ayesha', 62, 3, 6),
            const LeaderboardEntry('u3', 'Hira', 41, 2, 4),
          ];
          return CommunityData(
              progress: progress,
              settings: const UserSettings(leaderboardOptIn: true, displayName: 'Ayesha'),
              entries: entries,
              cohort: CommunityService.instance.levels(entries),
              myUid: 'me');
        },
      );
    case 'calorie':
      final p = UserSession.instance.profile!;
      return CalorieTargetScreen(
        loader: () async => CalorieTargetData(
          estimate: CalorieEstimate(
              status: EstimateStatus.adapted,
              priorTdee: p.tdee,
              tdee: p.tdee + 190,
              observedTdee: p.tdee + 420,
              dataShare: 0.45,
              reason: 'Your weight and food logs suggest your body uses about ${(p.tdee + 420).round()} kcal a day, more than the formula\'s ${p.tdee.round()}.',
              weighIns: 14,
              completeDays: 22,
              trendKgPerWeek: -0.08),
          weights: weights,
          targetKcal: p.dailyCalorieTarget + 190,
          formulaKcal: p.dailyCalorieTarget,
        ),
      );
    case 'body':
      return BodyTransformScreen(loader: () async => BodyTransformData(projectWeight(weights: weights, today: DateTime.now(), targetKg: 56), weights, 56, 58));
    case 'specialists':
      return SpecialistsScreen(loader: () async => SpecialistsData(_demoSpecialists, {for (final s in _demoSpecialists) s.id: DateTime.now().add(const Duration(hours: 20))}), loadBooked: (_) async => <int>{}, book: _demoBook, loadAppointments: () async => _demoAppointments);
    case 'payment':
      return PaymentScreen(
        appointment: Appointment.fromJson('held', {
          ..._demoAppointments.first.toJson(),
          'status': 'pending_payment',
          'holdUntil': DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        })!,
        hooks: PaymentHooks(
          testMode: true,
          loadOrder: (a) async => OrderSummary(consultationFee: a.fee),
          loadSavedCards: () async => const [SavedCard(id: 'c1', token: 'sbx_tok_demo0001', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030)],
          releaseHold: (_) async {},
          pay: (a, r, fee) async => a.copyWith(status: AppointmentStatus.confirmed, clearHold: true),
        ),
        clock: () => DateTime.now(),
      );
    case 'appointments':
      return MyAppointmentsScreen(loader: () async => _demoAppointments);
    case 'settings':
      return SettingsScreen(loader: () async => const UserSettings(reminderEnabled: true, leaderboardOptIn: true, displayName: 'Ayesha', inactivityAlerts: true), saver: (_) async {});
    case 'nutrition':
      return const NutritionPlanScreen();
    case 'sources':
      return const SourcesScreen();
    case 'chatbot':
      // Demo history so the answers that use the user's own data can be tried without signing in.
      return ChatbotScreen(historyLoader: () async {
        String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final t = DateTime.now();
        final y = t.subtract(const Duration(days: 1));
        FoodEntry e(DateTime d, String meal, String name, double kcal, double p) =>
            FoodEntry(date: key(d), meal: meal, name: name, quantity: 1, unit: 'serving', kcal: kcal, protein: p, carbs: 40, fat: 9);
        return ChatHistory(
          entriesByDate: {
            key(t): [e(t, 'Breakfast', 'Oatmeal', 332, 12), e(t, 'Snack', 'Banana', 105, 1)],
            key(y): [e(y, 'Lunch', 'Chicken biryani', 480, 24), e(y, 'Dinner', 'Daal', 230, 14)],
          },
          progress: progress,
          weights: weights,
        );
      });
    case 'allergy':
      return const AllergyScanner();
    case 'posture':
      return PostureModeSelection(
        request: const WorkoutSessionRequest(
          exercise: SessionExercise(id: 'squat', name: 'Bodyweight Squat', sets: 3, reps: 10),
        ),
      );
    case 'voice':
      return const VoiceAssistantScreen();
    case 'exercise':
      final plan = UserSession.instance.plan!;
      final day = plan.week.firstWhere((d) => d != null)!;
      return ExerciseDetail(planned: day.exercises[1], safetyNotes: plan.restrictionNotes);
    case 'login':
      return const LoginScreen();
    case 'signup':
      return const SignupScreen();
    case 'splash':
      return const SplashScreen();
    case 'step1':
      return Step1PersonalInfo(profile: HealthProfile());
    case 'step2':
      return Step2MedicalHistory(profile: HealthProfile(fullName: 'Ayesha'));
    case 'step3':
      return Step3FitnessGoals(profile: HealthProfile(fullName: 'Ayesha'));
    case 'classification':
      return const HealthClassification();
    case 'bmi':
      return BmiResult(profile: UserSession.instance.profile!);
    case 'camera':
      return CameraDetection(
        request: const WorkoutSessionRequest(
          exercise: SessionExercise(id: 'squat', name: 'Bodyweight Squat', sets: 3, reps: 10),
        ),
      );
    case 'manual':
      return ManualGuidance(
        request: const WorkoutSessionRequest(
          exercise: SessionExercise(id: 'squat', name: 'Bodyweight Squat', sets: 3, reps: 10),
        ),
      );
    case 'feedback':
      return PostureFeedbackScreen(
        summary: SessionSummary(
          exercise: const SessionExercise(id: 'squat', name: 'Bodyweight Squat', sets: 3, reps: 10),
          mode: SessionMode.camera,
          endedAt: DateTime.now(),
          duration: const Duration(minutes: 5, seconds: 12),
          reps: 10,
          partialReps: 1,
          setsCompleted: 3,
          postureScore: 85,
          accuracy: 90,
          feedback: const [
            FormFeedbackItem(id: '1', verdict: FeedbackVerdict.passed, text: 'Good squat depth reached'),
            FormFeedbackItem(id: '2', verdict: FeedbackVerdict.passed, text: 'Back kept straight'),
          ],
        ),
      );
    case 'scan':
      return FoodScanScreen(date: DateTime.now());
    case 'drawer':
      return Scaffold(appBar: AppBar(title: const Text('Menu preview')), drawer: AppDrawer(onSelectTab: (_) {}), body: const SizedBox.expand());
    default:
      return const MainNavigation();
  }
}

final _demoSpecialists = [
  const Specialist(id: 'd1', name: 'Hina Malik', type: SpecialistType.doctor, specialty: 'General medicine', yearsOfExperience: 12, rating: 4.9, reviewCount: 128, videoFee: 2500, chatFee: 1500, emergency: true),
  const Specialist(id: 'n1', name: 'Sara Khan', type: SpecialistType.nutritionist, specialty: 'Sports nutrition', yearsOfExperience: 7, rating: 4.7, reviewCount: 64, videoFee: 2000, chatFee: 1200),
  const Specialist(id: 't1', name: 'Ali Raza', type: SpecialistType.trainer, specialty: 'Strength and mobility', yearsOfExperience: 5, rating: 0, reviewCount: 0, videoFee: 1500, chatFee: 900),
];

Future<Appointment> _demoBook({required Specialist specialist, required DateTime slot, required ConsultType type, required SharePrefs shares, required String notes}) async =>
    _demoAppointments.first;

final _demoAppointments = [
  Appointment(
    id: 'a1',
    patientId: 'me',
    patientName: 'Ayesha',
    specialistId: 'd1',
    specialistName: 'Dr. Hina Malik',
    role: SpecialistType.doctor,
    specialty: 'General medicine',
    startAt: DateTime.now().add(const Duration(days: 1)),
    durationMinutes: 30,
    type: ConsultType.video,
    fee: 2500,
    meetingLink: 'https://meet.jit.si/baymax-demo',
    createdAt: DateTime.now(),
  ),
  Appointment(
    id: 'a0',
    patientId: 'me',
    patientName: 'Ayesha',
    specialistId: 'n1',
    specialistName: 'Sara Khan',
    role: SpecialistType.nutritionist,
    specialty: 'Sports nutrition',
    startAt: DateTime.now().subtract(const Duration(days: 4)),
    durationMinutes: 30,
    type: ConsultType.chat,
    status: AppointmentStatus.completed,
    fee: 1200,
    meetingLink: 'https://meet.jit.si/baymax-demo2',
    createdAt: DateTime.now().subtract(const Duration(days: 6)),
    consultation: ConsultationNote(notes: 'Add a protein source to breakfast and keep your water intake above 2 litres.', updatedAt: DateTime.now().subtract(const Duration(days: 4))),
  ),
];

const _names = [
  'home', 'diet', 'workout', 'analytics', 'profile', 'community', 'calorie', 'body', 'specialists', 'appointments', 'payment', 'settings', 'nutrition', 'sources', 'chatbot', 'allergy',
  'posture', 'voice', 'exercise', 'login', 'signup', 'splash', 'step1', 'step2', 'step3', 'classification', 'bmi', 'drawer',
  'camera', 'manual', 'feedback', 'scan',
];

class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GridView.count(
          crossAxisCount: 3,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: [
            for (final n in _names)
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.all(4)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _screen(n))),
                child: Text(n, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  RealtimeDb.init();
  await UserSession.instance.setProfile(HealthProfile(
    fullName: 'Ayesha Malik',
    dob: '1999-04-12',
    gender: 'Female',
    heightValue: 162,
    weightValue: 58,
    medicalConditions: const [],
    foodAllergies: const ['Nuts'],
    primaryGoal: 'Maintain & Stay Fit',
    activityLevel: 'Moderately Active',
    workoutFrequency: 4,
    targetWeightValue: 56,
  ));
  const name = String.fromEnvironment('PREVIEW_SCREEN', defaultValue: 'launcher');
  runApp(MaterialApp(
    title: 'Baymax preview',
    theme: AppTheme.lightTheme,
    builder: baymaxShell,
    home: name == 'launcher' ? const _Launcher() : _screen(name),
    debugShowCheckedModeBanner: false,
  ));
}

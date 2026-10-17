import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/health_profile.dart';
import '../models/plan.dart';
import '../models/workout_readiness.dart';
import 'api_client.dart';
import 'calorie_optimizer.dart';
import 'food_log_service.dart';
import 'weight_service.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'gamification.dart' show UserRole;
import 'food_database.dart';
import 'health_classifier.dart';
import 'ml/gradient_boosting_model.dart';
import 'ml/health_risk_model.dart';
import 'notification_service.dart';
import 'plan_generator.dart';
import 'profile_service.dart';
import 'workout_readiness_service.dart';
import 'workout_session/workout_log_service.dart';
import 'role_service.dart';

/// Holds the signed-in user's profile and everything derived from it
/// (classification → plan) so every screen shares one source of truth.
class UserSession extends ChangeNotifier {
  UserSession._();
  static final UserSession instance = UserSession._();

  /// Phase 2: swap in the Logistic Regression classifier here.
  HealthClassifier classifier = const RuleBasedClassifier();

  HealthProfile? profile;

  /// Exercises the user recently marked "Too Difficult" (report FR17.4);
  /// the plan generator makes them easier.
  final Set<String> tooDifficult = {};
  ClassificationResult? classification;
  PersonalizedPlan? plan;

  /// Module 4: the pre-exercise readiness answers (equipment, injuries, warning symptoms, doctor's clearance). Until they
  /// are answered, people with a heart condition get no plan and everyone else gets the curated body-weight plan.
  WorkoutReadiness readiness = WorkoutReadiness.unanswered;
  WorkoutReadinessStore readinessStore = FirebaseWorkoutReadinessStore.instance;

  /// True once the profile came from the signed-in account (not a local preview or test), so the plan may be stored.
  bool _fromAccount = false;

  /// Module 3 (FR-4): what the user's own weight and food logs say about their maintenance calories (null until first computed).
  CalorieEstimate? calorieEstimate;

  /// Module 14 (FR-2): the user's role; a plain member unless an administrator set another one.
  UserRole role = UserRole.user;

  bool get hasProfile => profile != null;

  static bool _modelsTried = false;

  /// Phase 2: Gradient Boosting workout-calorie model (only present if it beat the MET baseline).
  WorkoutCalorieModel? workoutModel;

  /// Phase 2: use the trained Logistic Regression when its file is bundled with the app.
  /// Without it the app keeps using the rule-based classifier alone.
  Future<void> _loadModels() async {
    if (_modelsTried) return;
    _modelsTried = true;
    try {
      final json = await rootBundle.loadString('assets/models/health_classifier.json');
      classifier = HybridHealthClassifier(const RuleBasedClassifier(), HealthRiskModel.fromJsonString(json));
    } catch (_) {
      // Model asset missing or unreadable: rule-based classification only.
    }
    try {
      final json = await rootBundle.loadString('assets/models/calorie_gb.json');
      workoutModel = WorkoutCalorieModel(GradientBoostingModel.fromJsonString(json));
    } catch (_) {
      // No calorie model bundled: workout calories use the Compendium MET estimate.
    }
  }

  /// Loads the profile from the server. Returns false if the user has none yet.
  Future<bool> load() async {
    final data = await ProfileService.instance.fetchMine();
    if (data == null) {
      _reset();
      notifyListeners();
      return false;
    }
    try {
      tooDifficult
        ..clear()
        ..addAll(await FirebaseWorkoutLog.instance.tooDifficultExercises());
    } catch (_) {
      // Not critical: the plan is generated without difficulty adjustments.
    }
    try {
      readiness = await readinessStore.load() ?? WorkoutReadiness.unanswered;
    } catch (_) {
      // Offline: keep the last answers this session had (unanswered on a cold start — the conservative choice).
    }
    _fromAccount = true;
    await setProfile(HealthProfile.fromJson(data));
    role = await RoleService.instance.fetchMine();
    notifyListeners();
    refreshCalorieEstimate(); // personalises the target in the background
    return true;
  }

  /// Use after profiling completes (or after any profile change).
  Future<void> setProfile(HealthProfile p) async {
    await _loadModels();
    final results = await Future.wait([FoodDatabase.load(), ExerciseLibrary.load(), _loadCatalog()]);
    final foods = results.first as FoodDatabase;
    profile = p;
    classification = classifier.classify(p);
    p.healthClassification = classification!.category;
    // An estimate built on a different weight/activity level no longer applies.
    final est = calorieEstimate;
    if (est != null && (est.priorTdee - p.tdee).abs() > 1) calorieEstimate = null;
    plan = _generate(foods, p, classification!);
    notifyListeners();
  }

  PersonalizedPlan _generate(FoodDatabase foods, HealthProfile p, ClassificationResult c) {
    final generated = PlanGenerator(foods, workoutModel: workoutModel, optimizer: AdaptiveCalorieOptimizer(calorieEstimate))
        .generate(p, c, variant: p.planVariant, tooDifficult: tooDifficult, readiness: readiness);
    if (_fromAccount) _storeSnapshot(generated, p);
    return generated;
  }

  /// Module 4: keeps a versioned copy of the current plan in the account. Best effort, never blocks the UI.
  void _storeSnapshot(PersonalizedPlan generated, HealthProfile p) {
    final snapshot = WorkoutPlanSnapshot.build(
      plan: generated,
      goal: p.primaryGoal,
      catalogCommit: ExerciseCatalog.datasetCommit,
      profileUpdatedAt: 0,
      weightKg: p.weightKg,
    );
    readinessStore.savePlanSnapshot(snapshot).catchError((_) => false);
  }

  /// The catalogue is optional for planning: without it only the curated library is used.
  static Future<void> _loadCatalog() async {
    try {
      await ExerciseCatalog.load();
    } catch (_) {
      // Asset missing or unreadable.
    }
  }

  /// Module 4: saves new readiness answers and regenerates the plan with them. Throws [ApiException] if saving fails
  /// (the answers still apply for this session).
  Future<void> saveReadiness(WorkoutReadiness r) async {
    readiness = r;
    final p = profile;
    if (p != null) await setProfile(p);
    await readinessStore.save(r);
  }

  Future<void> _rebuildPlan() async {
    final p = profile, c = classification;
    if (p == null || c == null) return;
    final foods = await FoodDatabase.load();
    plan = _generate(foods, p, c);
  }

  /// Module 3, FR-4: reads the last 28 days of weigh-ins and food logs, updates [calorieEstimate] and rebuilds the plan so the
  /// calorie target and meal plan follow it. Best effort: offline or signed out, the previous estimate is kept.
  Future<void> refreshCalorieEstimate({DateTime? today}) async {
    final p = profile;
    if (p == null) return;
    final blocked = CalorieOptimizerRules.adaptationBlockedReason(p);
    if (blocked != null) {
      calorieEstimate = CalorieEstimate.disabled(p.tdee, blocked);
    } else {
      try {
        final t = DateTime(today?.year ?? DateTime.now().year, today?.month ?? DateTime.now().month, today?.day ?? DateTime.now().day);
        final from = FoodLogService.dateKey(t.subtract(const Duration(days: CalorieOptimizerRules.windowDays - 1)));
        final to = FoodLogService.dateKey(t);
        final weights = await WeightService.instance.range(from, to);
        final kcal = await FoodLogService.instance.kcalByDate(from, to);
        final intake = <IntakeDay>[
          for (final e in kcal.entries)
            if (DateTime.tryParse(e.key) != null) IntakeDay(DateTime.parse(e.key), e.value),
        ];
        calorieEstimate = estimateMaintenance(priorTdee: p.tdee, bmr: p.bmr, weights: weights, intake: intake, today: t);
      } catch (_) {
        return; // keep whatever we had
      }
    }
    await _rebuildPlan();
    notifyListeners();
  }

  /// Saves today's weight, keeps the profile's weight current (BMI, BMR and macros depend on it), and recomputes the target.
  Future<void> logWeight(double kg, {DateTime? date}) async {
    final p = profile;
    if (p == null) throw const ApiException('Complete your health profile first.');
    final day = date ?? DateTime.now();
    await WeightService.instance.set(day, kg);
    final isToday = DateTime(day.year, day.month, day.day) == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (isToday) {
      p.weightValue = p.weightUnit == 'lbs' ? kg / 0.45359237 : kg;
      await setProfile(p);
      try {
        await ProfileService.instance.saveMine(p);
      } finally {
        await refreshCalorieEstimate(); // the weigh-in itself is saved either way
      }
    } else {
      await refreshCalorieEstimate();
    }
  }

  /// Module 3, FE-7. Returns false if the new variant could not be saved
  /// (the new plan is still shown locally).
  Future<bool> regeneratePlan() async {
    final p = profile;
    if (p == null) return false;
    p.planVariant += 1;
    await setProfile(p);
    try {
      await ProfileService.instance.saveMine(p);
      return true;
    } on ApiException {
      return false;
    }
  }

  void clear() {
    // Reminders belong to the person who signed out.
    NotificationService.instance.cancelAll();
    _reset();
    notifyListeners();
  }

  void _reset() {
    profile = null;
    tooDifficult.clear();
    classification = null;
    plan = null;
    calorieEstimate = null;
    role = UserRole.user;
    readiness = WorkoutReadiness.unanswered;
    _fromAccount = false;
  }
}

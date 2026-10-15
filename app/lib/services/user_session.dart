import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/health_profile.dart';
import '../models/plan.dart';
import 'api_client.dart';
import 'exercise_library.dart';
import 'food_database.dart';
import 'health_classifier.dart';
import 'ml/gradient_boosting_model.dart';
import 'ml/health_risk_model.dart';
import 'plan_generator.dart';
import 'profile_service.dart';
import 'workout_session/workout_log_service.dart';

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
    await setProfile(HealthProfile.fromJson(data));
    return true;
  }

  /// Use after profiling completes (or after any profile change).
  Future<void> setProfile(HealthProfile p) async {
    await _loadModels();
    final results = await Future.wait([FoodDatabase.load(), ExerciseLibrary.load()]);
    final foods = results.first as FoodDatabase;
    profile = p;
    classification = classifier.classify(p);
    p.healthClassification = classification!.category;
    plan = PlanGenerator(foods, workoutModel: workoutModel).generate(p, classification!, variant: p.planVariant, tooDifficult: tooDifficult);
    notifyListeners();
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
    _reset();
    notifyListeners();
  }

  void _reset() {
    profile = null;
    tooDifficult.clear();
    classification = null;
    plan = null;
  }
}

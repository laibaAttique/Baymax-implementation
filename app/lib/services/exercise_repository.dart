import '../models/movement_pattern.dart';
import '../models/plan.dart';
import 'exercise_catalog.dart';
import 'exercise_library.dart';
import 'posture/movement_patterns.dart';

/// One catalogue entry with everything the workout generator (Module 4) and posture detection (Module 5) need, under
/// a single canonical id. The original free-exercise-db record is never changed: dataset fields stay under `dataset`
/// in the catalogue file, Baymax metadata (MET, safety tags, movement pattern) sits beside it.
class CatalogEntry {
  final Exercise exercise;
  final ExercisePostureConfig posture;
  const CatalogEntry(this.exercise, this.posture);

  String get id => exercise.id;

  /// `baymax` (curated) or `free-exercise-db`.
  String get source => exercise.source;
  MovementPattern get movementPattern => posture.movementPattern;
  String get postureConfigId => posture.configId;
  CameraSupportLevel get postureCapability => posture.level;

  /// What the safety rules key on for this exercise (they decide eligibility per person; nothing here is a verdict).
  List<String> get safetyTags => [
        'impact:${exercise.impact}',
        for (final t in exercise.tags) 'tag:$t',
        for (final j in exercise.joints) 'joint:$j',
        'level:${exercise.level}',
      ];

  Map<String, Object?> toJson() => {
        'id': id,
        'name': exercise.name,
        'source': source,
        'difficulty': exercise.levelLabel,
        'category': exercise.category.isEmpty ? exercise.group : exercise.category,
        'muscles': exercise.muscles,
        'equipment': exercise.equipmentKey,
        'instructions': exercise.steps.length,
        'images': ExerciseCatalog.imagesFor(exercise).length,
        'movementPattern': movementPattern.name,
        'postureConfigId': postureConfigId,
        'postureCapability': postureCapability.name,
        'metValue': exercise.hasMet ? exercise.met : null,
        'safetyTags': safetyTags,
      };
}

/// The unified exercise catalogue: the curated Baymax library plus the free-exercise-db entries that are not already
/// represented by a curated exercise (no duplicates). Both modules resolve exercises through here.
class ExerciseRepository {
  ExerciseRepository._();

  /// Any exercise by its canonical id (curated id or dataset id).
  static Exercise? byId(String id) => ExerciseLibrary.byId(id) ?? ExerciseCatalog.byId(id);

  static List<Exercise> get all => [...ExerciseLibrary.all, ...ExerciseCatalog.uncurated];

  static ExercisePostureConfig postureFor(Exercise e) => MovementPatterns.resolve(e.id, e.movement, e.noTrackingReason);

  static CatalogEntry entry(Exercise e) => CatalogEntry(e, postureFor(e));

  static List<CatalogEntry> get entries => [for (final e in all) entry(e)];
}

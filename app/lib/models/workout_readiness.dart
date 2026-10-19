/// Pre-exercise readiness answers (Module 4). They fill the safety information the health profile does not collect: what
/// equipment the person has, current injuries, warning symptoms and whether a doctor has cleared them for exercise.
///
/// The symptom questions follow the topics of the PAR-Q+ general health questions (Warburton et al., 2011) and the
/// ACSM pre-participation screening (Riebe et al., 2015), reworded; they are a screening aid, not a diagnosis.
class WorkoutReadiness {
  /// False until the person has answered the questions at least once.
  final bool answered;

  /// Equipment keys the person owns (see [equipmentOptions]). Body weight is always available.
  final Set<String> equipment;

  /// Body regions with a current injury or pain that limits movement (see [injuryOptions]).
  final Set<String> injuries;

  /// Warning symptoms reported (see [symptomOptions]); empty means "none of these".
  final Set<String> symptoms;

  /// Whether a doctor has said exercise is safe for them: true, false, or null for "not sure / not asked".
  final bool? clearance;

  /// When the answers were last saved (ms since epoch), if known.
  final int? updatedAt;

  const WorkoutReadiness({
    this.answered = true,
    this.equipment = const {},
    this.injuries = const {},
    this.symptoms = const {},
    this.clearance,
    this.updatedAt,
  });

  static const unanswered = WorkoutReadiness(answered: false);

  static const equipmentOptions = {
    'dumbbell': 'Dumbbells',
    'kettlebell': 'Kettlebell',
    'bands': 'Resistance bands',
    'barbell': 'Barbell and plates',
    'ez_bar': 'EZ curl bar',
    'medicine_ball': 'Medicine ball',
    'exercise_ball': 'Exercise (Swiss) ball',
    'cable': 'Cable machine (gym)',
    'machine': 'Weight machines (gym)',
  };

  static const injuryOptions = {
    'knee': 'Knee',
    'lowerBack': 'Lower back',
    'shoulder': 'Shoulder',
    'wrist': 'Wrist',
    'ankle': 'Ankle',
  };

  static const symptomOptions = {
    'chestPain': 'Chest pain or pressure, at rest or when I am active',
    'dizziness': 'Fainting, or losing my balance because of dizziness, in the last 12 months',
    'breathless': 'Unusual shortness of breath with light effort',
    'doctorAdvisedAgainst': 'A doctor has told me to avoid or limit physical activity',
  };

  Map<String, dynamic> toJson() => {
        'equipment': {for (final e in equipment) e: true},
        'injuries': {for (final i in injuries) i: true},
        'symptoms': {for (final s in symptoms) s: true},
        if (clearance != null) 'clearance': clearance,
      };

  /// From the database. Unknown keys are ignored so an older app cannot misread a newer answer.
  factory WorkoutReadiness.fromJson(Map<String, dynamic> j) {
    Set<String> keys(dynamic v, Map<String, String> allowed) =>
        v is Map ? {for (final e in v.entries) if (e.value == true && allowed.containsKey(e.key)) e.key.toString()} : <String>{};
    return WorkoutReadiness(
      equipment: keys(j['equipment'], equipmentOptions),
      injuries: keys(j['injuries'], injuryOptions),
      symptoms: keys(j['symptoms'], symptomOptions),
      clearance: j['clearance'] as bool?,
      updatedAt: (j['updatedAt'] as num?)?.toInt(),
    );
  }
}

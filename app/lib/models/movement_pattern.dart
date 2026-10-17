/// How an exercise moves, as far as camera tracking is concerned (Module 5). One pattern per exercise.
///
/// Dataset (free-exercise-db) exercises get theirs from `ml/exercise_catalog/movement_patterns.py` at import time,
/// keyed by the dataset's stable id; curated exercises from [curatedMovements] below, assigned by hand. Two exercises
/// that train the same muscles can have different patterns (a squat and a leg extension both train the quadriceps).
enum MovementPattern {
  squat('Squat', 'knee bend'),
  lunge('Lunge', 'front-knee bend'),
  hinge('Hip hinge', 'hip bend'),
  hipExtension('Hip extension', 'hip lift'),
  pushup('Push-up', 'elbow bend'),
  benchPress('Chest press', 'elbow bend'),
  dip('Dip', 'elbow bend'),
  overheadPress('Overhead press', 'elbow straightening'),
  armRaise('Arm raise', 'arm lift'),
  row('Row', 'elbow bend'),
  pulldown('Vertical pull', 'elbow bend'),
  curl('Biceps curl', 'elbow bend'),
  tricepsExtension('Triceps extension', 'elbow bend'),
  tricepsPushdown('Triceps pushdown / kickback', 'elbow straightening'),
  legExtension('Leg extension', 'knee straightening'),
  legCurl('Leg curl', 'knee bend'),
  sitUp('Sit-up', 'hip bend'),
  legRaise('Leg raise', 'hip bend'),
  kneeLift('Knee lift', 'knee lift'),
  jumpingJack('Jumping jack', 'arm swing'),
  plankHold('Plank hold', 'body line'),
  wallSitHold('Wall sit hold', 'knee angle'),
  none('No camera tracking', '');

  final String label;

  /// What the camera measures for this pattern, in plain words.
  final String measures;
  const MovementPattern(this.label, this.measures);

  static MovementPattern? byName(String? name) => MovementPattern.values.where((p) => p.name == name).firstOrNull;
}

/// Why an exercise has no camera tracking. Shown to the user, who is offered Manual Guidance instead.
enum NoTrackingReason {
  stretch('Stretches and mobility moves are held in many different positions, so there is no single movement the camera could follow reliably.'),
  machineCardio('This is machine or travelling cardio; your body is partly hidden or moves out of the frame.'),
  locomotion('You move around (walking, stepping or carrying), so you would leave the camera frame.'),
  smallMovement('The movement is too small for the camera to measure reliably (for example wrists, calves, shoulder shrugs or a crunch).'),
  rotation('Twisting and side-bending movements cannot be measured reliably from one camera angle.'),
  complex('This exercise combines several fast phases (jumps, throws, cleans), which one joint angle cannot follow reliably.'),
  alternating('Fast alternating limbs on the floor cannot be separated reliably from one camera angle.'),
  sequence('This is a sequence of different movements, so there is no single movement to track.'),
  noTracker('No camera tracker has been built for this movement yet.');

  final String text;
  const NoTrackingReason(this.text);

  static NoTrackingReason? byName(String? name) => NoTrackingReason.values.where((r) => r.name == name).firstOrNull;
}

/// The curated library (assets/data/exercises.json), mapped by hand. Ids not listed have no camera tracking.
const curatedMovements = <String, MovementPattern>{
  'squat': MovementPattern.squat,
  'chair_squat': MovementPattern.squat,
  'jump_squats': MovementPattern.squat,
  'lunge': MovementPattern.lunge,
  'split_jump': MovementPattern.lunge,
  'glute_bridge': MovementPattern.hipExtension,
  'single_leg_bridge': MovementPattern.hipExtension,
  'wall_sit': MovementPattern.wallSitHold,
  'pushup': MovementPattern.pushup,
  'knee_pushup': MovementPattern.pushup,
  'wall_pushup': MovementPattern.pushup,
  'incline_pushup': MovementPattern.pushup,
  'incline_pushup_wide': MovementPattern.pushup,
  'incline_pushup_close': MovementPattern.pushup,
  'pushup_wide': MovementPattern.pushup,
  'pushup_close': MovementPattern.pushup,
  'tricep_dip': MovementPattern.dip,
  'plank': MovementPattern.plankHold,
  'side_plank_knee': MovementPattern.plankHold,
  'leg_raise': MovementPattern.legRaise,
  'hip_raise_bent_knee': MovementPattern.legRaise,
  'jumping_jacks': MovementPattern.jumpingJack,
  'star_jump': MovementPattern.jumpingJack,
  'march': MovementPattern.kneeLift,
  'high_knees': MovementPattern.kneeLift,
};

/// Reasons for the curated exercises that have no camera tracking.
const curatedNoTracking = <String, NoTrackingReason>{
  'warmup': NoTrackingReason.sequence,
  'cooldown': NoTrackingReason.sequence,
  'brisk_walk': NoTrackingReason.locomotion,
  'step_ups': NoTrackingReason.locomotion,
  'shadow_boxing': NoTrackingReason.complex,
  'mountain_climbers': NoTrackingReason.alternating,
  'spider_crawl': NoTrackingReason.alternating,
  'burpees': NoTrackingReason.complex,
  'calf_raise': NoTrackingReason.smallMovement,
  'shoulder_taps': NoTrackingReason.alternating,
  'superman': NoTrackingReason.smallMovement,
  'bird_dog': NoTrackingReason.alternating,
  'reverse_snow_angel': NoTrackingReason.smallMovement,
  'dead_bug': NoTrackingReason.alternating,
  'bicycle_crunch': NoTrackingReason.rotation,
  'crunch': NoTrackingReason.smallMovement,
  'reverse_crunch': NoTrackingReason.smallMovement,
  'oblique_crunch_floor': NoTrackingReason.rotation,
  'cross_body_crunch': NoTrackingReason.rotation,
  'heel_touches': NoTrackingReason.rotation,
  'russian_twist': NoTrackingReason.rotation,
  'glute_kickback': NoTrackingReason.noTracker,
  'single_leg_balance': NoTrackingReason.noTracker,
};

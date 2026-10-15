import '../models/health_profile.dart';
import '../models/plan.dart';

/// Module 3 (FR-2, FR-3): chooses which exercises a person gets, from their own body parameters and answers.
///
/// Safety is not decided here: the medical rules in `PlanGenerator` first remove every exercise that is not allowed for the
/// person (conditions, BMI, age). This class then RANKS what is left by how well each exercise suits them, and explains each pick.
///
/// The weights below are design choices of the project team. They are not taken from a published formula and have not been
/// reviewed by a trainer or physiotherapist; the Sources screen says so.

/// The inputs the ranking uses, all from the profiling questions.
class BodyProfile {
  final int age;
  final double heightCm;
  final double weightKg;
  final double bmi;
  final String activityLevel;
  final String goal;
  final int workoutsPerWeek;

  const BodyProfile({
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.bmi,
    required this.activityLevel,
    required this.goal,
    required this.workoutsPerWeek,
  });

  factory BodyProfile.from(HealthProfile p) => BodyProfile(
        age: p.ageForCalc,
        heightCm: p.heightCm,
        weightKg: p.weightKg,
        bmi: p.bmi,
        activityLevel: p.activityLevel,
        goal: p.primaryGoal,
        workoutsPerWeek: p.workoutFrequency,
      );

  /// How much exercise the person can handle, 1.0 (beginner) to 3.0 (advanced). From self-reported activity level, lowered a little
  /// for age 50+ and for a high BMI (both make the same exercise harder to recover from).
  double get capacity {
    var c = switch (activityLevel) {
      'Sedentary' => 1.0,
      'Lightly Active' => 1.5,
      'Moderately Active' => 2.0,
      'Very Active' => 2.5,
      'Athlete' => 3.0,
      _ => 1.5,
    };
    if (age >= 65) {
      c -= 0.5;
    } else if (age >= 50) {
      c -= 0.25;
    }
    if (bmi >= 35) {
      c -= 0.5;
    } else if (bmi >= 30) {
      c -= 0.25;
    }
    return c.clamp(1.0, 3.0);
  }

  /// How much a movement that loads this joint should count against the exercise for this person (0 = not at all).
  double jointLoad(String joint) {
    switch (joint) {
      case 'knee':
        return (bmi >= 30 ? 0.8 : (bmi >= 27.5 ? 0.4 : 0.0)) + (age >= 60 ? 0.3 : 0.0);
      case 'ankle':
        return bmi >= 30 ? 0.3 : 0.0;
      case 'wrist':
      case 'shoulder':
        return bmi >= 35 ? 0.3 : 0.0; // arms carrying a larger share of a heavier body
      case 'lowerBack':
        return age >= 60 ? 0.3 : 0.0;
      default:
        return 0.0;
    }
  }
}

/// Maps the library's muscle labels (which differ between sources: Quads / Quadriceps, Abs / Core ...) to common body regions,
/// so a session's trained muscles can be matched to stretches.
Set<String> bodyRegions(Iterable<String> muscles) {
  const map = {
    'legs': ['quads', 'hamstrings', 'glutes', 'calves'],
    'quadriceps': ['quads'],
    'quads': ['quads'],
    'hamstrings': ['hamstrings'],
    'glutes': ['glutes'],
    'calves': ['calves'],
    'ankles': ['calves'],
    'core': ['core'],
    'abs': ['core'],
    'chest': ['chest'],
    'shoulders': ['shoulders'],
    'triceps': ['triceps'],
    'arms': ['triceps', 'shoulders'],
    'forearms': ['forearms'],
    'lower back': ['lowerBack'],
    'upper back': ['upperBack'],
    'middle back': ['upperBack'],
    'back': ['upperBack'],
    'traps': ['upperBack'],
    'hips': ['hips'],
    'inner thighs': ['hips'],
  };
  return {for (final m in muscles) ...?map[m.toLowerCase()]};
}

class ScoredExercise {
  final Exercise exercise;
  final double score;
  final List<String> reasons;
  const ScoredExercise(this.exercise, this.score, this.reasons);
}

class ExerciseSelector {
  final BodyProfile body;

  /// Regenerating the plan changes this; it only breaks ties between similarly good exercises.
  final int variant;

  const ExerciseSelector(this.body, {this.variant = 0});

  // --- weights (team design choices) ---
  static const tooHardPenalty = 2.0; // per level above the person's capacity
  static const tooEasyPenalty = 0.8; // per level below it
  static const metWeight = 0.12; // weight-loss goal: favours higher energy use
  static const strengthBonus = 0.5; // muscle-gain goal: push / legs / back
  static const compoundBonusGain = 0.3;
  static const compoundBonusMaintain = 0.2;
  static const floorPenalty = 0.6; // age 65+ or BMI 35+: getting down to and up from the floor
  static const complexityPenalty = 0.4; // per step above 1, age 60+
  static const repeatPenalty = 0.9; // per time the exercise was already used this week
  static const jitter = 0.35; // maximum tie-break noise

  /// A fixed pseudo-random number in [0, jitter) for this exercise and variant (same inputs -> same plan).
  double _tieBreak(String id) {
    var h = 17 + variant * 7919;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h % 1000) / 1000 * jitter;
  }

  ScoredExercise score(Exercise e, {Map<String, int> weekUsage = const {}}) {
    final c = body.capacity;
    final reasons = <String>[];
    var s = 0.0;

    // 1. difficulty fit
    final diff = e.level - c;
    s -= diff > 0 ? tooHardPenalty * diff : tooEasyPenalty * -diff;
    if (diff.abs() <= 0.5) {
      reasons.add('Matches your current fitness level');
    } else if (diff < -0.5) {
      reasons.add('A comfortable start while you build up');
    }

    // 2. goal fit
    switch (body.goal) {
      case 'Lose Weight':
        s += metWeight * e.met;
        if (e.met >= 3.8 && e.group != 'mobility') reasons.add('Uses more energy, which supports your weight-loss goal');
        break;
      case 'Gain Muscle':
        if (e.group == 'push' || e.group == 'legs' || e.group == 'back') {
          s += strengthBonus;
          reasons.add('Builds muscle, which supports your muscle-gain goal');
        }
        if (e.mechanic == 'compound') s += compoundBonusGain;
        break;
      default:
        if (e.mechanic == 'compound') s += compoundBonusMaintain;
    }

    // 3. joint comfort for this body
    var jointCost = 0.0;
    for (final j in e.joints) {
      jointCost += body.jointLoad(j);
    }
    s -= jointCost;
    if (jointCost == 0 && e.joints.isEmpty && (body.bmi >= 27.5 || body.age >= 60) && e.group != 'mobility') {
      reasons.add(body.bmi >= 27.5 ? 'Easy on your joints at your current weight' : 'Gentle on your joints');
    }

    // 4. getting down to and up from the floor
    if (e.position == 'floor' && (body.age >= 65 || body.bmi >= 35)) {
      s -= floorPenalty;
    } else if (e.position != 'floor' && (body.age >= 65 || body.bmi >= 35)) {
      reasons.add('Done standing or seated, so no getting down to the floor');
    }

    // 5. coordination demand for older adults
    if (body.age >= 60 && e.complexity > 1) s -= complexityPenalty * (e.complexity - 1);

    // 6. variety across the week
    final used = weekUsage[e.id] ?? 0;
    s -= repeatPenalty * used;
    if (used == 0 && weekUsage.isNotEmpty) reasons.add('New this week, for variety');

    s += _tieBreak(e.id);
    if (e.tags.contains('balance') && body.age >= 65) reasons.insert(0, 'Balance training is recommended from age 65');
    return ScoredExercise(e, s, reasons.take(2).toList());
  }

  /// [candidates] must already satisfy the safety rules. Best first.
  List<ScoredExercise> rank(Iterable<Exercise> candidates, {Map<String, int> weekUsage = const {}}) {
    final out = [for (final e in candidates) score(e, weekUsage: weekUsage)];
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.exercise.id.compareTo(b.exercise.id);
    });
    return out;
  }
}

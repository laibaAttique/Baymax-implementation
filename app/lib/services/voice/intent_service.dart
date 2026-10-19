import '../../models/plan.dart';
import '../../utils/fuzzy.dart';
import '../exercise_library.dart';

/// What the user wants from the voice coach (Module 6, FR-2 / FR-7).
enum CoachIntent {
  painOrSymptom,
  confirmYes,
  confirmNo,
  stopSession,
  pauseSession,
  resumeSession,
  repCount,
  postureFeedback,
  postureScore,
  sessionTime,
  nextExercise,
  schedule,
  exerciseTechnique,
  currentExercise,
  startWorkout,
  generalGuidance,
  help,
  greeting,
  unknown,
}

class IntentResult {
  final CoachIntent intent;

  /// Library exercise named in the utterance, if any.
  final Exercise? exercise;

  /// Topic for [CoachIntent.generalGuidance]: breathing | rest | warmup | hydration | motivation.
  final String? topic;
  final String utterance;

  /// Which engine recognised it, shown to the user.
  final String engine;

  /// 0..1 when the engine reports one (Dialogflow); null otherwise.
  final double? confidence;
  const IntentResult(this.intent,
      {this.exercise, this.topic, this.utterance = '', this.engine = '', this.confidence});

  IntentResult copyWith({String? engine, Exercise? exercise}) => IntentResult(
        intent,
        exercise: exercise ?? this.exercise,
        topic: topic,
        utterance: utterance,
        engine: engine ?? this.engine,
        confidence: confidence,
      );
}

/// Intent recognition. The voice assistant only knows this interface.
///
/// Implementations: [RuleBasedIntentService] (on-device) and
/// `DialogflowIntentService` (report FR-2, via the backend), combined by
/// `HybridIntentService`.
abstract class IntentService {
  /// Shown in the UI so it is clear which engine produced the answer.
  String get engineName;
  Future<IntentResult> detect(String utterance);
}

typedef ExerciseLookup = List<Exercise> Function();

/// Local keyword/phrase rules. Used when Dialogflow is not configured or not
/// reachable, and always for safety reports. It is NOT Dialogflow and makes
/// no network calls.
///
/// Rules are checked in priority order: safety first, then session controls,
/// then questions about the live session, then general workout questions.
class RuleBasedIntentService implements IntentService {
  final ExerciseLookup _exercises;

  RuleBasedIntentService({ExerciseLookup? exercises})
      : _exercises = exercises ?? (() => ExerciseLibrary.isLoaded ? ExerciseLibrary.all : const <Exercise>[]);

  @override
  String get engineName => 'On-device rules';

  static final List<(CoachIntent, RegExp)> _rules = [
    (
      CoachIntent.painOrSymptom,
      RegExp(r'\b(pain|painful|hurt|hurts|hurting|injur\w*|dizzy|dizziness|faint\w*|light ?headed|numb\w*|'
          r'chest (tight\w*|discomfort)|can t breathe|cannot breathe|short of breath|sharp|pulled|sprain\w*|nausea\w*)\b'),
    ),
    (
      CoachIntent.stopSession,
      RegExp(r'\b((stop|end|finish|quit) (the |my |this )?(session|workout|exercise|set)|i m done|i am done|stop now)\b'),
    ),
    (CoachIntent.resumeSession, RegExp(r'\b(resume|unpause|continue|carry on|keep going|start again|i m ready)\b')),
    (CoachIntent.pauseSession, RegExp(r'\b(pause|take a break|hold on|give me a (minute|second|moment))\b')),
    (
      CoachIntent.postureScore,
      RegExp(r'\b(score|accuracy|how accurate|rating)\b'),
    ),
    (
      CoachIntent.repCount,
      // "how many squats did I do" counts too, but not "how many sets/minutes/calories".
      RegExp(r'\b(reps?|repetitions?|how many (?!sets?\b|minutes?\b|seconds?\b|calories\b)\w+|count)\b'),
    ),
    (
      CoachIntent.exerciseTechnique,
      RegExp(r'\b(how (do|should|can) (i|you) (do|perform)|how to|technique|instructions?|steps|'
          r'show me how|teach me|explain|form tips?|tips for)\b'),
    ),
    (
      CoachIntent.postureFeedback,
      RegExp(r'\b(form|posture|doing (it |this )?(right|wrong|correctly|ok|okay)|what s wrong|what is wrong|'
          r'what am i doing wrong|correct(ion)?|fix|feedback|my back|my knees)\b'),
    ),
    (CoachIntent.sessionTime, RegExp(r'\b(how long (have|has|did|was)|timer|elapsed|duration|(session|workout) time|how much time)\b')),
    (CoachIntent.nextExercise, RegExp(r'\b(next|after this|coming up|up next)\b')),
    (
      CoachIntent.schedule,
      RegExp(r'\b(schedule|today|todays|plan|routine|my workout|show (me )?(the )?exercises|what exercises)\b'),
    ),
    (
      CoachIntent.currentExercise,
      RegExp(r'\b((what|which) exercise|current exercise|what am i doing|target|how many sets|muscles?)\b'),
    ),
    (CoachIntent.startWorkout, RegExp(r'\b(start|begin|let s go)\b')),
    (CoachIntent.help, RegExp(r'\b(help|what can you do|what can i (ask|say)|commands?)\b')),
    (CoachIntent.greeting, RegExp(r'\b(hi|hello|hey|salam|good (morning|afternoon|evening))\b')),
  ];

  static final List<(String, RegExp)> _topics = [
    ('breathing', RegExp(r'\b(breath\w*|inhale|exhale)\b')),
    ('rest', RegExp(r'\b(rest|recover\w*|between sets|sore\w*)\b')),
    ('warmup', RegExp(r'\b(warm ?up|cool ?down|stretch\w*)\b')),
    ('hydration', RegExp(r'\b(water|hydrat\w*|drink)\b')),
    ('motivation', RegExp(r'\b(tired|exhausted|motivat\w*|give up|can t do|too hard|struggling)\b')),
  ];

  static final RegExp _yes = RegExp(r'^(yes|yeah|yep|yup|sure|ok|okay|confirm|do it|end it|yes end it|yes please)\b');
  static final RegExp _no = RegExp(r'^(no|nope|nah|cancel|never ?mind|don t|do not|no keep going|keep going)\b');

  @override
  Future<IntentResult> detect(String utterance) async {
    final text = Fuzzy.normalize(utterance.replaceAll(RegExp("['’]"), ' '))
        .replaceAll('pushup', 'push up')
        .replaceAll('situp', 'sit up');
    if (text.isEmpty) return IntentResult(CoachIntent.unknown, engine: engineName);
    final exercise = _findExercise(text);

    IntentResult result(CoachIntent intent, {String? topic}) =>
        IntentResult(intent, exercise: exercise, topic: topic, utterance: utterance, engine: engineName);

    if (_rules.first.$2.hasMatch(text)) return result(CoachIntent.painOrSymptom);
    if (_yes.hasMatch(text)) return result(CoachIntent.confirmYes);
    if (_no.hasMatch(text)) return result(CoachIntent.confirmNo);

    for (final (intent, pattern) in _rules.skip(1)) {
      if (!pattern.hasMatch(text)) continue;
      // "start squats" / "plan for push ups": a named exercise with no session
      // question means the user wants to know about that exercise.
      if (exercise != null && (intent == CoachIntent.startWorkout || intent == CoachIntent.currentExercise)) {
        return result(CoachIntent.exerciseTechnique);
      }
      return result(intent);
    }
    for (final (topic, pattern) in _topics) {
      if (pattern.hasMatch(text)) return result(CoachIntent.generalGuidance, topic: topic);
    }
    // Just an exercise name ("squats") is taken as "how do I do it?".
    if (exercise != null) return result(CoachIntent.exerciseTechnique);
    return result(CoachIntent.unknown);
  }

  /// "ups" → "up", "squats" → "squat" (shorter words than Fuzzy.singular handles).
  static String _singular(String w) => w.length > 2 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w;

  static const _genericWords = {'bodyweight', 'hold', 'in', 'place', 'the', 'to', 'a', 'dynamic'};

  /// The library exercise whose name words all appear in [text]; the most
  /// specific match wins ("jump squats" beats "squat").
  Exercise? _findExercise(String text) {
    final spoken = Fuzzy.tokens(text).map(_singular).toSet();
    Exercise? best;
    var bestSize = 0;
    for (final e in _exercises()) {
      // "Sit-to-Stand (Chair Squat)" can be asked for by either name.
      for (final variant in e.name.split(RegExp(r'[()]'))) {
        final words = Fuzzy.tokens(variant).map(_singular).where((w) => !_genericWords.contains(w)).toSet();
        if (words.isEmpty || !spoken.containsAll(words)) continue;
        if (words.length > bestSize) {
          best = e;
          bestSize = words.length;
        }
      }
    }
    return best;
  }
}

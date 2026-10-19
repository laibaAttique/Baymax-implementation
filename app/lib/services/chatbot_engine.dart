import '../models/health_profile.dart';
import '../models/plan.dart';
import '../utils/health_calc.dart';
import '../utils/fuzzy.dart';
import 'calorie_optimizer.dart';
import 'chat_history.dart';
import 'exercise_library.dart';
import 'food_database.dart';
import 'food_parser.dart';
import 'gamification.dart';
import 'health_classifier.dart';
import 'weight_projection.dart';

/// A tappable follow-up under a bot message.
class ChatAction {
  /// diet | workout | nutrition | scanner | consult | profile | sources
  final String type;
  final String label;
  const ChatAction(this.type, this.label);
}

class ChatReply {
  final String text;
  final String intent;
  final List<ChatAction> actions;
  const ChatReply(this.text, this.intent, {this.actions = const []});
}

class ChatContext {
  final HealthProfile? profile;
  final ClassificationResult? classification;
  final PersonalizedPlan? plan;
  final FoodDatabase? db;

  /// Calories logged so far today (used when [history] has no food log).
  final double consumedKcal;
  final DateTime now;

  /// The user's own recent logs: meals, workouts, weigh-ins, streaks, badges. Empty until loaded.
  final ChatHistory history;

  ChatContext({
    this.profile,
    this.classification,
    this.plan,
    this.db,
    this.consumedKcal = 0,
    this.history = ChatHistory.none,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  /// Today's logged calories: from the food log when it was read, otherwise [consumedKcal].
  double get todayKcal {
    final entries = history.entriesOn(now);
    return entries == null ? consumedKcal : entries.fold(0.0, (s, e) => s + e.kcal);
  }

  String get firstName {
    final n = profile?.fullName.trim() ?? '';
    return n.isEmpty ? '' : n.split(' ').first;
  }
}

class _Faq {
  final List<String> keys;
  final String answer;
  final List<ChatAction> actions;
  const _Faq(this.keys, this.answer, [this.actions = const []]);
}

class _FaqHit {
  final _Faq faq;
  final int keyLength;
  const _FaqHit(this.faq, this.keyLength);
}

/// Module 12: rule-based intent detection (FR-1), FAQ answers (FR-2),
/// calorie/workout information (FR-3) and doctor recommendations (FR-4).
class ChatbotEngine {
  const ChatbotEngine();

  static const suggestions = [
    'What should I eat for lunch?',
    "What's my workout today?",
    'How many calories in 2 rotis and daal?',
    'How many calories can I eat?',
    'How do I do a squat?',
  ];

  static const _disclaimer =
      'I can share general fitness and nutrition guidance, but I\'m not a doctor and can\'t diagnose or treat conditions.';

  // Intent keyword tables: phrases weigh 2, single words weigh 1.
  static const _intents = <String, List<String>>{
    'greeting': ['hi', 'hello', 'hey', 'salam', 'assalam o alaikum', 'assalamualaikum', 'good morning', 'good evening', 'good afternoon'],
    'thanks': ['thanks', 'thank you', 'thx', 'shukriya', 'jazakallah'],
    'bye': ['bye', 'goodbye', 'see you', 'allah hafiz'],
    'bmi': ['my bmi', 'current bmi', 'check bmi', 'calculate bmi', 'tell me my bmi', 'my weight status'],
    'bmr': ['my bmr', 'current bmr', 'calculate bmr', 'my metabolic rate', 'my resting calories'],
    'calorie_target': [
      'calorie target', 'daily calories', 'calorie goal', 'calories should i eat', 'calories can i eat',
      'calories do i need', 'calories per day', 'maintenance calories', 'tdee', 'calorie intake',
    ],
    'remaining': [
      'calories left', 'calories remaining', 'remaining calories', 'eaten today', 'consumed today',
      'how much have i eaten', 'calories so far', 'today intake',
    ],
    'workout_today': [
      'workout today', "today's workout", 'todays workout', 'exercise today', 'train today',
      'what should i do today', 'my workout', 'gym today',
    ],
    'workout_plan': ['workout plan', 'weekly plan', 'weekly schedule', 'exercise plan', 'training plan', 'routine', 'schedule'],
    'meal': [
      'what should i eat', 'what to eat', 'meal idea', 'meal suggestion', 'suggest a meal', 'suggest meal',
      'recommend food', 'food suggestion', 'diet plan', 'meal plan', 'what can i eat', 'something to eat', 'what should i have',
    ],
    'can_eat': ['can i eat', 'can i have', 'am i allowed', 'is it ok to eat', 'is it safe to eat', 'should i eat', 'is it okay to eat', 'safe for me'],
    'allergy': ['my allergies', 'allergic to', 'what am i allergic', 'allergy list', 'allergen'],
    // Intents that answer from the user's own history (food log, workouts, weigh-ins, streaks).
    'week_summary': [
      'how am i doing', 'weekly summary', 'weekly progress', 'week summary', 'my progress', 'fitness score', 'my score', 'weekly score',
      'how is my week', 'progress this week', 'progress so far', 'how have i done',
    ],
    'streaks_badges': ['streak', 'streaks', 'my streak', 'workout streak', 'logging streak', 'badges', 'my badges', 'achievements', 'next badge', 'my level', 'fitness level'],
    'last_workout': [
      'last workout', 'when did i last', 'workouts this week', 'how many workouts', 'did i work out', 'did i train', 'workout history',
      'workouts done', 'workouts have i done', 'missed workouts', 'workouts did i do',
    ],
    'ate_log': [
      'what did i eat', 'what have i eaten', 'what i ate', 'what i have eaten', 'my meals today', 'meals today', 'food today',
      'my food log', 'food log', 'my diary', 'what did i have', 'what have i had', 'show my meals',
    ],
    'macros': [
      'protein left', 'protein today', 'macros today', 'my macros', 'protein so far', 'how much protein have i', 'carbs today',
      'fat today', 'protein remaining', 'macros left', 'macros so far',
    ],
    'eating_trend': [
      'how have i been eating', 'average calories', 'avg calories', 'calories this week', 'eating this week', 'calorie history',
      'intake this week', 'my eating', 'eating habits', 'last week calories', 'calories last week',
    ],
    'weight_progress': [
      'my weight', 'weight progress', 'weight trend', 'am i losing weight', 'am i gaining weight', 'have i lost', 'how much have i lost',
      'goal weight', 'target weight', 'how close am i', 'weight change', 'weigh ins', 'weigh in', 'progress toward my goal',
    ],
    'target_explain': [
      'why is my target', 'why is my calorie', 'target adjusted', 'adjusted my target', 'personalised target', 'personalized target',
      'how was my target', 'why did my target',
    ],
  };

  static const _symptoms = [
    'chest pain', 'chest tightness', 'chest pressure', 'dizzy', 'dizziness', 'faint', 'fainting', 'passed out',
    'shortness of breath', 'short of breath', 'breathless', 'cant breathe', 'palpitation', 'palpitations',
    'heart racing', 'irregular heartbeat', 'numbness', 'numb', 'severe pain', 'blood in', 'swelling', 'swollen',
    'vomiting', 'injury', 'injured', 'sprain', 'sprained', 'pulled muscle', 'blood sugar', 'sugar level', 'glucose',
    'blood pressure', 'bp high', 'hypoglycemia', 'hyperglycemia', 'pain', 'hurts', 'ache',
  ];
  static const _emergency = [
    'chest pain', 'chest tightness', 'chest pressure', 'faint', 'fainting', 'passed out', 'shortness of breath',
    'short of breath', 'breathless', 'cant breathe', 'numbness', 'numb', 'severe pain', 'blood in',
  ];
  static const _doctorWords = ['doctor', 'consult', 'specialist', 'physician', 'appointment', 'medical advice', 'see a doctor', 'dietitian', 'nutritionist'];
  static const _riskyTopics = [
    'supplement', 'steroid', 'medicine', 'medication', 'insulin', 'tablet', 'pills', 'fasting', 'intermittent', 'keto',
    'crash diet', 'detox', 'hiit', 'max out', 'heavy lifting', 'extreme',
  ];

  static const _faqs = <_Faq>[
    _Faq(['log food', 'log meal', 'track food', 'track calories', 'add food', 'log my meal', 'food diary'],
        'Open the Diet tab and tap "Log Food". You can type what you ate (for example "2 rotis and a bowl of daal") or search the food list. I add up the calories and update your daily total.',
        [ChatAction('diet', 'Open Diet Tracker')]),
    _Faq(['scan label', 'scan ingredients', 'allergen scanner', 'check ingredients', 'scan product', 'scan a label'],
        'Use the Allergy Scanner: take a photo of a product\'s ingredient label (or paste the ingredients) and I\'ll compare them with your allergy list and warn you if there\'s a match.',
        [ChatAction('scanner', 'Open Allergy Scanner')]),
    _Faq(['regenerate', 'new plan', 'change my plan', 'different workout', 'change workout', 'new workout'],
        'Open the Workout tab and tap "Regenerate plan" to get a fresh set of exercises that still respect your health restrictions.',
        [ChatAction('workout', 'Open Workout Plan')]),
    _Faq(['change goal', 'update profile', 'edit profile', 'update weight', 'change my goal', 'change my weight', 'update my details'],
        'Open the Profile tab and tap "Update my details". Your BMI, calorie target, classification and plans are recalculated from the new values.',
        [ChatAction('profile', 'Open Profile')]),
    _Faq(['sources', 'source of your data', 'where do your numbers come from', 'references', 'how accurate', 'how reliable', 'evidence', 'methodology'],
        'My numbers come from published references: WHO BMI categories, the Mifflin–St Jeor equation for calories, the 2024 Compendium of Physical Activities for workout energy, and USDA FoodData Central for food nutrition (foods without a USDA value are labelled as estimates). The Sources & methodology page lists every reference and its limits.',
        [ChatAction('sources', 'Sources & methodology')]),
    _Faq(['what is bmi', 'bmi mean', 'bmi formula', 'how is bmi', 'bmi', 'body mass index'],
        'BMI is your weight in kg divided by your height in metres squared. WHO ranges: under 18.5 underweight, 18.5–24.9 normal, 25–29.9 overweight, 30 and above obese. It\'s a screening tool and doesn\'t measure body fat directly.'),
    _Faq(['what is bmr', 'bmr mean', 'how is bmr', 'what is tdee', 'bmr', 'tdee', 'basal metabolic rate'],
        'BMR is the calories your body burns at rest. I use the Mifflin-St Jeor formula, then multiply by your activity level to estimate your daily needs (TDEE).'),
    _Faq(['how is calorie', 'how are calories calculated', 'calorie calculation'],
        'Your daily needs come from BMR (Mifflin-St Jeor) × your activity level. For weight loss I subtract 500 kcal, for muscle gain I add 300 kcal, with a safety floor so the target never gets too low.'),
    _Faq(['lose weight', 'weight loss', 'fat loss', 'burn fat', 'reduce weight'],
        'Sustainable weight loss comes from a modest calorie deficit (about 500 kcal/day), enough protein, daily movement and good sleep. Aim for 0.25–0.75 kg per week. Your plan already sets these targets for you.',
        [ChatAction('nutrition', 'View Nutrition Plan')]),
    _Faq(['gain muscle', 'build muscle', 'muscle gain', 'gain weight', 'bulk'],
        'To build muscle: train major muscle groups 3–5 days a week, eat a small calorie surplus (about +300 kcal) and get enough protein (roughly 1.6–1.8 g per kg of body weight).',
        [ChatAction('workout', 'View Workout Plan')]),
    _Faq(['how much protein', 'protein need', 'protein intake'],
        'A good general range is 1.2–1.8 g of protein per kg of body weight depending on your goal. Your exact target is on your Nutrition Plan.',
        [ChatAction('nutrition', 'View Nutrition Plan')]),
    _Faq(['how much water', 'drink water', 'hydration', 'water intake'],
        'A practical target is about 35 ml of water per kg of body weight each day, more if you sweat a lot. Your plan shows your personal amount.'),
    _Faq(['sleep', 'rest day', 'recovery'],
        'Aim for 7–9 hours of sleep and keep your rest days. Muscles and your heart adapt during recovery, not during the workout itself.'),
    _Faq(['are you a doctor', 'medical advice', 'replace doctor', 'diagnose', 'diagnosis'],
        '$_disclaimer For anything medical, please talk to a qualified professional.',
        [ChatAction('consult', 'Find a Specialist')]),
    _Faq(['privacy', 'data safe', 'my data', 'is my data'],
        'Your health profile is tied to your account and sent over to the Baymax server only when you are signed in. Camera images for posture detection are meant to be processed on your device.'),
    _Faq(['what can you do', 'help', 'features', 'how to use'],
        'I can: tell you your BMI and calorie target, show today\'s workout, summarise your week, show what you ate, your macros, streaks, badges and weight progress, explain how to do an exercise, suggest meals that avoid your allergens, look up calories in foods, check if a food is safe for your allergies, and tell you when to see a doctor.'),
  ];

  ChatReply respond(String input, ChatContext ctx) {
    final text = input.trim();
    if (text.isEmpty) return const ChatReply('Type a question and I\'ll do my best to help!', 'empty');

    final norm = Fuzzy.normalize(text);
    final compact = norm.replaceAll(' ', '');

    // 1. Safety first (FR-4): symptoms and explicit doctor requests.
    final concern = _concernReply(norm, ctx);
    if (concern != null) return concern;

    // 2. Specific data lookups.
    final lookup = _calorieLookup(text, norm, ctx);
    if (lookup != null) return lookup;

    final howTo = _exerciseHowTo(norm, compact);
    if (howTo != null) return howTo;

    // Definitional questions ("what is…", "how is… calculated") are answered
    // from the FAQ even when a personal-data intent also matches.
    final faqHit = _matchFaq(norm);
    if (faqHit != null && faqHit.keyLength >= 8 && RegExp(r'^(how (is|are|does|do you)|what (is|are)|why)\b').hasMatch(norm)) {
      return ChatReply(faqHit.faq.answer, 'faq', actions: faqHit.faq.actions);
    }

    final intent = _detectIntent(norm);
    switch (intent) {
      case 'greeting':
        final n = ctx.firstName;
        final today = _todayLine(ctx);
        return ChatReply('Hi${n.isEmpty ? '' : ' $n'}! I\'m Baymax, your health assistant. Ask me about your calories, workouts, meals or allergies.${today.isEmpty ? '' : '\n$today'}', 'greeting');
      case 'thanks':
        return const ChatReply('You\'re welcome! Keep going — I\'m here whenever you need me.', 'thanks');
      case 'bye':
        return const ChatReply('Take care! See you at your next workout.', 'bye');
      case 'bmi':
        return _bmi(ctx);
      case 'bmr':
        return _bmr(ctx);
      case 'calorie_target':
        return _calorieTarget(ctx);
      case 'remaining':
        return _remaining(ctx);
      case 'workout_today':
        return _workoutToday(ctx);
      case 'workout_plan':
        return _workoutWeek(ctx);
      case 'meal':
        return _mealSuggestion(norm, ctx);
      case 'can_eat':
        return _canEat(text, norm, ctx);
      case 'allergy':
        return _allergies(ctx);
      case 'week_summary':
        return _weekSummary(ctx);
      case 'streaks_badges':
        return _streaksBadges(ctx);
      case 'last_workout':
        return _lastWorkout(ctx);
      case 'ate_log':
        return _ateLog(norm, ctx);
      case 'macros':
        return _macros(ctx);
      case 'eating_trend':
        return _eatingTrend(ctx);
      case 'weight_progress':
        return _weightProgress(ctx);
      case 'target_explain':
        return _targetExplain(ctx);
    }

    // 3. FAQs.
    if (faqHit != null) return ChatReply(faqHit.faq.answer, 'faq', actions: faqHit.faq.actions);

    return const ChatReply(
      'I\'m not sure I understood that. Try asking things like "What\'s my workout today?", "How many calories in biryani?" or "What should I eat for dinner?".',
      'fallback',
    );
  }

  // --- Intent detection (FR-1) ------------------------------------------------

  String? _detectIntent(String norm) {
    final padded = ' $norm ';
    final tokens = norm.split(' ');
    String? best;
    var bestScore = 0.0;
    var bestLongest = 0;
    _intents.forEach((intent, keys) {
      var score = 0.0;
      var longest = 0; // length of the longest phrase that matched: breaks ties toward the more specific intent
      for (final k in keys) {
        final nk = Fuzzy.normalize(k);
        if (nk.contains(' ')) {
          if (padded.contains(' $nk ')) {
            score += 2;
            if (nk.length > longest) longest = nk.length;
          }
        } else if (tokens.contains(nk)) {
          score += 1;
          if (nk.length > longest) longest = nk.length;
        } else if (nk.length >= 6 && tokens.any((t) => Fuzzy.wordsMatch(nk, t))) {
          score += 0.8; // typo tolerance
        }
      }
      if (score > bestScore || (score == bestScore && score > 0 && longest > bestLongest)) {
        bestScore = score;
        bestLongest = longest;
        best = intent;
      }
    });
    return bestScore >= 1 ? best : null;
  }

  _FaqHit? _matchFaq(String norm) {
    final padded = ' $norm ';
    _FaqHit? best;
    for (final f in _faqs) {
      for (final k in f.keys) {
        final nk = Fuzzy.normalize(k);
        if (padded.contains(' $nk ') && (best == null || nk.length > best.keyLength)) {
          best = _FaqHit(f, nk.length);
        }
      }
    }
    return best;
  }

  // --- Doctor recommendation (FR-4) ---------------------------------------------

  ChatReply? _concernReply(String norm, ChatContext ctx) {
    final padded = ' $norm ';
    bool has(List<String> list) => list.any((k) => padded.contains(' ${Fuzzy.normalize(k)} '));

    final consultAction = const ChatAction('consult', 'Book a Consultation');

    if (has(_emergency)) {
      return ChatReply(
        'Those symptoms can be serious. Please stop exercising now and seek medical help immediately — call your local emergency number or go to the nearest hospital. $_disclaimer',
        'emergency',
        actions: [consultAction],
      );
    }
    if (has(_symptoms)) {
      return ChatReply(
        'I\'m sorry you\'re dealing with that. $_disclaimer Please rest, avoid training through it, and speak to a doctor — especially if it\'s severe, getting worse, or lasts more than a couple of days.',
        'health_concern',
        actions: [consultAction],
      );
    }
    if (has(_doctorWords)) {
      return ChatReply(
        'A qualified doctor, nutritionist or trainer can give you advice I can\'t. You can book an online consultation from the app.',
        'doctor_request',
        actions: [consultAction],
      );
    }
    final cls = ctx.classification;
    final risky = cls != null && (cls.isCardiac || cls.isDiabetic || cls.riskLevel == 'High');
    if (risky && has(_riskyTopics)) {
      return ChatReply(
        'Because your profile is classified as ${cls.category} (${cls.riskLevel} risk), changes like that — supplements, fasting, medication or very intense training — should be approved by your doctor first. $_disclaimer',
        'doctor_recommended',
        actions: [consultAction],
      );
    }
    return null;
  }

  // --- Calorie / nutrition information (FR-3) -------------------------------------

  ChatReply? _calorieLookup(String raw, String norm, ChatContext ctx) {
    final db = ctx.db;
    if (db == null) return null;
    final lower = raw.toLowerCase();
    final m = RegExp(r'(?:calories?|kcals?|nutrition|macros?|protein|carbs?|fats?)\s+(?:are\s+)?(?:in|of|for|does)\s+(.+)').firstMatch(lower) ??
        RegExp(r'how many calories (?:does|do|is|are)\s+(.+?)\s+(?:have|contain|has)').firstMatch(lower);
    if (m == null) return null;
    return _calorieReplyFor(m.group(1)!, ctx);
  }

  /// The calories and macros of the foods named in [phrase] ("2 rotis and daal").
  ChatReply? _calorieReplyFor(String phrase, ChatContext ctx) {
    final db = ctx.db;
    if (db == null) return null;
    final parsed = FoodParser(db).parse(phrase.replaceAll(RegExp(r'[?!.]+$'), ''));
    final matched = parsed.where((p) => p.matched).toList();
    if (matched.isEmpty) {
      return const ChatReply('I couldn\'t find that food in my database. Try a simpler name like "rice", "chicken biryani" or "banana".', 'calorie_lookup');
    }
    final b = StringBuffer();
    for (final p in matched) {
      b.writeln('• ${FoodParser.describe(p)} (${p.item!.servingLabel}) — ${p.kcal.round()} kcal');
    }
    final totalKcal = matched.fold(0.0, (s, p) => s + p.kcal);
    final protein = matched.fold(0.0, (s, p) => s + p.protein);
    final carbs = matched.fold(0.0, (s, p) => s + p.carbs);
    final fat = matched.fold(0.0, (s, p) => s + p.fat);
    if (matched.length > 1) b.writeln('Total: ${totalKcal.round()} kcal');
    b.write('Protein ${protein.round()} g · Carbs ${carbs.round()} g · Fat ${fat.round()} g');
    final unmatched = parsed.where((p) => !p.matched).map((p) => p.raw).toList();
    if (unmatched.isNotEmpty) b.write('\n(Couldn\'t find: ${unmatched.join(', ')})');
    return ChatReply(b.toString(), 'calorie_lookup', actions: const [ChatAction('diet', 'Log Food')]);
  }

  ChatReply _bmi(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('bmi');
    return ChatReply(
      'Your BMI is ${p.bmi.toStringAsFixed(1)} — ${p.bmiCategory} (WHO). Healthy range is 18.5–24.9. BMI is only a screening tool, so it doesn\'t tell the whole story.',
      'bmi',
    );
  }

  ChatReply _bmr(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('bmr');
    return ChatReply(
      'Your BMR is about ${p.bmr.round()} kcal/day (Mifflin-St Jeor) — what you burn at rest. With your activity level (${p.activityLevel}) your daily needs are around ${p.tdee.round()} kcal.',
      'bmr',
    );
  }

  ChatReply _calorieTarget(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('calorie_target');
    final t = p.calorieTargets;
    final e = ctx.history.estimate;
    final adapted = e != null && e.status == EstimateStatus.adapted;
    final target = ctx.plan?.nutrition.targetKcal ?? p.dailyCalorieTarget;
    return ChatReply(
      'For your goal (${p.primaryGoal}) your daily target is $target kcal. Maintenance is ${t.maintain}, a deficit is ${t.deficit} and a surplus is ${t.surplus} kcal.'
      '${adapted ? '\nThis target was adjusted from your own weight and food logs; ask "why is my target adjusted" for the details.' : ''}'
      '${t.safetyNote != null && p.primaryGoal == 'Lose Weight' ? '\n${t.safetyNote}' : ''}',
      'calorie_target',
      actions: const [ChatAction('nutrition', 'View Nutrition Plan')],
    );
  }

  ChatReply _remaining(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('remaining');
    final target = ctx.plan?.nutrition.targetKcal ?? p.dailyCalorieTarget;
    final eaten = ctx.todayKcal;
    final left = target - eaten.round();
    final b = StringBuffer(left >= 0
        ? 'You\'ve eaten ${eaten.round()} of ${target} kcal today — $left kcal left.'
        : 'You\'ve eaten ${eaten.round()} kcal today, which is ${-left} kcal over your ${target} kcal target.');
    final entries = ctx.history.entriesOn(ctx.now);
    final n = ctx.plan?.nutrition;
    if (entries != null && entries.isNotEmpty && n != null) {
      final protein = entries.fold(0.0, (s, e) => s + e.protein).round();
      b.write('\nProtein so far: $protein of ${n.proteinG} g.');
    }
    return ChatReply(b.toString(), 'remaining', actions: const [ChatAction('diet', 'Open Diet Tracker')]);
  }

  // --- Workout information (FR-3) ---------------------------------------------------

  ChatReply _workoutToday(ChatContext ctx) {
    final plan = ctx.plan;
    final p = ctx.profile;
    if (plan == null || p == null) return _needsProfile('workout_today');
    final blocked = _workoutBlocked(plan, 'workout_today');
    if (blocked != null) return blocked;
    final day = plan.workoutFor(ctx.now);
    if (day == null) {
      return const ChatReply('Today is a rest day. A relaxed walk and some stretching are great for recovery.', 'workout_today',
          actions: [ChatAction('workout', 'View Weekly Plan')]);
    }
    final main = day.exercises.where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown');
    final list = main.map((e) => '• ${e.exercise.name} — ${e.prescription}').join('\n');
    final pr = ctx.history.progress;
    final extra = StringBuffer();
    if (pr != null) {
      if (pr.days.last.workoutDone) extra.write('\nYou have already marked today\'s workout as done.');
      extra.write('\nThis week: ${pr.week.workoutsDone} of ${pr.week.workoutsPlanned} planned workouts done.');
      if (pr.inactivity != null) extra.write('\nIt has been ${pr.inactivity!.daysSinceWorkout} days since your last one, so keep it easy and just get started.');
    }
    return ChatReply(
      'Today: ${day.name} (~${day.durationMin} min, ~${day.kcal(p.weightKg)} kcal, ${plan.intensity} intensity).\n$list$extra',
      'workout_today',
      actions: const [ChatAction('workout', 'Open Workout Plan')],
    );
  }

  /// Module 4: when the safety screening stopped the plan, say why instead of listing rest days.
  ChatReply? _workoutBlocked(PersonalizedPlan plan, String intent) {
    if (plan.workoutAvailable) return null;
    return ChatReply(
      'There is no workout plan yet: ${plan.gate!.reasons.join(' ')}',
      intent,
      actions: const [ChatAction('workout', 'Open Workout')],
    );
  }

  ChatReply _workoutWeek(ChatContext ctx) {
    final plan = ctx.plan;
    if (plan == null) return _needsProfile('workout_plan');
    final blocked = _workoutBlocked(plan, 'workout_plan');
    if (blocked != null) return blocked;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final lines = [
      for (var i = 0; i < 7; i++) '${names[i]}: ${plan.week[i]?.name ?? 'Rest'}',
    ];
    return ChatReply(
      'Your week (${plan.workoutDays} workout days, ${plan.intensity} intensity):\n${lines.join('\n')}',
      'workout_plan',
      actions: const [ChatAction('workout', 'Open Workout Plan')],
    );
  }

  ChatReply? _exerciseHowTo(String norm, String compact) {
    if (!norm.contains('how') && !norm.contains('form') && !norm.contains('technique') && !norm.contains('perform')) {
      return null;
    }
    Exercise? best;
    var bestLen = 0;
    for (final e in [...ExerciseLibrary.all, ExerciseLibrary.warmUp]) {
      final keys = {
        Fuzzy.normalize(e.name).replaceAll(' ', ''),
        e.id.replaceAll('_', ''),
      };
      for (final k in keys) {
        if (k.length >= 4 && (compact.contains(k) || compact.contains(Fuzzy.singular(k))) && k.length > bestLen) {
          best = e;
          bestLen = k.length;
        }
      }
    }
    if (best == null) return null;
    final steps = [for (var i = 0; i < best.steps.length; i++) '${i + 1}. ${best.steps[i]}'].join('\n');
    return ChatReply(
      '${best.name} (${best.muscles.join(', ')}):\n$steps\nStop if you feel sharp pain.',
      'exercise_howto',
      actions: const [ChatAction('workout', 'Open Workout Plan')],
    );
  }

  // --- Meals and allergies (FR-3) -------------------------------------------------------

  String _mealFor(String norm, DateTime now) {
    if (norm.contains('breakfast')) return 'Breakfast';
    if (norm.contains('lunch')) return 'Lunch';
    if (norm.contains('dinner') || norm.contains('supper')) return 'Dinner';
    if (norm.contains('snack')) return 'Snack';
    final h = now.hour;
    if (h < 11) return 'Breakfast';
    if (h < 16) return 'Lunch';
    if (h < 19) return 'Snack';
    return 'Dinner';
  }

  ChatReply _mealSuggestion(String norm, ChatContext ctx) {
    final plan = ctx.plan;
    final p = ctx.profile;
    if (plan == null || p == null) return _needsProfile('meal');
    final meal = _mealFor(norm, ctx.now);
    final items = plan.nutrition.meals[meal] ?? const <MealItem>[];
    if (items.isEmpty) {
      return ChatReply('I couldn\'t build a $meal that avoids your allergies from my food list. Try searching foods in the Diet tab.', 'meal',
          actions: const [ChatAction('diet', 'Open Diet Tracker')]);
    }
    final kcal = items.fold(0.0, (s, i) => s + i.kcal).round();
    final lines = items.map((i) => '${i.food.name} (${i.servingText}) — ${i.kcal.round()} kcal').join('\n');
    final logged = ctx.history.entriesOn(ctx.now)?.where((e) => e.meal == meal).toList() ?? const [];
    final left = plan.nutrition.targetKcal - ctx.todayKcal.round();
    final personal = StringBuffer();
    if (logged.isNotEmpty) personal.write('\nYou already logged ${logged.map((e) => e.name).join(', ')} for $meal today (${logged.fold(0.0, (s, e) => s + e.kcal).round()} kcal).');
    personal.write(left > 0 ? '\nYou have about $left kcal left today.' : '\nYou are already at or over your calorie target today, so keep this one light.');
    final allergyNote = p.allergies.isEmpty ? '' : '\nThis avoids your ${p.allergies.join(', ').toLowerCase()} allergen${p.allergies.length > 1 ? 's' : ''}.';
    return ChatReply(
      'For $meal I suggest (~$kcal kcal):\n$lines$allergyNote$personal',
      'meal',
      actions: const [ChatAction('nutrition', 'View Nutrition Plan'), ChatAction('diet', 'Log Food')],
    );
  }

  ChatReply _canEat(String raw, String norm, ChatContext ctx, {String? foodPhrase}) {
    final db = ctx.db;
    final p = ctx.profile;
    if (db == null || p == null) return _needsProfile('can_eat');
    final phrase = foodPhrase ?? raw
        .toLowerCase()
        .replaceAll(RegExp(r'(can i (eat|have)|am i allowed( to (eat|have))?|is it (ok|okay|safe)( to eat)?|should i eat|safe for me|\?)'), ' ')
        .trim();
    final item = db.match(phrase);
    if (item == null) {
      return const ChatReply('I couldn\'t identify that food. Try the Allergy Scanner for packaged products, or ask about a simpler food name.', 'can_eat',
          actions: [ChatAction('scanner', 'Open Allergy Scanner')]);
    }
    final conflicts = item.conflictsWith(p.allergies);
    if (conflicts.isNotEmpty) {
      return ChatReply('${item.name} contains ${conflicts.join(', ')}, which is on your allergy list. Please avoid it.', 'can_eat');
    }
    final notes = <String>[];
    if (p.hasCondition('Diabetes') && (item.tags.contains('highSugar') || item.tags.contains('refined'))) {
      notes.add('It is high in sugar/refined carbs, so keep the portion small and watch your blood sugar.');
    }
    if ((p.hasCondition('Hypertension') || ctx.classification?.isCardiac == true) &&
        (item.tags.contains('highSodium') || item.tags.contains('fried'))) {
      notes.add('It is salty or fried, which is best limited for your heart health.');
    }
    if (p.primaryGoal == 'Lose Weight' && item.kcal > 400) {
      notes.add('It is calorie-dense (${item.kcal.round()} kcal per ${item.servingLabel}) — consider a smaller portion.');
    }
    final target = ctx.plan?.nutrition.targetKcal;
    if (target != null) {
      final left = target - ctx.todayKcal.round();
      notes.add(left > 0
          ? 'That would use ${item.kcal.round()} of the $left kcal you have left today.'
          : 'You are already at or over your calorie target today, so a smaller portion would be wise.');
    }
    return ChatReply(
      '${item.name} doesn\'t contain anything on your allergy list. ${item.servingLabel}: ${item.kcal.round()} kcal.${notes.isEmpty ? '' : '\n${notes.join(' ')}'}',
      'can_eat',
    );
  }

  ChatReply _allergies(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null) return _needsProfile('allergy');
    if (p.allergies.isEmpty) {
      return const ChatReply('You haven\'t listed any food allergies. If that\'s not right, update your profile so I can protect you.', 'allergy');
    }
    return ChatReply('Your allergies: ${p.allergies.join(', ')}. I use these to filter meal suggestions and to check ingredient labels.', 'allergy',
        actions: const [ChatAction('scanner', 'Open Allergy Scanner')]);
  }

  // --- Answers from the user's own history ------------------------------------------------
  //
  // Everything below is written from data in the user's account (food log, completed workouts, weigh-ins). When a part of
  // that data could not be read the reply says so, instead of claiming the user did nothing.

  ChatReply _unavailable(String intent, String what) => ChatReply(
        'I can\'t read your $what right now (you may be offline or signed out). Please try again in a moment.',
        intent,
      );

  static String _ago(DateTime d, DateTime now) {
    final days = Gamification.dateOnly(now).difference(Gamification.dateOnly(d)).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }

  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  ChatReply _weekSummary(ChatContext ctx) {
    if (ctx.profile == null || ctx.plan == null) return _needsProfile('week_summary');
    final pr = ctx.history.progress;
    if (pr == null) return _unavailable('week_summary', 'activity and food logs');
    final w = pr.week;
    final b = StringBuffer('This week your fitness score is ${w.total.round()}/100 (${pr.level.label} level).');
    b.write(w.training == null
        ? '\nWorkouts: no planned workout day has passed yet this week.'
        : '\nWorkouts: ${w.workoutsDone} of ${w.workoutsPlanned} planned days done.');
    b.write('\nFood logging: ${w.daysLogged} of ${w.daysElapsed} days.');
    if (w.daysLogged > 0) b.write('\nCalories: ${w.daysOnTarget} of ${w.daysLogged} logged days within 15% of your target.');
    if (pr.workoutStreak > 0 || pr.loggingStreak > 0) {
      b.write('\nStreaks: ${pr.workoutStreak} workouts in a row, ${pr.loggingStreak} days of logging in a row.');
    }
    final parts = <String, double>{
      if (w.training != null) 'workouts': w.training!,
      'food logging': w.logging,
      if (w.daysLogged > 0) 'staying near your calorie target': w.adherence,
    };
    final weakest = parts.entries.reduce((a, c) => c.value < a.value ? c : a);
    if (weakest.value >= 0.9) {
      b.write('\nA strong week so far. Keep it going.');
    } else if (weakest.key == 'workouts') {
      b.write('\nYour lowest area is workouts. Even a short session on your next planned day lifts your score.');
    } else if (weakest.key == 'food logging') {
      b.write('\nYour lowest area is food logging. Logging every meal today is the quickest way to raise your score.');
    } else {
      b.write('\nYour lowest area is staying near your calorie target. The Diet tab shows what you have left each day.');
    }
    final i = pr.inactivity;
    if (i != null) {
      b.write('\nIt has been ${i.daysSinceWorkout} days since your last workout and you missed ${i.missedPlannedDays} planned '
          '${i.missedPlannedDays == 1 ? 'session' : 'sessions'}. A short one still counts.');
    }
    return ChatReply(b.toString(), 'week_summary', actions: const [ChatAction('progress', 'Open Progress'), ChatAction('analytics', 'Open Analytics')]);
  }

  ChatReply _streaksBadges(ChatContext ctx) {
    final pr = ctx.history.progress;
    if (ctx.plan == null) return _needsProfile('streaks_badges');
    if (pr == null) return _unavailable('streaks_badges', 'progress');
    final badges = pr.badges;
    final earned = badges.where((b) => b.earned).toList();
    final next = badges.where((b) => !b.earned).toList();
    final b = StringBuffer('Streaks: ${pr.workoutStreak} workouts in a row and ${pr.loggingStreak} days of food logging in a row. '
        'Your level is ${pr.level.label}.');
    b.write(earned.isEmpty
        ? '\nYou have not earned a badge yet.'
        : '\nBadges earned (${earned.length} of ${badges.length}): ${earned.map((e) => e.title).join(', ')}.');
    if (next.isNotEmpty) b.write('\nNext up: ${next.first.title}. ${next.first.description}');
    return ChatReply(b.toString(), 'streaks_badges', actions: const [ChatAction('progress', 'Open Progress')]);
  }

  ChatReply _lastWorkout(ChatContext ctx) {
    if (ctx.plan == null) return _needsProfile('last_workout');
    final pr = ctx.history.progress;
    if (pr == null) return _unavailable('last_workout', 'workout history');
    const act = [ChatAction('workout', 'Open Workout Plan')];
    final last = pr.lastWorkout;
    if (last == null) {
      return const ChatReply('I can\'t see a completed workout in your log yet. Tap "Mark done" on the Workout tab after a session and I\'ll track it.', 'last_workout', actions: act);
    }
    final done28 = pr.days.where((d) => d.workoutDone).toList();
    final minutes = done28.fold<int>(0, (s, d) => s + d.minutes);
    final w = pr.week;
    final b = StringBuffer('Your last completed workout was ${_ago(last, ctx.now)} (${_dayNames[last.weekday - 1]}).');
    b.write('\nThis week: ${w.workoutsDone} of ${w.workoutsPlanned} planned workouts done.');
    b.write('\nLast 4 weeks: ${done28.length} workouts${minutes > 0 ? ', about $minutes minutes in total' : ''}.');
    final i = pr.inactivity;
    if (i != null) {
      b.write('\nYou missed ${i.missedPlannedDays} planned ${i.missedPlannedDays == 1 ? 'session' : 'sessions'} since then. Restart with something short.');
    }
    return ChatReply(b.toString(), 'last_workout', actions: act);
  }

  ChatReply _ateLog(String norm, ChatContext ctx) {
    final p = ctx.profile;
    if (p == null) return _needsProfile('ate_log');
    final yesterday = norm.contains('yesterday');
    final day = yesterday ? Gamification.dateOnly(ctx.now).subtract(const Duration(days: 1)) : Gamification.dateOnly(ctx.now);
    final label = yesterday ? 'yesterday' : 'today';
    final entries = ctx.history.entriesOn(day);
    if (entries == null) return _unavailable('ate_log', 'food log');
    const act = [ChatAction('diet', 'Open Diet Tracker')];
    if (entries.isEmpty) {
      return ChatReply('You have not logged any food $label.${yesterday ? '' : ' Tell me what you ate, or log it in the Diet tab, and I can add it up.'}', 'ate_log', actions: act);
    }
    final b = StringBuffer('You logged these $label:');
    for (final meal in const ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
      final items = entries.where((e) => e.meal == meal).toList();
      if (items.isEmpty) continue;
      b.write('\n$meal: ${items.map((e) => '${e.name} (${e.kcal.round()} kcal)').join(', ')}');
    }
    final kcal = entries.fold(0.0, (s, e) => s + e.kcal);
    final target = ctx.plan?.nutrition.targetKcal ?? p.dailyCalorieTarget;
    b.write('\nTotal: ${kcal.round()} of $target kcal');
    final left = target - kcal.round();
    b.write(left >= 0 ? ' ($left left).' : ' (${-left} over).');
    return ChatReply(b.toString(), 'ate_log', actions: act);
  }

  ChatReply _macros(ChatContext ctx) {
    final plan = ctx.plan;
    if (plan == null || ctx.profile == null) return _needsProfile('macros');
    final entries = ctx.history.entriesOn(ctx.now);
    if (entries == null) return _unavailable('macros', 'food log');
    final n = plan.nutrition;
    final protein = entries.fold(0.0, (s, e) => s + e.protein);
    final carbs = entries.fold(0.0, (s, e) => s + e.carbs);
    final fat = entries.fold(0.0, (s, e) => s + e.fat);
    String line(String name, double eaten, int target) {
      final left = target - eaten.round();
      return '$name: ${eaten.round()} of $target g (${left >= 0 ? '$left g to go' : '${-left} g over'})';
    }

    if (entries.isEmpty) {
      return ChatReply('You have not logged food today, so nothing counts yet. Your daily targets are protein ${n.proteinG} g, carbs ${n.carbsG} g and fat ${n.fatG} g.', 'macros',
          actions: const [ChatAction('diet', 'Log Food')]);
    }
    return ChatReply('Today so far:\n${line('Protein', protein, n.proteinG)}\n${line('Carbs', carbs, n.carbsG)}\n${line('Fat', fat, n.fatG)}', 'macros',
        actions: const [ChatAction('diet', 'Open Diet Tracker')]);
  }

  ChatReply _eatingTrend(ChatContext ctx) {
    final plan = ctx.plan;
    if (plan == null || ctx.profile == null) return _needsProfile('eating_trend');
    final pr = ctx.history.progress;
    if (pr == null) return _unavailable('eating_trend', 'food log');
    final week = pr.days.sublist(pr.days.length - 7);
    final logged = week.where((d) => d.kcal != null).toList();
    const act = [ChatAction('analytics', 'Open Analytics')];
    if (logged.isEmpty) {
      return const ChatReply('You have not logged any food in the last 7 days, so I have nothing to average. Log your meals and I can show how you are eating.', 'eating_trend',
          actions: [ChatAction('diet', 'Log Food')]);
    }
    final target = plan.nutrition.targetKcal;
    final avg = logged.fold(0.0, (s, d) => s + d.kcal!) / logged.length;
    final within = logged.where((d) => d.kcal! >= target * 0.85 && d.kcal! <= target * 1.15).length;
    final top = logged.reduce((a, c) => c.kcal! > a.kcal! ? c : a);
    final b = StringBuffer('In the last 7 days you logged food on ${logged.length} days, averaging ${avg.round()} kcal a day (your target is $target).');
    b.write('\n$within of those days were within 15% of your target. Your highest day was ${_dayNames[top.date.weekday - 1]} at ${top.kcal!.round()} kcal.');
    if (avg > target * 1.15) {
      b.write('\nOn average you are above your target. Check the portion sizes of your biggest meals.');
    } else if (avg < target * 0.85) {
      b.write('\nOn average you are well below your target. If that is not on purpose, you may be missing meals or not logging them.');
    } else {
      b.write('\nThat is close to your target.');
    }
    if (logged.length < 5) b.write('\nWith only ${logged.length} logged days this is a rough picture; the more you log, the better it gets.');
    return ChatReply(b.toString(), 'eating_trend', actions: act);
  }

  ChatReply _weightProgress(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('weight_progress');
    final w = ctx.history.weights;
    if (w == null) return _unavailable('weight_progress', 'weigh-ins');
    const act = [ChatAction('calorie', 'Log My Weight')];
    final targetKg = p.targetWeightValue > 0 ? HealthCalc.toKg(p.targetWeightValue, p.targetWeightUnit) : null;
    if (w.isEmpty) {
      return ChatReply(
        'I do not see any weigh-ins from the last 4 weeks. Your profile weight is ${p.weightKg.toStringAsFixed(1)} kg'
        '${targetKg == null ? '' : ' and your target is ${targetKg.toStringAsFixed(1)} kg'}. Log your weight two or three times a week and I will show your trend.',
        'weight_progress',
        actions: act,
      );
    }
    final first = w.first, last = w.last;
    final b = StringBuffer('Your latest weigh-in is ${last.kg.toStringAsFixed(1)} kg (${_ago(last.date, ctx.now)}).');
    if (w.length >= 2) {
      final change = last.kg - first.kg;
      b.write(' Compared with ${first.kg.toStringAsFixed(1)} kg ${_ago(first.date, ctx.now)}, that is ${change >= 0 ? '+' : '-'}${change.abs().toStringAsFixed(1)} kg.');
    }
    final proj = projectWeight(weights: w, today: ctx.now, targetKg: targetKg);
    if (proj.reliable) {
      final perWeek = proj.kgPerWeek!;
      b.write('\nYour trend is ${perWeek >= 0 ? '+' : '-'}${perWeek.abs().toStringAsFixed(2)} kg per week.');
      if (p.primaryGoal == 'Lose Weight' && perWeek > 0.05) {
        b.write(' Your goal is to lose weight, so this is the wrong direction. The Diet tab shows what you have left each day.');
      } else if (p.primaryGoal == 'Lose Weight' && perWeek < -1.0) {
        b.write(' That is faster than the usual 0.25 to 0.75 kg a week. Make sure you are eating enough.');
      } else if (p.primaryGoal == 'Gain Muscle' && perWeek < -0.05) {
        b.write(' Your goal is to gain, so this is the wrong direction. Check your calorie and protein targets.');
      }
    } else {
      b.write('\n${proj.note}');
    }
    if (targetKg != null) {
      final toGo = last.kg - targetKg;
      if (toGo.abs() < 0.2) {
        b.write('\nYou are at your target of ${targetKg.toStringAsFixed(1)} kg.');
      } else {
        b.write('\nYou are ${toGo.abs().toStringAsFixed(1)} kg ${toGo > 0 ? 'above' : 'below'} your target of ${targetKg.toStringAsFixed(1)} kg.');
        final weeks = proj.weeksToTarget;
        if (proj.reliable && weeks != null && weeks <= 52) b.write(' At this pace that is about ${weeks.ceil()} weeks away.');
      }
    }
    b.write('\nWeight moves up and down with water, food and sleep, so look at the trend, not one day.');
    return ChatReply(b.toString(), 'weight_progress', actions: act);
  }

  ChatReply _targetExplain(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('target_explain');
    final target = ctx.plan?.nutrition.targetKcal ?? p.dailyCalorieTarget;
    final e = ctx.history.estimate;
    const act = [ChatAction('calorie', 'How It Is Worked Out')];
    if (e == null || e.status != EstimateStatus.adapted) {
      return ChatReply(
        'Your target of $target kcal comes from the Mifflin-St Jeor formula, your activity level and your goal (${p.primaryGoal}). '
        '${e?.reason ?? 'Once you have logged your weight and meals for a couple of weeks, I can adjust it to how your body actually responds.'}',
        'target_explain',
        actions: act,
      );
    }
    final diff = e.adjustment.round();
    return ChatReply(
      'Your target of $target kcal was adjusted using your own logs. The formula alone would give about ${(e.priorTdee).round()} kcal for maintenance; '
      'your weight and food logs moved it by ${diff >= 0 ? '+' : ''}$diff kcal a day. ${e.reason}',
      'target_explain',
      actions: act,
    );
  }

  /// A line about today taken from the user's own data, or empty when there is nothing to say.
  String _todayLine(ChatContext ctx) {
    final plan = ctx.plan;
    final p = ctx.profile;
    if (plan == null || p == null) return '';
    final parts = <String>[];
    if (ctx.history.entriesOn(ctx.now) != null || ctx.consumedKcal > 0) {
      parts.add('${ctx.todayKcal.round()} of ${plan.nutrition.targetKcal} kcal eaten');
    }
    final day = plan.workoutFor(ctx.now);
    final done = ctx.history.progress?.days.last.workoutDone ?? false;
    parts.add(!plan.workoutAvailable ? 'no workout plan until the safety questions are resolved' : (day == null ? 'rest day' : '${day.name}${done ? ' (done)' : ''}'));
    return 'Today so far: ${parts.join(', ')}.';
  }

  /// Chat suggestions that fit what the user has (and has not) done, so the first tap is already useful.
  static List<String> suggestionsFor(ChatContext ctx) {
    final out = <String>[];
    final entries = ctx.history.entriesOn(ctx.now);
    if (ctx.history.progress != null) out.add('How am I doing this week?');
    if (entries != null && entries.isEmpty) {
      out.add('What should I eat for ${_mealLabel(ctx.now).toLowerCase()}?');
    } else if (entries != null) {
      out.add('What did I eat today?');
      out.add('How much protein have I had?');
    }
    out.add("What's my workout today?");
    if (ctx.history.weights != null) out.add("How's my weight progress?");
    out.add('How many calories can I eat?');
    for (final s in suggestions) {
      if (out.length >= 6) break;
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  static String _mealLabel(DateTime now) {
    final h = now.hour;
    if (h < 11) return 'Breakfast';
    if (h < 16) return 'Lunch';
    if (h < 19) return 'Snack';
    return 'Dinner';
  }

  ChatReply _needsProfile(String intent) => ChatReply(
        'I need your health profile for that. Please complete the profiling steps first and I\'ll personalise the answer.',
        intent,
      );
}

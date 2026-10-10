import '../models/health_profile.dart';
import '../models/plan.dart';
import '../utils/fuzzy.dart';
import 'exercise_library.dart';
import 'food_database.dart';
import 'food_parser.dart';
import 'health_classifier.dart';

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

  /// Calories logged so far today.
  final double consumedKcal;
  final DateTime now;

  ChatContext({
    this.profile,
    this.classification,
    this.plan,
    this.db,
    this.consumedKcal = 0,
    DateTime? now,
  }) : now = now ?? DateTime.now();

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
/// A Dialogflow NLU can replace [_detectIntent] later without touching the UI.
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
      'recommend food', 'food suggestion', 'diet plan', 'meal plan', 'what can i eat', 'something to eat',
    ],
    'can_eat': ['can i eat', 'can i have', 'am i allowed', 'is it ok to eat', 'is it safe to eat', 'should i eat', 'is it okay to eat', 'safe for me'],
    'allergy': ['my allergies', 'allergic to', 'what am i allergic', 'allergy list', 'allergen'],
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
        'I can: tell you your BMI and calorie target, show today\'s workout, explain how to do an exercise, suggest meals that avoid your allergens, look up calories in foods, check if a food is safe for your allergies, and tell you when to see a doctor.'),
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
        return ChatReply('Hi${n.isEmpty ? '' : ' $n'}! 👋 I\'m Baymax, your health assistant. Ask me about your calories, workouts, meals or allergies.', 'greeting');
      case 'thanks':
        return const ChatReply('You\'re welcome! Keep going — I\'m here whenever you need me. 💪', 'thanks');
      case 'bye':
        return const ChatReply('Take care! See you at your next workout. 👋', 'bye');
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
    _intents.forEach((intent, keys) {
      var score = 0.0;
      for (final k in keys) {
        final nk = Fuzzy.normalize(k);
        if (nk.contains(' ')) {
          if (padded.contains(' $nk ')) score += 2;
        } else if (tokens.contains(nk)) {
          score += 1;
        } else if (nk.length >= 6 && tokens.any((t) => Fuzzy.wordsMatch(nk, t))) {
          score += 0.8; // typo tolerance
        }
      }
      if (score > bestScore) {
        bestScore = score;
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
        '⚠️ Those symptoms can be serious. Please stop exercising now and seek medical help immediately — call your local emergency number or go to the nearest hospital. $_disclaimer',
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

    final parsed = FoodParser(db).parse(m.group(1)!.replaceAll(RegExp(r'[?!.]+$'), ''));
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
    return ChatReply(
      'For your goal (${p.primaryGoal}) your daily target is ${p.dailyCalorieTarget} kcal. Maintenance is ${t.maintain}, a deficit is ${t.deficit} and a surplus is ${t.surplus} kcal.${t.safetyNote != null && p.primaryGoal == 'Lose Weight' ? '\n${t.safetyNote}' : ''}',
      'calorie_target',
      actions: const [ChatAction('nutrition', 'View Nutrition Plan')],
    );
  }

  ChatReply _remaining(ChatContext ctx) {
    final p = ctx.profile;
    if (p == null || p.bmi <= 0) return _needsProfile('remaining');
    final target = ctx.plan?.nutrition.targetKcal ?? p.dailyCalorieTarget;
    final left = target - ctx.consumedKcal.round();
    final msg = left >= 0
        ? 'You\'ve eaten ${ctx.consumedKcal.round()} of ${target} kcal today — $left kcal left.'
        : 'You\'ve eaten ${ctx.consumedKcal.round()} kcal today, which is ${-left} kcal over your ${target} kcal target.';
    return ChatReply(msg, 'remaining', actions: const [ChatAction('diet', 'Open Diet Tracker')]);
  }

  // --- Workout information (FR-3) ---------------------------------------------------

  ChatReply _workoutToday(ChatContext ctx) {
    final plan = ctx.plan;
    final p = ctx.profile;
    if (plan == null || p == null) return _needsProfile('workout_today');
    final day = plan.workoutFor(ctx.now);
    if (day == null) {
      return const ChatReply('Today is a rest day. 🛌 A relaxed walk and some stretching are great for recovery.', 'workout_today',
          actions: [ChatAction('workout', 'View Weekly Plan')]);
    }
    final main = day.exercises.where((e) => e.exercise.id != 'warmup' && e.exercise.id != 'cooldown');
    final list = main.map((e) => '• ${e.exercise.name} — ${e.prescription}').join('\n');
    return ChatReply(
      'Today: ${day.name} (~${day.durationMin} min, ~${day.kcal(p.weightKg)} kcal, ${plan.intensity} intensity).\n$list',
      'workout_today',
      actions: const [ChatAction('workout', 'Open Workout Plan')],
    );
  }

  ChatReply _workoutWeek(ChatContext ctx) {
    final plan = ctx.plan;
    if (plan == null) return _needsProfile('workout_plan');
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
      '${best.icon} ${best.name} (${best.muscles.join(', ')}):\n$steps\nStop if you feel sharp pain.',
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
    final lines = items.map((i) => '${i.food.icon} ${i.food.name} (${i.servingText}) — ${i.kcal.round()} kcal').join('\n');
    final allergyNote = p.allergies.isEmpty ? '' : '\nThis avoids your ${p.allergies.join(', ').toLowerCase()} allergen${p.allergies.length > 1 ? 's' : ''}. 🛡️';
    return ChatReply(
      'For $meal I suggest (~$kcal kcal):\n$lines$allergyNote',
      'meal',
      actions: const [ChatAction('nutrition', 'View Nutrition Plan'), ChatAction('diet', 'Log Food')],
    );
  }

  ChatReply _canEat(String raw, String norm, ChatContext ctx) {
    final db = ctx.db;
    final p = ctx.profile;
    if (db == null || p == null) return _needsProfile('can_eat');
    final phrase = raw
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
      return ChatReply('🚫 ${item.name} contains ${conflicts.join(', ')}, which is on your allergy list. Please avoid it.', 'can_eat');
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
    return ChatReply(
      '✅ ${item.name} doesn\'t contain anything on your allergy list. ${item.servingLabel}: ${item.kcal.round()} kcal.${notes.isEmpty ? '' : '\n${notes.join(' ')}'}',
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

  ChatReply _needsProfile(String intent) => ChatReply(
        'I need your health profile for that. Please complete the profiling steps first and I\'ll personalise the answer.',
        intent,
      );
}

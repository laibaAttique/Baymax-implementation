import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/screens/chatbot/chatbot_screen.dart';
import 'package:app/services/activity_service.dart';
import 'package:app/services/calorie_optimizer.dart';
import 'package:app/services/chat_history.dart';
import 'package:app/services/chatbot_engine.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/user_session.dart';
import 'package:app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 14, 13); // a Wednesday, lunchtime

FoodEntry _e(String date, String meal, String name, double kcal, {double protein = 10, double carbs = 40, double fat = 8}) =>
    FoodEntry(date: date, meal: meal, name: name, quantity: 1, unit: 'serving', kcal: kcal, protein: protein, carbs: carbs, fat: fat);

HealthProfile _profile({String goal = 'Lose Weight', double target = 60}) => HealthProfile(
      fullName: 'Ayesha Malik',
      dob: '1998-05-05',
      gender: 'Female',
      heightValue: 165,
      weightValue: 72,
      medicalConditions: const [],
      foodAllergies: const ['Dairy'],
      primaryGoal: goal,
      activityLevel: 'Lightly Active',
      workoutFrequency: 4,
      targetWeightValue: target,
    );

void main() {
  late FoodDatabase db;
  const bot = ChatbotEngine();

  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  ChatContext build({
    HealthProfile? profile,
    ChatHistory history = ChatHistory.none,
    double consumed = 0,
  }) {
    final p = profile ?? _profile();
    final cls = const RuleBasedClassifier().classify(p);
    return ChatContext(profile: p, classification: cls, plan: PlanGenerator(db).generate(p, cls), db: db, consumedKcal: consumed, history: history, now: _now);
  }

  ProgressSnapshot progress(ChatContext base, {Map<String, ActivityEntry>? activity, Map<String, double>? kcal}) => ProgressSnapshot.build(
        today: _now,
        plannedWeekdays: ProgressService.plannedWeekdays(base.plan!),
        targetKcal: base.plan!.nutrition.targetKcal,
        activity: activity ??
            {
              '2026-10-12': const ActivityEntry('2026-10-12', 40, 250),
              '2026-10-10': const ActivityEntry('2026-10-10', 35, 200),
              '2026-10-08': const ActivityEntry('2026-10-08', 30, 180),
            },
        kcalByDate: kcal ?? {'2026-10-08': 2100, '2026-10-09': 1900, '2026-10-12': 2000, '2026-10-13': 1500, '2026-10-14': 900},
      );

  Map<String, List<FoodEntry>> meals() => {
        '2026-10-14': [_e('2026-10-14', 'Breakfast', 'Oatmeal', 332, protein: 12), _e('2026-10-14', 'Snack', 'Banana', 105, protein: 1)],
        '2026-10-13': [_e('2026-10-13', 'Dinner', 'Chicken biryani', 480, protein: 24), _e('2026-10-13', 'Snack', 'Apple', 95, protein: 0)],
        '2026-10-12': <FoodEntry>[],
      };

  ChatHistory full(ChatContext base, {List<WeightPoint>? weights}) => ChatHistory(
        entriesByDate: meals(),
        progress: progress(base),
        weights: weights ??
            [
              WeightPoint(DateTime(2026, 9, 18), 62.0),
              WeightPoint(DateTime(2026, 9, 25), 61.6),
              WeightPoint(DateTime(2026, 10, 2), 61.3),
              WeightPoint(DateTime(2026, 10, 9), 61.0),
              WeightPoint(DateTime(2026, 10, 13), 60.8),
            ],
      );

  group('answers come from the user\'s own history', () {
    test('weekly summary uses the real week and names the weakest area', () {
      final base = build();
      final ctx = build(history: full(base));
      final w = ctx.history.progress!.week;
      final r = bot.respond('how am I doing this week?', ctx);
      expect(r.intent, 'week_summary');
      expect(r.text, contains('${w.total.round()}/100'));
      expect(r.text, contains('${w.workoutsDone} of ${w.workoutsPlanned} planned days done'));
      expect(r.text, contains('${w.daysLogged} of ${w.daysElapsed} days'));
      expect(r.text, contains('Your lowest area'));
    });

    test('when the logs cannot be read it says so instead of inventing numbers', () {
      final ctx = build(); // no history at all
      for (final q in ['how am I doing this week', 'what did I eat today', 'what is my workout streak', 'when was my last workout', 'how have I been eating', "how's my weight progress"]) {
        final r = bot.respond(q, ctx);
        expect(r.text, contains('can\'t read'), reason: q);
      }
    });

    test('streaks and badges name what was earned and what is next', () {
      final base = build();
      final ctx = build(history: full(base));
      final r = bot.respond('what are my badges and streak', ctx);
      expect(r.intent, 'streaks_badges');
      expect(r.text, contains('workouts in a row'));
      expect(r.text, contains('Badges earned'));
      expect(r.text, contains('Next up:'));
    });

    test('last workout is dated, counted and flags missed sessions', () {
      final base = build();
      final ctx = build(history: full(base));
      final r = bot.respond('when was my last workout', ctx);
      expect(r.intent, 'last_workout');
      expect(r.text, contains('2 days ago')); // 12 Oct, today is the 14th
      expect(r.text, contains('Monday'));
      expect(r.text, contains('Last 4 weeks: 3 workouts'));
      expect(r.text, contains('105 minutes'));
      final none = build(history: ChatHistory(progress: progress(base, activity: {}), entriesByDate: meals()));
      expect(bot.respond('did I work out', none).text, contains('can\'t see a completed workout'));
    });

    test('what did I eat: today, yesterday, and nothing', () {
      final base = build();
      final ctx = build(history: full(base));
      final today = bot.respond('what did I eat today', ctx);
      expect(today.intent, 'ate_log');
      expect(today.text, contains('Breakfast: Oatmeal (332 kcal)'));
      expect(today.text, contains('Snack: Banana (105 kcal)'));
      expect(today.text, contains('Total: 437 of ${base.plan!.nutrition.targetKcal} kcal'));
      final yday = bot.respond('what did I eat yesterday?', ctx);
      expect(yday.text, contains('Dinner: Chicken biryani (480 kcal)'));
      expect(yday.text, contains('yesterday'));
      final empty = build(history: ChatHistory(entriesByDate: {'2026-10-14': <FoodEntry>[]}, progress: progress(base)));
      expect(bot.respond('what have I eaten', empty).text, contains('not logged any food today'));
    });

    test('macros are today\'s logged totals against the plan\'s targets', () {
      final base = build();
      final ctx = build(history: full(base));
      final n = base.plan!.nutrition;
      final r = bot.respond('how much protein have I had', ctx);
      expect(r.intent, 'macros');
      expect(r.text, contains('Protein: 13 of ${n.proteinG} g (${n.proteinG - 13} g to go)'));
      expect(r.text, contains('Carbs: 80 of ${n.carbsG} g'));
    });

    test('eating trend averages the logged days of the last week against the target', () {
      final base = build();
      final ctx = build(history: full(base));
      final r = bot.respond('how have I been eating this week', ctx);
      expect(r.intent, 'eating_trend');
      // logged in the last 7 days (8-14 Oct): 8th 2100, 9th 1900, 12th 2000, 13th 1500, 14th 900 -> 5 days, average 1680
      expect(r.text, contains('logged food on 5 days'));
      expect(r.text, contains('averaging 1680 kcal'));
      expect(r.text, contains('Your highest day was Thursday at 2100 kcal'));
    });

    test('weight progress uses the weigh-ins, the trend and the distance to the target', () {
      final base = build();
      final ctx = build(history: full(base));
      final r = bot.respond('how much have I lost so far', ctx);
      expect(r.intent, 'weight_progress');
      expect(r.text, contains('60.8 kg (yesterday)'));
      expect(r.text, contains('-1.2 kg'));
      expect(r.text, contains('Your trend is -'));
      expect(r.text, contains('0.8 kg above your target of 60.0 kg'));
    });

    test('weight going the wrong way for the goal is said plainly', () {
      final base = build();
      final up = [for (var i = 0; i < 5; i++) WeightPoint(DateTime(2026, 9, 18).add(Duration(days: i * 7)), 60 + i * 0.5)];
      final r = bot.respond('weight trend', build(history: full(base, weights: up)));
      expect(r.text, contains('wrong direction'));
    });

    test('no weigh-ins: it says so and points to the log', () {
      final base = build();
      final r = bot.respond('my weight progress', build(history: ChatHistory(weights: const [], progress: progress(base))));
      expect(r.text, contains('do not see any weigh-ins'));
      expect(r.actions.map((a) => a.type), contains('calorie'));
    });

    test('target explanation: formula only, and adjusted from the user\'s own logs', () {
      final base = build();
      final plain = bot.respond('why is my target what it is', build(history: full(base)));
      expect(plain.text, contains('Mifflin-St Jeor'));
      final adapted = bot.respond(
        'why is my calorie target adjusted',
        build(
          history: ChatHistory(
            estimate: const CalorieEstimate(status: EstimateStatus.adapted, priorTdee: 2000, tdee: 2190, reason: 'Your logs suggest you burn more than the formula says.'),
          ),
        ),
      );
      expect(adapted.intent, 'target_explain');
      expect(adapted.text, contains('+190 kcal'));
      expect(adapted.text, contains('Your logs suggest'));
    });
  });

  group('existing answers now use the history', () {
    test('calories left comes from the food log, with protein', () {
      final base = build();
      final ctx = build(history: full(base), consumed: 9999); // the log wins over the old counter
      final r = bot.respond('how many calories left', ctx);
      final target = base.plan!.nutrition.targetKcal;
      expect(r.text, contains('437 of $target kcal'));
      expect(r.text, contains('${target - 437} kcal left'));
      expect(r.text, contains('Protein so far: 13 of'));
    });

    test('a meal suggestion mentions what is already logged and the calories left', () {
      final base = build();
      final r = bot.respond('what should I have for breakfast', build(history: full(base)));
      expect(r.intent, 'meal');
      expect(r.text, contains('You already logged Oatmeal for Breakfast today (332 kcal)'));
      expect(r.text, contains('kcal left today'));
    });

    test('can I eat shows what it does to today\'s calories', () {
      final base = build();
      final r = bot.respond('can I eat banana', build(history: full(base)));
      expect(r.intent, 'can_eat');
      expect(r.text, contains('of the ${base.plan!.nutrition.targetKcal - 437} kcal you have left today'));
    });

    test('the greeting carries a line about today', () {
      final base = build();
      final r = bot.respond('hello', build(history: full(base)));
      expect(r.intent, 'greeting');
      expect(r.text, contains('Today so far: 437 of ${base.plan!.nutrition.targetKcal} kcal eaten'));
    });

    test('today\'s workout says when it is already done and how the week is going', () {
      final base = build();
      final plan = base.plan!;
      // find a weekday with a workout and pretend today is that day, already done
      final weekday = List.generate(7, (i) => i + 1).firstWhere((d) => plan.week[d - 1] != null);
      final day = DateTime(2026, 10, 12).add(Duration(days: weekday - 1)); // a date in that weekday
      final snap = ProgressSnapshot.build(
        today: day,
        plannedWeekdays: ProgressService.plannedWeekdays(plan),
        targetKcal: plan.nutrition.targetKcal,
        activity: {'${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}': ActivityEntry('x', 30, 150)},
        kcalByDate: const {},
      );
      final ctx = ChatContext(profile: base.profile, classification: base.classification, plan: plan, db: db, history: ChatHistory(progress: snap), now: day);
      final r = bot.respond("what's my workout today", ctx);
      expect(r.text, contains('already marked today\'s workout as done'));
      expect(r.text, contains('planned workouts done'));
    });
  });

  group('routing and safety are unchanged', () {
    test('specific phrases beat general ones, and the old intents still win their own phrases', () {
      final base = build();
      final ctx = build(history: full(base));
      expect(bot.respond('what did I eat yesterday', ctx).intent, 'ate_log');
      expect(bot.respond('how much have I eaten today', ctx).intent, 'remaining');
      expect(bot.respond('what is my bmi', ctx).intent, 'bmi');
      expect(bot.respond('what should I eat for lunch', ctx).intent, 'meal');
      expect(bot.respond('how many calories in biryani', ctx).intent, 'calorie_lookup');
    });

    test('symptoms are still answered first, whatever the history says', () {
      final base = build();
      final r = bot.respond('I have chest pain', build(history: full(base)));
      expect(r.intent, 'emergency');
    });

    test('suggestions follow the user\'s situation', () {
      final base = build();
      final withLog = ChatbotEngine.suggestionsFor(build(history: full(base)));
      expect(withLog, contains('How am I doing this week?'));
      expect(withLog, contains('What did I eat today?'));
      expect(withLog.length, lessThanOrEqualTo(6));
      final noLog = ChatbotEngine.suggestionsFor(build(history: ChatHistory(entriesByDate: {'2026-10-14': <FoodEntry>[]}, progress: progress(base))));
      expect(noLog.any((s) => s.startsWith('What should I eat for')), isTrue);
      expect(noLog, isNot(contains('What did I eat today?')));
      expect(ChatbotEngine.suggestionsFor(build()).length, greaterThanOrEqualTo(3));
    });
  });

  testWidgets('chat screen: loads the user\'s logs, greets with today\'s numbers and answers from them', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => UserSession.instance.setProfile(_profile()));
    addTearDown(UserSession.instance.clear);
    final base = build();
    // the screen reads the real clock, so the history is keyed by the real "today"
    final today = DateTime.now();
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final snap = ProgressSnapshot.build(today: today, plannedWeekdays: ProgressService.plannedWeekdays(base.plan!), targetKcal: base.plan!.nutrition.targetKcal, activity: const {}, kcalByDate: const {});
    final history = ChatHistory(
      entriesByDate: {key(today): [_e(key(today), 'Breakfast', 'Oatmeal', 332, protein: 12), _e(key(today), 'Snack', 'Banana', 105, protein: 1)]},
      progress: snap,
    );
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: ChatbotScreen(historyLoader: () async => history)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Today so far'), findsOneWidget);
    expect(find.text('How am I doing this week?'), findsOneWidget); // a suggestion built from the user's data
    await tester.enterText(find.byType(TextField), 'what did I eat today');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Oatmeal (332 kcal)'), findsOneWidget);
  });
}

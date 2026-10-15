import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/app_notification.dart';
import 'package:app/models/food.dart';
import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/services/community_service.dart';
import 'package:app/services/diet_summary.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/gamification.dart';
import 'package:app/services/inbox_service.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/login_guard.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/recommendations.dart';
import 'package:app/services/progress_service.dart';
import 'package:app/services/user_settings_service.dart';
import 'package:app/utils/validators.dart';

DayRecord day(DateTime d, {bool planned = false, bool done = false, bool logged = false}) =>
    DayRecord(date: d, planned: planned, workoutDone: done, foodLogged: logged, kcal: logged ? 2000 : null, targetKcal: 2000);

List<DayRecord> run(DateTime last, List<bool> activeOldestFirst) {
  final n = activeOldestFirst.length;
  return [for (var i = 0; i < n; i++) day(last.subtract(Duration(days: n - 1 - i)), done: activeOldestFirst[i])];
}

void main() {
  group('Validators (scope mockups M2, M3, M4, M6)', () {
    test('full name: letters only, 2+ characters', () {
      expect(Validators.fullName(''), isNotNull);
      expect(Validators.fullName('A'), isNotNull);
      expect(Validators.fullName('Ali123'), isNotNull);
      expect(Validators.fullName("Aamna Rasheed Khan"), isNull);
      expect(Validators.fullName("O'Brien-Smith"), isNull);
    });
    test('email', () {
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('name@example.com'), isNull);
    });
    test('password needs 8 chars, uppercase, number and symbol', () {
      expect(Validators.password('Ab1!'), isNotNull);
      expect(Validators.password('abcdefg1!'), isNotNull);
      expect(Validators.password('Abcdefgh!'), isNotNull);
      expect(Validators.password('Abcdefg1'), isNotNull);
      expect(Validators.password('Abcdef1!'), isNull);
      expect(Validators.confirmPassword('Abcdef1!', 'Abcdef1?'), isNotNull);
      expect(Validators.confirmPassword('Abcdef1!', 'Abcdef1!'), isNull);
    });
    test('date of birth: at least 13 on the given day', () {
      final now = DateTime(2026, 10, 15);
      expect(Validators.dateOfBirth(null, now: now), isNotNull);
      expect(Validators.dateOfBirth(DateTime(2013, 10, 16), now: now), isNotNull); // turns 13 tomorrow
      expect(Validators.dateOfBirth(DateTime(2013, 10, 15), now: now), isNull);
      expect(Validators.dateOfBirth(DateTime(1900, 1, 1), now: now), isNotNull);
    });
    test('height and weight ranges in both units', () {
      expect(Validators.height('49', 'cm'), isNotNull);
      expect(Validators.height('301', 'cm'), isNotNull);
      expect(Validators.height('170', 'cm'), isNull);
      expect(Validators.height('5.6', 'ft'), isNull);
      expect(Validators.height('abc', 'cm'), isNotNull);
      expect(Validators.weight('19', 'kg'), isNotNull);
      expect(Validators.weight('501', 'kg'), isNotNull);
      expect(Validators.weight('70', 'kg'), isNull);
      expect(Validators.weight('150', 'lbs'), isNull);
      expect(Validators.weight('30', 'lbs'), isNotNull);
    });
    test('target weight: optional, near current or a healthy BMI', () {
      String? t(String v) => Validators.targetWeight(v, 'kg', currentKg: 90, heightCm: 170);
      expect(t(''), isNull);
      expect(t('abc'), isNotNull);
      expect(t('80'), isNull); // within 15% of 90 kg
      expect(t('60'), isNull); // BMI 20.8
      expect(t('45'), isNotNull); // BMI 15.6, underweight
      expect(Validators.targetWeight('70', 'kg', currentKg: 140, heightCm: 170), isNull); // far from now, but a healthy BMI (24.2)
      expect(Validators.targetWeight('95', 'kg', currentKg: 140, heightCm: 170), isNotNull); // BMI 32.9 and not within 15%
    });
  });

  group('LoginGuard (5 failures lock for 15 minutes)', () {
    test('locks on the fifth failure and unlocks after 15 minutes', () {
      var now = DateTime(2026, 10, 15, 9);
      final g = LoginGuard(now: () => now);
      for (var i = 1; i <= 4; i++) {
        expect(g.recordFailure('A@x.com'), 5 - i);
        expect(g.lockedFor('a@x.com'), isNull);
      }
      expect(g.recordFailure('a@x.com'), 0);
      expect(g.lockedFor('A@X.COM'), isNotNull);
      now = now.add(const Duration(minutes: 14, seconds: 59));
      expect(g.lockedFor('a@x.com'), isNotNull);
      now = now.add(const Duration(seconds: 2));
      expect(g.lockedFor('a@x.com'), isNull);
      expect(g.recordFailure('a@x.com'), 4); // the counter restarted
    });
    test('a success clears the count, other emails are unaffected', () {
      final g = LoginGuard(now: () => DateTime(2026, 10, 15));
      for (var i = 0; i < 4; i++) {
        g.recordFailure('a@x.com');
      }
      g.recordSuccess('a@x.com');
      expect(g.recordFailure('a@x.com'), 4);
      for (var i = 0; i < 5; i++) {
        g.recordFailure('b@x.com');
      }
      expect(g.lockedFor('a@x.com'), isNull);
      expect(g.lockedFor('b@x.com'), isNotNull);
    });
  });

  group('Streaks, XP and the new badges', () {
    final today = DateTime(2026, 10, 15);
    test('active streak counts workout or meal days; today may still be empty', () {
      expect(Gamification.activeStreak(run(today, [true, true, true])), 3);
      expect(Gamification.activeStreak(run(today, [true, true, false])), 2); // today not over yet
      expect(Gamification.activeStreak(run(today, [true, false, true])), 1); // yesterday broke it
      final mixed = [day(today.subtract(const Duration(days: 1)), logged: true), day(today, done: true)];
      expect(Gamification.activeStreak(mixed), 2);
      expect(Gamification.bestActiveStreak(run(today, [true, true, false, true, true, true, false])), 3);
    });
    test('7 and 30 day streak badges', () {
      final seven = Gamification.earnedBadgeIds(run(today, List.filled(7, true)), today);
      expect(seven, contains('daily_7'));
      expect(seven, isNot(contains('daily_30')));
      final thirty = Gamification.earnedBadgeIds(run(today, List.filled(30, true)), today);
      expect(thirty, containsAll(['daily_7', 'daily_30']));
      expect(Gamification.earnedBadgeIds(run(today, List.filled(6, true)), today), isNot(contains('daily_7')));
      expect(Gamification.catalogue.length, 10);
    });
    test('XP levels: level L starts at 100*L*(L-1)', () {
      expect(Xp.levelOf(0), 1);
      expect(Xp.levelOf(199), 1);
      expect(Xp.levelOf(200), 2);
      expect(Xp.levelOf(599), 2);
      expect(Xp.levelOf(600), 3);
      expect(Xp.toNext(150), 50);
      expect(Xp.progress(0), 0);
      expect(Xp.progress(100), closeTo(0.5, 1e-9));
      expect(Xp.total(workoutDays: 2, mealDays: 3, badges: 1), 2 * 50 + 3 * 10 + 100);
    });
  });

  group('Diet summary rules', () {
    test('macro shares always add up to 100', () {
      for (final g in [(30.0, 100.0, 20.0), (1.0, 1.0, 1.0), (50.0, 0.0, 0.0), (33.3, 66.6, 12.1)]) {
        final m = MacroShare.fromGrams(protein: g.$1, carbs: g.$2, fat: g.$3);
        expect(m.protein + m.carbs + m.fat, 100, reason: '$g');
      }
      expect(MacroShare.fromGrams(protein: 0, carbs: 0, fat: 0).isEmpty, isTrue);
      final fatOnly = MacroShare.fromGrams(protein: 0, carbs: 0, fat: 10);
      expect(fatOnly.fat, 100);
    });
    test('calories by meal and net calories', () {
      FoodEntry e(String meal, double kcal) =>
          FoodEntry(date: '2026-10-15', meal: meal, name: 'x', quantity: 1, unit: 'serving', kcal: kcal, protein: 0, carbs: 0, fat: 0);
      final by = kcalByMeal([e('Breakfast', 300), e('Lunch', 500), e('Breakfast', 100)]);
      expect(by['Breakfast'], 400);
      expect(by['Lunch'], 500);
      expect(by['Dinner'], 0);
      expect(netKcal(consumed: 1800, burned: 350), 1450);
    });
    test('verdict never praises a very low intake', () {
      final low = dailyVerdict(goal: 'Lose Weight', consumed: 600, target: 1800, bmr: 1500);
      expect(low, contains('very low intake'));
      expect(dailyVerdict(goal: 'Lose Weight', consumed: 0, target: 1800, bmr: 1500), contains('Nothing is logged'));
      expect(dailyVerdict(goal: 'Lose Weight', consumed: 1790, target: 1800, bmr: 1500), contains('right on your daily target'));
      expect(dailyVerdict(goal: 'Lose Weight', consumed: 1400, target: 1800, bmr: 1200), contains('under your daily target'));
      expect(dailyVerdict(goal: 'Gain Muscle', consumed: 1900, target: 2600, bmr: 1500), contains('short of your target'));
    });
  });

  group('Rotating nutrition tips', () {
    final pool = [for (var i = 0; i < 28; i++) 'tip $i'];
    final plan = NutritionPlan(
        goalLabel: 'x', targetKcal: 2000, proteinG: 100, carbsG: 200, fatG: 60, waterLitres: 2, meals: const {}, avoid: const [], tips: const [], tipPool: pool);
    test('three tips a day, none repeats within a week, and the same day gives the same tips', () {
      final start = DateTime(2026, 10, 15);
      final seen = <String>{};
      for (var d = 0; d < 7; d++) {
        final t = plan.tipsFor(start.add(Duration(days: d)));
        expect(t.length, 3);
        for (final x in t) {
          expect(seen.add(x), isTrue, reason: 'tip "$x" repeated on day $d');
        }
      }
      expect(plan.tipsFor(start), plan.tipsFor(DateTime(2026, 10, 15, 22)));
      expect(plan.tipsFor(start), isNot(plan.tipsFor(start.add(const Duration(days: 1)))));
    });
    test('an empty pool gives no tips', () {
      final empty = NutritionPlan(goalLabel: 'x', targetKcal: 1, proteinG: 1, carbsG: 1, fatG: 1, waterLitres: 1, meals: const {}, avoid: const [], tips: const []);
      expect(empty.tipsFor(DateTime(2026, 10, 15)), isEmpty);
    });
  });

  group('Weekly reset countdown', () {
    test('next reset is the next Monday 00:00', () {
      expect(CommunityService.nextReset(DateTime(2026, 10, 15, 10)), DateTime(2026, 10, 19));
      expect(CommunityService.nextReset(DateTime(2026, 10, 12)), DateTime(2026, 10, 19)); // Monday itself
    });
    test('wording', () {
      expect(CommunityService.resetsIn(DateTime(2026, 10, 15, 19)), 'Resets in 3d 5h');
      expect(CommunityService.resetsIn(DateTime(2026, 10, 18, 18, 40)), 'Resets in 5h 20m');
      expect(CommunityService.resetsIn(DateTime(2026, 10, 18, 23, 48)), 'Resets in 12m');
      expect(CommunityService.weekNumber(DateTime(2026, 10, 15)), 42);
    });
  });

  group('Due reminders for the notification inbox', () {
    final today = DateTime(2026, 10, 15, 19, 0);
    ProgressSnapshot snap({required bool done, required bool logged, Inactivity? inactive}) {
      final t = Gamification.dateOnly(today);
      final days = [for (var i = 2; i >= 0; i--) day(t.subtract(Duration(days: i)), planned: true, done: done, logged: logged)];
      return ProgressSnapshot(
        today: t,
        days: days,
        week: Gamification.weeklyScore(days),
        weeks: const [],
        level: FitnessLevel.beginner,
        workoutStreak: 0,
        loggingStreak: 0,
        activeStreak: 0,
        lastWorkout: null,
        inactivity: inactive,
        earnedNow: const {},
        earned: const {},
        newBadges: const {},
      );
    }

    const on = UserSettings(reminderEnabled: true, reminderHour: 18, mealReminderEnabled: true, mealReminderHour: 20, inactivityAlerts: true);

    test('workout reminder is due after the reminder time; meal reminder only after its own time', () {
      final items = InboxService.dueItems(now: today, progress: snap(done: false, logged: false), settings: on);
      final ids = items.map((i) => i.id).toSet();
      expect(ids, contains('wr-2026-10-15'));
      expect(ids, contains('wr-2026-10-14'));
      expect(ids, isNot(contains('ml-2026-10-15'))); // 20:00 has not come yet
      expect(ids, contains('ml-2026-10-14'));
    });
    test('nothing is due when the user did the work, or the reminders are off', () {
      expect(InboxService.dueItems(now: today, progress: snap(done: true, logged: true), settings: on), isEmpty);
      expect(InboxService.dueItems(now: today, progress: snap(done: false, logged: false), settings: const UserSettings()), isEmpty);
    });
    test('inactivity item appears once per day and ids are stable', () {
      final s = snap(done: true, logged: true, inactive: const Inactivity(5, 2));
      final a = InboxService.dueItems(now: today, progress: s, settings: on);
      final b = InboxService.dueItems(now: today.add(const Duration(minutes: 5)), progress: s, settings: on);
      expect(a.single.type, NotificationType.inactivity);
      expect(a.single.id, b.single.id);
    });
    test('badge notification names the badge and its id is stable', () {
      final n = InboxService.badge('daily_7', today);
      expect(n.id, 'badge-daily_7');
      expect(n.title, contains('7-Day Streak'));
    });
  });

  group('Searchable food list (team list + INDB + USDA)', () {
    final bulkJson = File('assets/data/foods_bulk.json').readAsStringSync();
    final curatedJson = File('assets/data/foods.json').readAsStringSync();
    final db = FoodDatabase.fromJsonString(curatedJson, bulkJson: bulkJson);
    final bulk = db.items.where((i) => i.isBulk).toList();

    test('more than 2,500 foods, ids unique, all three sources present', () {
      expect(db.items.length, greaterThan(2500));
      expect(db.items.map((i) => i.id).toSet().length, db.items.length);
      expect(bulk.map((i) => i.source).toSet(), {'calorica', 'indb', 'usda'});
    });
    test('every listed food has sane numbers, no meal slot and estimated allergens', () {
      for (final f in bulk) {
        expect(f.meals, isEmpty, reason: f.name);
        expect(f.allergensEstimated, isTrue);
        expect(f.grams, greaterThan(0), reason: f.name);
        expect(f.kcal, greaterThanOrEqualTo(0), reason: f.name);
        expect(f.kcal / f.grams * 100, lessThanOrEqualTo(905), reason: f.name);
        expect(f.ref.length, lessThanOrEqualTo(40), reason: f.name); // the database rule on a food-log entry's ref
        expect(f.sourceLabel, isNotEmpty);
      }
    });
    test('every USDA food names its FDC id; Indian Databank rows agree with their own macros', () {
      for (final f in bulk.where((i) => i.fromUsda)) {
        expect(f.fdcId, isNotNull, reason: f.name);
        expect(f.ref, 'usda:${f.fdcId}');
      }
      for (final f in bulk.where((i) => i.source == 'indb')) {
        final est = 4 * f.protein + 4 * f.carbs + 9 * f.fat;
        if (f.kcal >= 10 && est > 0) expect((f.kcal - est).abs() / f.kcal, lessThan(0.36), reason: f.name);
      }
    });
    test('source labels never claim more than the data says', () {
      final curatedRow = bulk.firstWhere((i) => i.source == 'calorica' && (i.sourceNote ?? '').startsWith('CURATED'));
      expect(curatedRow.sourceLabel, contains('no outside source'));
      expect(bulk.firstWhere((i) => i.source == 'indb').sourceLabel, contains('Indian Nutrient Databank'));
      expect(bulk.firstWhere((i) => i.fromUsda).sourceTag, 'USDA');
    });
    test('a listed food never replaces a curated one, and none reaches meal plans', () {
      final curated = (jsonDecode(curatedJson) as List).map((e) => FoodItem.fromJson(e as Map<String, dynamic>)).toList();
      for (final c in curated) {
        expect(db.items.where((i) => i.id == c.id).single.isBulk, isFalse);
      }
      expect(db.items.where((i) => i.isBulk && i.meals.isNotEmpty), isEmpty);
    });
    test('search finds foods by Pakistani / Indian names and by USDA names, curated first on a tie', () {
      expect(db.search('abiyuch').map((i) => i.name), contains('Abiyuch, raw'));
      final chawal = db.search('chawal', limit: 12);
      expect(chawal, isNotEmpty);
      expect(chawal.any((i) => i.name.toLowerCase().contains('rice')), isTrue);
      expect(db.search('rice').first.isBulk, isFalse);
      expect(db.search('khichdi'), isNotEmpty);
    });
    test('search over the whole list stays fast', () {
      final watch = Stopwatch()..start();
      for (final q in ['chicken', 'biryani', 'daal', 'apple', 'milk tea', 'paratha', 'xyzzy']) {
        db.search(q);
      }
      expect(watch.elapsedMilliseconds / 7, lessThan(150)); // average per search, in debug test mode
    });
    test('a damaged list leaves the curated catalogue intact', () {
      final broken = FoodDatabase.fromJsonString(curatedJson, bulkJson: '{not json');
      expect(broken.items.any((i) => i.isBulk), isFalse);
      expect(broken.items.length, lessThan(200));
    });
    test('common allergens are caught by name (over-warning is intended)', () {
      final milk = bulk.firstWhere((i) => i.fromUsda && i.name.toLowerCase().startsWith('milk'));
      expect(milk.allergens, contains('dairy'));
      for (final p in bulk.where((i) => i.name.toLowerCase().contains('peanut'))) {
        expect(p.allergens, contains('nuts'), reason: p.name);
      }
      for (final p in bulk.where((i) => RegExp(r'\b(naan|roti|chapati|paratha)\b', caseSensitive: false).hasMatch(i.name))) {
        expect(p.allergens, contains('gluten'), reason: p.name);
      }
    });
  });

  group('Recommended actions on the classification result (Module 2)', () {
    late FoodDatabase db;
    const classifier = RuleBasedClassifier();
    setUpAll(() {
      ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
      db = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
    });

    HealthProfile p({List<String> conditions = const [], double weight = 70, String goal = 'Maintain & Stay Fit'}) => HealthProfile(
        fullName: 'Test User',
        dob: '1996-01-01',
        gender: 'Female',
        heightValue: 165,
        weightValue: weight,
        medicalConditions: conditions,
        foodAllergies: const [],
        primaryGoal: goal,
        activityLevel: 'Lightly Active',
        workoutFrequency: 4);

    List<RecommendedAction> actionsFor(HealthProfile profile) {
      final cls = classifier.classify(profile);
      return recommendedActions(profile, cls, PlanGenerator(db).generate(profile, cls));
    }

    test('every user gets exercise, calorie and water actions with the numbers from their own plan', () {
      final profile = p(goal: 'Lose Weight');
      final cls = classifier.classify(profile);
      final plan = PlanGenerator(db).generate(profile, cls);
      final titles = recommendedActions(profile, cls, plan).map((a) => a.title).toList();
      expect(titles.first, contains('${plan.workoutDays}x a week'));
      expect(titles.any((t) => t.contains('deficit') || t.contains('Eat around')), isTrue);
      expect(titles.any((t) => t.contains('water')), isTrue);
    });
    test('condition advice appears only for the matching condition and defers to the doctor', () {
      expect(actionsFor(p()).map((a) => a.title), isNot(contains('Spread carbohydrates across your meals')));
      final diabetic = actionsFor(p(conditions: ['Diabetes'])).map((a) => a.title);
      expect(diabetic, contains('Spread carbohydrates across your meals'));
      expect(diabetic, contains('Talk to your doctor before you begin'));
      expect(actionsFor(p(conditions: ['Hypertension'])).map((a) => a.title), contains('Keep salt under 5 g a day'));
      expect(actionsFor(p(conditions: ['Asthma'])).map((a) => a.title), contains('Warm up well and keep your reliever close'));
    });
  });
}

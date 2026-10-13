import 'dart:math';

/// Module 11 (Community Ranking & Gamification) rules. Pure Dart: no Firebase, so every rule is unit-tested.
///
/// The weights, tolerances and level thresholds below are design choices of the project team; they are not
/// taken from a published standard (see Profile → Sources & methodology).

/// One calendar day of the user's activity as the score and badge rules see it.
class DayRecord {
  /// Local calendar date (time of day ignored).
  final DateTime date;

  /// The weekly plan has a workout on this weekday.
  final bool planned;
  final bool workoutDone;
  final int minutes;
  final bool foodLogged;

  /// Total calories logged that day (null when nothing was logged) and the user's daily target.
  final double? kcal;
  final int? targetKcal;

  const DayRecord({
    required this.date,
    this.planned = false,
    this.workoutDone = false,
    this.minutes = 0,
    this.foodLogged = false,
    this.kcal,
    this.targetKcal,
  });

  /// Logged calories within ±[Gamification.calorieTolerance] of the target.
  /// A day with only part of the meals logged usually falls outside it, which is why logging comes first.
  bool get withinTarget {
    final k = kcal, t = targetKcal;
    if (k == null || t == null || t <= 0) return false;
    return (k - t).abs() <= t * Gamification.calorieTolerance;
  }
}

/// A weekly fitness score from 0 to 100 (FR-1) and the parts it is made of.
class FitnessScore {
  final double total;

  /// Each part is 0..1; [training] is null when no planned workout day has passed yet this week.
  final double? training;
  final double logging;
  final double adherence;
  final int workoutsDone;
  final int workoutsPlanned;
  final int daysLogged;
  final int daysOnTarget;
  final int daysElapsed;

  const FitnessScore({
    required this.total,
    required this.training,
    required this.logging,
    required this.adherence,
    required this.workoutsDone,
    required this.workoutsPlanned,
    required this.daysLogged,
    required this.daysOnTarget,
    required this.daysElapsed,
  });

  static const empty = FitnessScore(
      total: 0, training: null, logging: 0, adherence: 0, workoutsDone: 0, workoutsPlanned: 0, daysLogged: 0, daysOnTarget: 0, daysElapsed: 0);
}

enum FitnessLevel { beginner, intermediate, advanced }

extension FitnessLevelLabel on FitnessLevel {
  String get label => const ['Beginner', 'Intermediate', 'Advanced'][index];
}

class AppBadge {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool earned;
  const AppBadge(this.id, this.emoji, this.title, this.description, {this.earned = false});

  AppBadge copyWith({bool? earned}) => AppBadge(id, emoji, title, description, earned: earned ?? this.earned);
}

class Gamification {
  Gamification._();

  /// Score weights (percent): training consistency, food logging, calorie-target adherence. Team design choice.
  static const weightTraining = 50.0;
  static const weightLogging = 25.0;
  static const weightAdherence = 25.0;

  /// A logged day counts as "on target" within ±15% of the calorie target. Team design choice.
  static const calorieTolerance = 0.15;

  /// Beginner below [intermediateFrom], Advanced from [advancedFrom] (average weekly score). Team design choice.
  static const intermediateFrom = 40.0;
  static const advancedFrom = 70.0;

  /// K-Means needs enough users to mean anything; below this the thresholds above are used.
  static const minCohortForKMeans = 15;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday of the week containing [d].
  static DateTime weekStart(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

  /// ISO-8601 week id such as `2026-W42` (weeks start on Monday; week 1 contains the first Thursday).
  static String isoWeekId(DateTime d) {
    final date = DateTime.utc(d.year, d.month, d.day);
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final week = thursday.difference(jan1).inDays ~/ 7 + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// FR-1: weighted fitness score for the days of one week that have already happened.
  static FitnessScore weeklyScore(List<DayRecord> elapsedDays) {
    if (elapsedDays.isEmpty) return FitnessScore.empty;
    final elapsed = elapsedDays.length;
    final plannedElapsed = elapsedDays.where((d) => d.planned).length;
    final done = elapsedDays.where((d) => d.workoutDone).length;
    final logged = elapsedDays.where((d) => d.foodLogged).length;
    final onTarget = elapsedDays.where((d) => d.foodLogged && d.withinTarget).length;

    final double? training = plannedElapsed == 0 ? null : min(1.0, done / plannedElapsed);
    final logging = logged / elapsed;
    final adherence = logged == 0 ? 0.0 : onTarget / logged;

    var points = weightLogging * logging + weightAdherence * adherence;
    var weights = weightLogging + weightAdherence;
    if (training != null) {
      points += weightTraining * training;
      weights += weightTraining;
    }
    return FitnessScore(
      total: (100 * points / weights).clamp(0, 100).toDouble(),
      training: training,
      logging: logging,
      adherence: adherence,
      workoutsDone: done,
      workoutsPlanned: plannedElapsed,
      daysLogged: logged,
      daysOnTarget: onTarget,
      daysElapsed: elapsed,
    );
  }

  /// Weekly scores for the weeks that overlap [days] (oldest → newest, Monday-based weeks), counting only days up to [today].
  static List<FitnessScore> weeklyScores(List<DayRecord> days, DateTime today) {
    final t = dateOnly(today);
    final byWeek = <DateTime, List<DayRecord>>{};
    for (final d in days) {
      if (dateOnly(d.date).isAfter(t)) continue;
      byWeek.putIfAbsent(weekStart(d.date), () => []).add(d);
    }
    final starts = byWeek.keys.toList()..sort();
    return [for (final s in starts) weeklyScore(byWeek[s]!)];
  }

  /// FE-5 rule-based level from an average weekly score.
  static FitnessLevel levelForScore(double score) =>
      score >= advancedFrom ? FitnessLevel.advanced : (score >= intermediateFrom ? FitnessLevel.intermediate : FitnessLevel.beginner);

  /// Average of the weekly scores that had anything to measure (a week with no activity at all is ignored); no data → beginner.
  static FitnessLevel levelFromScores(List<FitnessScore> weeks) {
    final used = weeks.where((w) => w.daysLogged > 0 || w.workoutsDone > 0).toList();
    if (used.isEmpty) return FitnessLevel.beginner;
    return levelForScore(used.fold(0.0, (s, w) => s + w.total) / used.length);
  }

  /// Consecutive completed workouts, ending today. Rest days do not break the streak; a planned workout that was
  /// missed does, except today's which may still be done later.
  static int workoutStreak(List<DayRecord> days) {
    var streak = 0;
    for (var i = days.length - 1; i >= 0; i--) {
      final d = days[i];
      if (d.workoutDone) {
        streak++;
      } else if (d.planned && i != days.length - 1) {
        break;
      }
    }
    return streak;
  }

  /// Longest run of completed workouts anywhere in [days] (same rules as [workoutStreak]).
  static int bestWorkoutStreak(List<DayRecord> days) {
    var best = 0, run = 0;
    for (final d in days) {
      if (d.workoutDone) {
        run++;
        best = max(best, run);
      } else if (d.planned) {
        run = 0;
      }
    }
    return best;
  }

  /// Consecutive days with food logged, ending today (today not logged yet does not break it).
  static int loggingStreak(List<DayRecord> days) {
    var streak = 0;
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].foodLogged) {
        streak++;
      } else if (i != days.length - 1) {
        break;
      }
    }
    return streak;
  }

  static int bestLoggingStreak(List<DayRecord> days) {
    var best = 0, run = 0;
    for (final d in days) {
      run = d.foodLogged ? run + 1 : 0;
      best = max(best, run);
    }
    return best;
  }

  static const catalogue = <AppBadge>[
    AppBadge('first_workout', '🎯', 'First step', 'Complete your first workout.'),
    AppBadge('streak_3', '🔥', 'On a roll', 'Complete 3 planned workouts in a row.'),
    AppBadge('streak_7', '⚡', 'Unstoppable', 'Complete 7 planned workouts in a row.'),
    AppBadge('full_week', '🏅', 'Full week', 'Finish every planned workout of a week.'),
    AppBadge('logger_3', '🍽️', 'Food diary habit', 'Log your food 3 days in a row.'),
    AppBadge('logger_7', '📒', 'Week of logging', 'Log your food 7 days in a row.'),
    AppBadge('on_target_3', '🥗', 'Right on target', 'Land within 15% of your calorie target on 3 days.'),
    AppBadge('high_scorer', '⭐', 'High scorer', 'Reach a weekly fitness score of 80 or more.'),
  ];

  /// FR-3: ids of the badges earned according to [days] (oldest → newest, normally the last 28 days).
  static Set<String> earnedBadgeIds(List<DayRecord> days, DateTime today) {
    final earned = <String>{};
    if (days.any((d) => d.workoutDone)) earned.add('first_workout');
    final bestW = bestWorkoutStreak(days);
    if (bestW >= 3) earned.add('streak_3');
    if (bestW >= 7) earned.add('streak_7');
    final bestL = bestLoggingStreak(days);
    if (bestL >= 3) earned.add('logger_3');
    if (bestL >= 7) earned.add('logger_7');
    if (days.where((d) => d.foodLogged && d.withinTarget).length >= 3) earned.add('on_target_3');

    final t = dateOnly(today);
    final byWeek = <DateTime, List<DayRecord>>{};
    for (final d in days) {
      if (dateOnly(d.date).isAfter(t)) continue;
      byWeek.putIfAbsent(weekStart(d.date), () => []).add(d);
    }
    for (final week in byWeek.values) {
      final planned = week.where((d) => d.planned).toList();
      if (planned.isNotEmpty && planned.every((d) => d.workoutDone)) earned.add('full_week');
      if (weeklyScore(week).total >= 80) earned.add('high_scorer');
    }
    return earned;
  }

  /// The full badge list with the earned flag set (earned ids may come from history stored earlier).
  static List<AppBadge> badges(Set<String> earnedIds) => [for (final b in catalogue) b.copyWith(earned: earnedIds.contains(b.id))];
}

// ---------------------------------------------------------------- K-Means (FR-4)

class KMeansResult {
  final List<List<double>> centroids;
  final List<int> assignments;
  final int iterations;
  const KMeansResult(this.centroids, this.assignments, this.iterations);
}

/// Lloyd's K-Means with k-means++ seeding and a fixed seed (same data → same clusters).
KMeansResult kMeans(List<List<double>> points, int k, {int seed = 7, int maxIterations = 100}) {
  if (k < 1 || points.length < k) throw ArgumentError('Need at least k=$k points, got ${points.length}.');
  final rnd = Random(seed);
  double dist2(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      s += d * d;
    }
    return s;
  }

  // k-means++ seeding
  final centroids = <List<double>>[List<double>.from(points[rnd.nextInt(points.length)])];
  while (centroids.length < k) {
    final d2 = [for (final p in points) centroids.map((c) => dist2(p, c)).reduce(min)];
    final total = d2.fold(0.0, (a, b) => a + b);
    if (total == 0) {
      centroids.add(List<double>.from(points[rnd.nextInt(points.length)]));
      continue;
    }
    var r = rnd.nextDouble() * total;
    var pick = 0;
    for (var i = 0; i < d2.length; i++) {
      r -= d2[i];
      if (r <= 0) {
        pick = i;
        break;
      }
    }
    centroids.add(List<double>.from(points[pick]));
  }

  var assignments = List<int>.filled(points.length, -1);
  var iterations = 0;
  for (; iterations < maxIterations; iterations++) {
    var changed = false;
    for (var i = 0; i < points.length; i++) {
      var best = 0;
      var bestD = double.infinity;
      for (var c = 0; c < k; c++) {
        final d = dist2(points[i], centroids[c]);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      if (assignments[i] != best) {
        assignments[i] = best;
        changed = true;
      }
    }
    if (!changed) break;
    for (var c = 0; c < k; c++) {
      final members = [for (var i = 0; i < points.length; i++) if (assignments[i] == c) points[i]];
      if (members.isEmpty) continue; // keep the old centroid for an empty cluster
      centroids[c] = [for (var d = 0; d < points.first.length; d++) members.fold(0.0, (s, p) => s + p[d]) / members.length];
    }
  }
  return KMeansResult(centroids, assignments, iterations);
}

/// One leaderboard participant as seen by the clustering.
class CohortMember {
  final String id;
  final double score;
  final int workouts;
  final int logDays;
  const CohortMember(this.id, this.score, this.workouts, this.logDays);
}

class CohortLevels {
  final Map<String, FitnessLevel> levels;

  /// "K-Means (n users)" or "score thresholds (K-Means needs at least 15 users)".
  final String method;
  const CohortLevels(this.levels, this.method);
}

/// FR-4 + FE-5: groups the leaderboard participants as beginner / intermediate / advanced.
/// With at least [Gamification.minCohortForKMeans] people, K-Means (k=3) on score, workouts and logging days is
/// used and the three clusters are ranked by their average score; with fewer people the score thresholds are used.
CohortLevels groupCohort(List<CohortMember> members) {
  if (members.length < Gamification.minCohortForKMeans) {
    return CohortLevels({for (final m in members) m.id: Gamification.levelForScore(m.score)},
        'score thresholds (K-Means needs at least ${Gamification.minCohortForKMeans} users)');
  }
  final points = [for (final m in members) [m.score / 100, m.workouts / 7, m.logDays / 7]];
  final result = kMeans(points, 3);
  final order = List<int>.generate(3, (i) => i)..sort((a, b) => result.centroids[a][0].compareTo(result.centroids[b][0]));
  final rank = {for (var i = 0; i < 3; i++) order[i]: FitnessLevel.values[i]};
  return CohortLevels({for (var i = 0; i < members.length; i++) members[i].id: rank[result.assignments[i]]!}, 'K-Means (${members.length} users)');
}

// ---------------------------------------------------------------- inactivity (Module 14, FR-5)

class Inactivity {
  final int daysSinceWorkout;
  final int missedPlannedDays;
  const Inactivity(this.daysSinceWorkout, this.missedPlannedDays);
}

/// FR-5: the user is inactive when at least [thresholdDays] days have passed since their last workout AND at least one
/// planned workout day (not counting today) has gone by without a workout. Rest days alone never count.
/// Returns null when there is nothing to compare (no workout recorded yet) or the user is not inactive.
Inactivity? detectInactivity({
  required DateTime today,
  required DateTime? lastWorkout,
  required Set<int> plannedWeekdays,
  int thresholdDays = 3,
}) {
  if (lastWorkout == null) return null;
  final t = Gamification.dateOnly(today);
  final last = Gamification.dateOnly(lastWorkout);
  final since = t.difference(last).inDays;
  if (since < thresholdDays) return null;
  var missed = 0;
  for (var i = 1; i < since; i++) {
    if (plannedWeekdays.contains(last.add(Duration(days: i)).weekday)) missed++;
  }
  return missed == 0 ? null : Inactivity(since, missed);
}

// ---------------------------------------------------------------- reminder times (Module 14, FR-3)

/// The first moment strictly after [now] that falls on [weekday] (Mon = 1) at [hour]:[minute], in local time.
DateTime nextWeekdayAt(DateTime now, int weekday, int hour, int minute) {
  var candidate = DateTime(now.year, now.month, now.day, hour, minute);
  candidate = candidate.add(Duration(days: (weekday - candidate.weekday) % 7));
  if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 7));
  return candidate;
}

/// When to send the single "we miss you" nudge: [afterDays] days after the last workout at [hour]:00, or, if that moment
/// has passed, tomorrow at [hour]:00. Null when no workout has ever been recorded.
DateTime? inactivityNudgeAt(DateTime now, DateTime? lastWorkout, {int afterDays = 3, int hour = 18}) {
  if (lastWorkout == null) return null;
  final base = Gamification.dateOnly(lastWorkout).add(Duration(days: afterDays));
  var at = DateTime(base.year, base.month, base.day, hour);
  if (!at.isAfter(now)) {
    final tomorrow = Gamification.dateOnly(now).add(const Duration(days: 1));
    at = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour);
  }
  return at;
}

// ---------------------------------------------------------------- roles (Module 14, FR-2)

enum UserRole { user, doctor, nutritionist, trainer, admin }

enum Permission { viewOwnData, viewAssignedPatientData, editAssignedPlans, uploadPrescriptions, manageAccounts }

extension UserRoleRules on UserRole {
  /// What each role may do inside the app. The security rules in `database.rules.json` are the real enforcement: today they give
  /// nobody access to another person's data, because patient assignment belongs to Module 13 and does not exist yet.
  Set<Permission> get permissions {
    switch (this) {
      case UserRole.user:
        return {Permission.viewOwnData};
      case UserRole.doctor:
        return {Permission.viewOwnData, Permission.viewAssignedPatientData, Permission.editAssignedPlans, Permission.uploadPrescriptions};
      case UserRole.nutritionist:
      case UserRole.trainer:
        return {Permission.viewOwnData, Permission.viewAssignedPatientData, Permission.editAssignedPlans};
      case UserRole.admin:
        return {Permission.viewOwnData, Permission.manageAccounts};
    }
  }

  bool can(Permission p) => permissions.contains(p);

  String get label => const ['Member', 'Doctor', 'Nutritionist', 'Trainer', 'Administrator'][index];

  static UserRole parse(Object? value) {
    for (final r in UserRole.values) {
      if (r.name == value) return r;
    }
    return UserRole.user; // unknown or missing role never grants more than a member
  }
}

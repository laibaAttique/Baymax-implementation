import 'gamification.dart';
import 'realtime_db.dart';

/// A user's lifetime XP and level (Module 12, mockup M33).
class XpSnapshot {
  final int workoutDays;
  final int mealDays;
  final int badges;
  const XpSnapshot({this.workoutDays = 0, this.mealDays = 0, this.badges = 0});

  int get xp => Xp.total(workoutDays: workoutDays, mealDays: mealDays, badges: badges);
  int get level => Xp.levelOf(xp);
  int get toNext => Xp.toNext(xp);
  double get progress => Xp.progress(xp);
}

/// Counts what earns XP: days with a completed workout (`activity`), days with food logged (`foodDays`) and badges (`badges`).
class XpService {
  XpService._();
  static final XpService instance = XpService._();

  Future<XpSnapshot> load() {
    return RealtimeDb.guard(() async {
      Future<int> count(String child) async {
        final snap = await RealtimeDb.userRef(child).get();
        return snap.exists && snap.value is Map ? (snap.value as Map).length : 0;
      }

      final r = await Future.wait([count('activity'), count('foodDays'), count('badges')]);
      return XpSnapshot(workoutDays: r[0], mealDays: r[1], badges: r[2]);
    });
  }
}

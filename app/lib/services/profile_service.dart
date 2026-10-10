import 'package:firebase_database/firebase_database.dart';
import '../models/health_profile.dart';
import 'realtime_db.dart';

/// Saves/loads the signed-in user's health profile (Module 1) in the Realtime
/// Database at `users/{uid}/profile`.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  /// The user's saved profile, or `null` if they haven't completed profiling.
  Future<Map<String, dynamic>?> fetchMine() {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('profile').get();
      if (!snap.exists) return null;
      return Map<String, dynamic>.from(RealtimeDb.plain(snap.value) as Map);
    });
  }

  /// Creates or replaces the user's profile. Returns the user id.
  Future<String?> saveMine(HealthProfile profile) {
    return RealtimeDb.guard(() async {
      await RealtimeDb.userRef('profile').set({
        ...profile.toJson(),
        'updatedAt': ServerValue.timestamp,
      });
      return RealtimeDb.uid;
    });
  }
}

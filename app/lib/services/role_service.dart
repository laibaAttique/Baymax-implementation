import 'gamification.dart';
import 'realtime_db.dart';

/// Module 14, FR-2: the signed-in user's role, read from `roles/{uid}`.
/// Roles can only be set by an administrator in the Firebase console (the security rules refuse every write from the app),
/// so nobody can promote themselves. A missing or unreadable role means a plain member.
class RoleService {
  RoleService._();
  static final RoleService instance = RoleService._();

  Future<UserRole> fetchMine() async {
    try {
      return await RealtimeDb.guard(() async {
        final snap = await RealtimeDb.db.ref('roles/${RealtimeDb.uid}').get();
        return UserRoleRules.parse(snap.exists ? snap.value : null);
      });
    } catch (_) {
      return UserRole.user;
    }
  }
}

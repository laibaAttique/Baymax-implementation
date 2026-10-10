import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/firebase_config.dart';
import 'api_client.dart' show ApiException;
import 'auth_service.dart';

/// Access to the Firebase Realtime Database. All user data lives under
/// `users/{uid}/…`, and the security rules (`database.rules.json`) only let a
/// signed-in user read and write their own branch.
class RealtimeDb {
  RealtimeDb._();

  static const _timeout = Duration(seconds: 12);

  static FirebaseDatabase? _db;

  static FirebaseDatabase get db =>
      _db ??= FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: FirebaseConfig.databaseUrl);

  /// Call once at start-up, before any other database use.
  static void init() {
    if (kIsWeb) return;
    try {
      db.setPersistenceEnabled(true); // keeps the last known data available offline
    } catch (_) {
      // Already configured (e.g. after a hot restart).
    }
  }

  /// UID of the signed-in user; throws a 401-style error when signed out.
  static String get uid {
    final id = AuthService.instance.currentUser?.uid;
    if (id == null) throw const ApiException('You are not signed in.', statusCode: 401);
    return id;
  }

  /// `users/{uid}/{child}`
  static DatabaseReference userRef(String child) => db.ref('users/$uid/$child');

  /// Converts the loosely typed values the SDK returns (Map<Object?, Object?>,
  /// List<Object?>) into plain `Map<String, dynamic>` / `List<dynamic>`.
  static dynamic plain(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): plain(e.value)};
    }
    if (value is List) return value.map(plain).toList();
    return value;
  }

  /// Runs a database operation with a timeout and friendly errors.
  static Future<T> guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('Could not reach the database. Check your internet connection.');
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'permission-denied':
          throw const ApiException(
            'The database refused access. Make sure the security rules are deployed and you are signed in.',
            statusCode: 403,
          );
        case 'network-error':
        case 'unavailable':
        case 'disconnected':
          throw const ApiException('Could not reach the database. Check your internet connection.');
        default:
          throw ApiException(e.message ?? 'Database error (${e.code}).');
      }
    }
  }
}

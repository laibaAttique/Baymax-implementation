/// Extra Firebase settings that `flutterfire configure` does not generate.
class FirebaseConfig {
  FirebaseConfig._();

  /// Realtime Database URL (Firebase console → Build → Realtime Database).
  static const String databaseUrl = String.fromEnvironment(
    'FIREBASE_DB_URL',
    defaultValue: 'https://baymax-148da-default-rtdb.firebaseio.com',
  );
}

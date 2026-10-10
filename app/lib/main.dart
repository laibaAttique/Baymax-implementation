import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/realtime_db.dart';
import 'theme/app_theme.dart';
import 'screens/auth/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    // On Android the google-services plugin may already have created the
    // default app natively (and hot restarts keep it alive).
    if (e.code != 'duplicate-app') rethrow;
  }

  RealtimeDb.init();

  runApp(const BaymaxApp());
}

class BaymaxApp extends StatelessWidget {
  const BaymaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baymax',
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

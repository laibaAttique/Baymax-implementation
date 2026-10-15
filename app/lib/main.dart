import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/realtime_db.dart';
import 'theme/app_theme.dart';
import 'widgets/glass.dart';
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

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const BaymaxApp());
}

class BaymaxApp extends StatelessWidget {
  const BaymaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baymax',
      theme: AppTheme.lightTheme,
      builder: baymaxShell,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// The shell around every screen: one mist gradient behind everything (each Scaffold is transparent so it shows through).
/// On tablets and landscape the content is held to a readable column and centred; text scaling is capped so layouts stay intact.
Widget baymaxShell(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: GlassBackground(
      child: MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: child ?? const SizedBox.shrink()),
        ),
      ),
    ),
  );
}

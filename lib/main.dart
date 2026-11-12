import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'config.dart';
import 'push.dart';
import 'auth.dart';
import 'profile_setup.dart';
import 'app_lock.dart';
import 'l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  await AppSettings.load();

  runApp(const UniBridgeApp());
}

class UniBridgeApp extends StatelessWidget {
  const UniBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the language or the theme changes (Profile tab).
    return ValueListenableBuilder<String>(
      valueListenable: AppSettings.language,
      builder: (context, language, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppSettings.themeMode,
        builder: (context, themeMode, _) => MaterialApp(
          title: 'UniBridge',
          theme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.dark,
          ),
          themeMode: themeMode,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // The lock covers every screen, so it also works after hot restart
          // and on screens opened from notifications.
          builder: (context, child) => AppLock(child: child!),
          home: supabase.auth.currentSession == null
              ? const AuthScreen()
              : const ProfileGate(),
        ),
      ),
    );
  }
}

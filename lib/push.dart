import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

StreamSubscription<RemoteMessage>? _foregroundSub;

void listenForForegroundNotifications(BuildContext context) {
  _foregroundSub?.cancel();
  _foregroundSub =
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final title = message.notification?.title ?? 'UniBridge';
    final body = message.notification?.body ?? '';

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $body'),
        duration: const Duration(seconds: 4),
      ),
    );
  });
}

// ---------------- Push notification helpers ----------------

StreamSubscription<String>? _tokenRefreshSub;

Future<void> setupPushNotifications() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  debugPrint('Notification permission: ${settings.authorizationStatus}');

  final token = await messaging.getToken();
  debugPrint('FCM TOKEN: $token');

  if (token != null && token.isNotEmpty) {
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('Could not save FCM token: $e');
    }
  }

  // Only one refresh listener at a time, always for the current user.
  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
    debugPrint('New FCM TOKEN: $newToken');
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': newToken})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('Could not update FCM token: $e');
    }
  });
}

// Call this just before signing out, so a logged-out account stops
// receiving notifications on this phone.
Future<void> clearPushToken() async {
  final user = supabase.auth.currentUser;
  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = null;
  await _foregroundSub?.cancel();
  _foregroundSub = null;
  if (user == null) return;

  try {
    await supabase
        .from('profiles')
        .update({'fcm_token': null})
        .eq('id', user.id);
    await FirebaseMessaging.instance.deleteToken();
  } catch (e) {
    debugPrint('Could not clear FCM token: $e');
  }
}

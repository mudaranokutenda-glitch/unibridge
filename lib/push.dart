import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'config.dart';
import 'l10n.dart';
import 'errors.dart';

// ---------------- Phone notification bar (Android channels) ----------------
//
// Two channels. The Edge Functions send "general" or "emergency" as
// android.notification.channel_id, so background pushes use them too.
//
// EMERGENCY SOUND: android/app/src/main/res/raw/emergency_alert.mp3 is not in
// the project yet, so the emergency channel uses the phone's alarm sound.
// When you add the file:
//   1. set kEmergencySoundFileAdded = true below,
//   2. change kEmergencyChannelId to 'emergency2' here AND
//      EMERGENCY_CHANNEL in supabase/functions/emergency-alert/index.ts
//      (Android keeps the first sound of a channel forever, so a new id is
//      needed), then deploy emergency-alert again.
const bool kEmergencySoundFileAdded = false;
const String kGeneralChannelId = 'general';
const String kEmergencyChannelId = 'emergency';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

AndroidNotificationChannel _generalChannel() => AndroidNotificationChannel(
      kGeneralChannelId,
      tr('General'),
      description: tr('Messages, matches and requests'),
      importance: Importance.high,
    );

AndroidNotificationChannel _emergencyChannel() => AndroidNotificationChannel(
      kEmergencyChannelId,
      tr('Emergency alerts'),
      description: tr('Urgent alerts from the Educational Attaché'),
      importance: Importance.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: kEmergencySoundFileAdded
          ? const RawResourceAndroidNotificationSound('emergency_alert')
          : const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert'),
    );

// Called once in main(). Creates the two channels.
Future<void> initLocalNotifications() async {
  try {
    await localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_generalChannel());
    await android?.createNotificationChannel(_emergencyChannel());
  } catch (e) {
    debugPrint('Could not set up local notifications: $e');
  }
}

int _nextNotificationId = 0;

// Shows a notification in the phone's notification bar (app open).
Future<void> showLocalNotification(String title, String body,
    {bool emergency = false}) async {
  final channel = emergency ? _emergencyChannel() : _generalChannel();
  try {
    await localNotifications.show(
      id: _nextNotificationId++ & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: emergency ? Priority.max : Priority.high,
          sound: channel.sound,
          audioAttributesUsage: channel.audioAttributesUsage,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  } catch (e) {
    debugPrint('Could not show notification: $e');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

StreamSubscription<RemoteMessage>? _foregroundSub;

void listenForForegroundNotifications(BuildContext context) {
  if (kIsWeb) return; // no push on the web version
  _foregroundSub?.cancel();
  _foregroundSub =
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'UniBridge';
    final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
    final emergency = message.data['channel'] == kEmergencyChannelId;

    // While the app is open, Android does not show the push by itself:
    // show it in the notification bar.
    showLocalNotification(title, body, emergency: emergency);
    if (emergency) onEmergencyAlertReceived?.call();
  });
}

// The home screen sets this to reload the alert banner.
VoidCallback? onEmergencyAlertReceived;


// ---------------- Push notification helpers ----------------

StreamSubscription<String>? _tokenRefreshSub;

// Never throws: if notifications cannot be set up (no Google Play services,
// permission refused, no internet), the user still gets into the app.
Future<void> setupPushNotifications() async {
  if (kIsWeb) return; // no push on the web version
  try {
    await _setupPushNotifications();
  } catch (e) {
    debugPrint('Push notifications not set up: $e');
  }
}

Future<void> _setupPushNotifications() async {
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
    if (!kIsWeb) await FirebaseMessaging.instance.deleteToken();
  } catch (e) {
    debugPrint('Could not clear FCM token: $e');
  }
}

// ---------------- "New request notifications" switch (Profile) ----------------
// Saved in notification_settings (only I can read or change my row).
// No row = ON (the default).

class NewRequestNotificationsTile extends StatefulWidget {
  const NewRequestNotificationsTile({super.key});
  @override
  State<NewRequestNotificationsTile> createState() =>
      _NewRequestNotificationsTileState();
}

class _NewRequestNotificationsTileState
    extends State<NewRequestNotificationsTile> {
  bool on = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final row = await supabase
          .from('notification_settings')
          .select('new_requests')
          .eq('user_id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          on = row == null || row['new_requests'] != false;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint('Could not load notification settings: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> change(bool value) async {
    setState(() => on = value);
    try {
      await supabase.from('notification_settings').upsert({
        'user_id': supabase.auth.currentUser!.id,
        'new_requests': value,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => on = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not save: {error}', {'error': friendlyError(e, short: true)}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: Text(tr('New request notifications')),
        subtitle: Text(tr('A notification each time someone posts a request.')),
        value: on,
        onChanged: loading ? null : change,
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'config.dart';
import 'l10n.dart';
import 'presence.dart';
import 'push.dart';

// ---------------- Settings -> Check notifications ----------------
// One page that says, in plain words, why notifications or the green
// "online" dot might not work on this phone, with a button to fix each one
// and buttons to send test notifications.

class NotificationCheckScreen extends StatefulWidget {
  const NotificationCheckScreen({super.key});

  @override
  State<NotificationCheckScreen> createState() =>
      _NotificationCheckScreenState();
}

class _NotificationCheckScreenState extends State<NotificationCheckScreen> {
  bool checking = true;
  bool? allowed; // notifications allowed for AZSA on this phone
  bool? channelOk; // "General" kept with sound and pop-up
  bool registered = false; // push address saved on my profile
  String? pushError;
  bool sending = false;
  String? testResult;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  void initState() {
    super.initState();
    runChecks();
  }

  Future<void> runChecks() async {
    setState(() => checking = true);
    if (!kIsWeb) {
      try {
        allowed = await _android?.areNotificationsEnabled();
      } catch (_) {
        allowed = null;
      }
      try {
        final channels = await _android?.getNotificationChannels();
        final general = channels
            ?.where((c) => c.id == kGeneralChannelId)
            .firstOrNull;
        channelOk = general == null
            ? null
            : general.importance.value >= Importance.high.value &&
                general.playSound != false;
      } catch (_) {
        channelOk = null;
      }
      await setupPushNotifications(); // saves this phone's push address again
      registered = PushStatus.tokenSaved;
      pushError = PushStatus.error;
    }
    if (mounted) setState(() => checking = false);
  }

  Future<void> allow() async {
    final granted = await _android?.requestNotificationsPermission();
    if (granted != true) await _android?.openAppNotificationSettings();
    await runChecks();
  }

  Future<void> openSettings() async {
    await _android?.openAppNotificationSettings();
    await runChecks();
  }

  Future<void> testFromServer({required bool closed}) async {
    setState(() {
      sending = true;
      testResult = null;
    });
    if (closed && mounted) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Close the app now')),
          content: Text(tr(
              'Press the phone\'s Home button now. A notification should arrive in about 10 seconds, with the phone\'s sound.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('OK')),
            ),
          ],
        ),
      );
    }
    final error = await sendTestPush(delaySeconds: closed ? 8 : 0);
    if (!mounted) return;
    setState(() {
      sending = false;
      testResult = error == null
          ? tr('Sent. It should appear in your notification bar.')
          : tr('Not sent: {error}', {'error': error});
    });
  }

  Widget row(String title, bool? ok,
      {String? detail, String? fixLabel, VoidCallback? onFix}) {
    final icon = ok == null
        ? const Icon(Icons.help_outline, color: kMutedText)
        : ok
            ? const Icon(Icons.check_circle, color: Color(0xFF25D366))
            : const Icon(Icons.error, color: Colors.redAccent);
    return Card(
      child: ListTile(
        leading: icon,
        title: Text(title),
        subtitle: detail == null ? null : Text(detail),
        trailing: (ok == false && onFix != null)
            ? FilledButton.tonal(onPressed: onFix, child: Text(fixLabel!))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Check notifications')),
        actions: [
          IconButton(
            tooltip: tr('Check again'),
            onPressed: checking ? null : runChecks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom),
        children: [
          if (checking) const LinearProgressIndicator(),
          if (kIsWeb)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(tr(
                    'Notifications in the notification bar are for the Android app. The web version shows them on the bell only.')),
              ),
            )
          else ...[
            row(
              tr('Notifications allowed for AZSA'),
              allowed,
              detail: allowed == false
                  ? tr('Android is blocking AZSA notifications.')
                  : null,
              fixLabel: tr('Allow'),
              onFix: allow,
            ),
            row(
              tr('"General" notifications have sound and pop-up'),
              channelOk,
              detail: channelOk == false
                  ? tr('Turn on sound and "Pop on screen" for General.')
                  : null,
              fixLabel: tr('Open settings'),
              onFix: openSettings,
            ),
            row(
              tr('This phone is registered for notifications'),
              checking ? null : registered,
              detail: registered ? null : pushError,
              fixLabel: tr('Try again'),
              onFix: runChecks,
            ),
          ],
          ValueListenableBuilder<String>(
            valueListenable: OnlineStatus.state,
            builder: (context, state, _) =>
                ValueListenableBuilder<Set<String>>(
              valueListenable: OnlineStatus.online,
              builder: (context, online, _) => row(
                tr('Online status (green dot)'),
                state == 'connected'
                    ? true
                    : (state == 'connecting' ? null : false),
                detail: state == 'connected'
                    ? tr('{n} people online now (you included).',
                        {'n': online.length})
                    : state,
              ),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 16),
            Text(tr('Tests'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_outlined),
              label: Text(tr('Show a notification from this phone')),
              onPressed: () => showLocalNotification('AZSA',
                  tr('Test: this is how AZSA notifications look and sound.')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_outlined),
              label: Text(tr('Send a test from the server')),
              onPressed: sending ? null : () => testFromServer(closed: false),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.phonelink_erase),
              label: Text(tr('Test with the app closed')),
              onPressed: sending ? null : () => testFromServer(closed: true),
            ),
            if (sending)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(testResult!),
              ),
          ],
        ],
      ),
    );
  }
}

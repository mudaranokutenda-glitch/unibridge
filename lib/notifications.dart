import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'config.dart';
import 'requests.dart';
import 'rates.dart';
import 'student_space.dart';
import 'l10n.dart';

// ---------------- Notifications (bell + inbox) ----------------

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unread = 0;
  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    loadCount();
    // Refresh the number when a push arrives while the app is open.
    _sub = FirebaseMessaging.onMessage.listen((_) => loadCount());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> loadCount() async {
    try {
      final data = await supabase
          .from('notifications')
          .select('id')
          .eq('is_read', false);
      if (!mounted) return;
      setState(() => unread = (data as List).length);
    } catch (e) {
      debugPrint('Could not load notification count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Notifications'),
      icon: Badge(
        label: Text(unread > 9 ? '9+' : '$unread'),
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        loadCount();
      },
    );
  }
}

IconData _notificationIcon(String type) {
  switch (type) {
    case 'MATCH_FOUND':
      return Icons.people_outline;
    case 'CONFIRMATION_NEEDED':
      return Icons.pending_actions;
    case 'TRANSACTION_COMPLETED':
      return Icons.check_circle_outline;
    case 'DISPUTE_OPENED':
      return Icons.report_problem_outlined;
    case 'VERIFIED_BADGE_AWARDED':
      return Icons.verified_outlined;
    case 'ATTESTATION_UPDATE':
      return Icons.workspace_premium_outlined;
    default:
      return Icons.notifications_none;
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      final loaded = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      setState(() {
        items = loaded;
        loading = false;
      });

      // The unread dots stay visible on this screen, and everything is
      // marked as read once the person has seen the list.
      if (loaded.any((n) => n['is_read'] != true)) {
        await supabase
            .from('notifications')
            .update({'is_read': true}).eq('is_read', false);
      }
    } catch (e) {
      debugPrint('Could not load notifications: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notifications'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: 100),
                      Center(child: Text(tr('No notifications yet.'))),
                    ],
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = items[index];
                      final isUnread = n['is_read'] != true;
                      return ListTile(
                        leading: Icon(_notificationIcon('${n['type']}')),
                        title: Text(
                          '${n['content']}',
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(updatedAgo(
                            DateTime.tryParse('${n['created_at']}'))),
                        trailing: isUnread
                            ? const Icon(Icons.circle,
                                size: 10, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => n['type'] == 'ATTESTATION_UPDATE'
                                    ? const AttestationScreen()
                                    : const MyRequestsScreen()),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

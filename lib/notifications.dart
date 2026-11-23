import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'app_theme.dart';
import 'requests.dart';
import 'request_row.dart';
import 'rates.dart';
import 'student_space.dart';
import 'student_info.dart';
import 'verification.dart';
import 'roles.dart';
import 'errors.dart';
import 'l10n.dart';
import 'presence.dart';

// ---------------- Unread count, shared by every bell ----------------
// One live connection for the whole app (started by the Home screen). It
// counts again when: a notification row changes (Realtime), a push arrives,
// the app comes back to the screen, or the notifications page closes.

class NotificationCenter {
  NotificationCenter._();

  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static String? _userId;
  static RealtimeChannel? _channel;
  static StreamSubscription<RemoteMessage>? _pushSub;
  static AppLifecycleListener? _lifecycle;
  static Timer? _debounce;

  static void start() {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;
    if (_userId == me && _channel != null) {
      OnlineStatus.start(); // green "online" dot in chats
      refresh();
      return;
    }
    stop(); // also stops the online dot, so start it AFTER this line
    OnlineStatus.start(); // green "online" dot in chats
    _userId = me;
    _channel = supabase
        .channel('notifications-$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (_) => refreshSoon(),
        )
        .subscribe();
    try {
      if (!kIsWeb) {
        _pushSub = FirebaseMessaging.onMessage.listen((_) => refreshSoon());
      }
    } catch (e) {
      debugPrint('Push listener not available: $e');
    }
    _lifecycle = AppLifecycleListener(onResume: refreshSoon);
    refresh();
  }

  // Called at log out: no count for the next person on this phone.
  static void stop() {
    OnlineStatus.stop();
    _debounce?.cancel();
    _pushSub?.cancel();
    _pushSub = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    final channel = _channel;
    if (channel != null) supabase.removeChannel(channel);
    _channel = null;
    _userId = null;
    unread.value = 0;
  }

  static void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  static Future<void> refresh() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', me)
          .eq('is_read', false)
          .limit(100);
      unread.value = (rows as List).length;
    } catch (e) {
      debugPrint('Could not load notification count: $e');
    }
  }
}

// ---------------- The bell (put it in any AppBar) ----------------

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationCenter.unread,
      builder: (context, unread, _) => IconButton(
        tooltip: unread > 0
            ? tr('Notifications ({count} new)', {'count': unread})
            : tr('Notifications'),
        icon: Badge(
          label: Text(unread > 99 ? '99+' : '$unread'),
          isLabelVisible: unread > 0,
          backgroundColor: AppColors.cancelled,
          child: Icon(unread > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_outlined),
        ),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          );
          NotificationCenter.refresh();
        },
      ),
    );
  }
}

// ---------------- Look of each type ----------------

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
    case 'MEMBERSHIP_UPDATE':
      return Icons.how_to_reg_outlined;
    case 'APPOINTMENT_UPDATE':
      return Icons.event_outlined;
    case 'REQUEST_EXPIRED':
      return Icons.timer_off_outlined;
    default:
      return Icons.notifications_none;
  }
}

Color _notificationColor(String type) {
  switch (type) {
    case 'CONFIRMATION_NEEDED':
      return AppColors.warning;
    case 'TRANSACTION_COMPLETED':
      return AppColors.success;
    case 'DISPUTE_OPENED':
      return AppColors.cancelled;
    case 'VERIFIED_BADGE_AWARDED':
      return AppColors.verified;
    case 'REQUEST_EXPIRED':
      return AppColors.expired;
    default:
      return AppColors.sky;
  }
}

// "Today", "Yesterday", "Earlier"
String _dayGroup(DateTime? d) {
  if (d == null) return tr('Earlier');
  final local = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return tr('Today');
  if (diff == 1) return tr('Yesterday');
  return tr('Earlier');
}

// ---------------- Notifications page ----------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? loadError;
  bool clearing = false;

  String get myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = items.isEmpty;
      loadError = null;
    });
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(100);
      final loaded = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      setState(() {
        items = loaded;
        loading = false;
      });

      // The unread dots stay visible on this page; in the database everything
      // is marked as read now, so the red number on the bell goes away.
      if (loaded.any((n) => n['is_read'] != true)) {
        await supabase
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', myId)
            .eq('is_read', false);
      }
      NotificationCenter.unread.value = 0;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = friendlyError(e);
      });
    }
  }

  Future<void> clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Clear all notifications?')),
        content: Text(tr('They will be deleted. This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.cancelled),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Clear all')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => clearing = true);
    try {
      await supabase.from('notifications').delete().eq('user_id', myId);
      if (!mounted) return;
      setState(() => items = []);
      NotificationCenter.unread.value = 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  // Swipe one notification away.
  Future<void> deleteOne(Map<String, dynamic> n) async {
    final id = n['id'];
    final index = items.indexOf(n);
    setState(() => items.remove(n));
    try {
      await supabase.from('notifications').delete().eq('id', id);
    } catch (e) {
      // Not deleted: put it back.
      if (!mounted) return;
      setState(() => items.insert(index.clamp(0, items.length), n));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  // "Your request expired": show it and offer to post the same one again.
  Future<void> askRepost(Map<String, dynamic> n) async {
    final id = n['request_id']?.toString();
    if (id == null) {
      // An old notification without a link: just open My requests.
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const MyRequestsScreen()));
      return;
    }
    Map<String, dynamic>? r;
    try {
      r = await supabase
          .from('transaction_requests')
          .select()
          .eq('id', id)
          .maybeSingle();
    } catch (e) {
      debugPrint('Could not load the expired request: $e');
    }
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.timer_off_outlined),
        title: Text(tr('Your request expired')),
        content: Text(r == null
            ? tr('Post the same request again?')
            : tr('{request}. Post the same request again?',
                {'request': requestHeadline(r)})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('No, thanks')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Post again')),
          ),
        ],
      ),
    );
    if (again != true || !mounted) return;
    try {
      await supabase.rpc('repost_expired_request', params: {'p_request_id': id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Your request is posted again.'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  // Opens the screen that belongs to this notification. It stays in the list.
  Future<void> open(Map<String, dynamic> n) async {
    final type = '${n['type']}';
    if (type == 'REQUEST_EXPIRED') {
      await askRepost(n);
      return;
    }
    Widget? screen;
    switch (type) {
      case 'MATCH_FOUND':
      case 'CONFIRMATION_NEEDED':
      case 'TRANSACTION_COMPLETED':
      case 'DISPUTE_OPENED':
        screen = const MyRequestsScreen();
        break;
      case 'VERIFIED_BADGE_AWARDED':
        screen = const VerificationScreen();
        break;
      case 'ATTESTATION_UPDATE':
        screen = const AttestationScreen();
        break;
      case 'MEMBERSHIP_UPDATE':
        screen = const StudentSpaceScreen();
        break;
      case 'APPOINTMENT_UPDATE':
        final role = await loadMyRole();
        screen = role.isStaff
            ? const StaffAppointmentsScreen()
            : const AppointmentsScreen();
        break;
      default:
        screen = null; // nothing to open
    }
    if (screen == null || !mounted) return;
    final page = screen;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget tile(Map<String, dynamic> n) {
    final type = '${n['type']}';
    final color = _notificationColor(type);
    final isUnread = n['is_read'] != true;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('notification-${n['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        color: AppColors.cancelled,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => deleteOne(n),
      child: Material(
        color: isUnread
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        child: ListTile(
          contentPadding:
              const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_notificationIcon(type), color: color, size: 22),
          ),
          title: Text(
            tr('${n['content'] ?? ''}'),
            style: TextStyle(
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(updatedAgo(DateTime.tryParse('${n['created_at']}'))),
          trailing: isUnread
              ? const Icon(Icons.circle, size: 10, color: AppColors.sky)
              : null,
          onTap: () => open(n),
        ),
      ),
    );
  }

  Widget header(String text) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.notifications_none,
                size: 40, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(tr("You're all caught up"),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            tr('Matches, confirmations and updates will appear here.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? lastGroup;
    for (final n in items) {
      final group = _dayGroup(DateTime.tryParse('${n['created_at']}'));
      if (group != lastGroup) {
        children.add(header(group));
        lastGroup = group;
      }
      children.add(tile(n));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Notifications')),
        actions: [
          if (items.isNotEmpty)
            TextButton.icon(
              onPressed: clearing ? null : clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(tr('Clear all')),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : loadError != null
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(child: Text(loadError!, textAlign: TextAlign.center)),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton(
                            onPressed: load, child: Text(tr('Try again'))),
                      ),
                    ],
                  )
                : items.isEmpty
                    ? emptyState()
                    : ListView(
                        children: [
                          ...children,
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              tr('Swipe left to delete one notification.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

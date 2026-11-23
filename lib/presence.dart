import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

// ---------------- Who is online (green dot in chats) ----------------
// Every signed-in phone joins one Realtime "presence" channel. While the app
// is open on screen, the phone says "I'm here". When the app goes to the
// background or is closed, it leaves, so the others see "offline".
// The channel is private: only signed-in users can join (see the SQL file
// 2026-11-20-07-online-status.sql). If that SQL is not run yet, everyone
// simply shows as offline; nothing breaks.

class OnlineStatus {
  OnlineStatus._();

  // The ids of the users online right now.
  static final ValueNotifier<Set<String>> online =
      ValueNotifier<Set<String>>(<String>{});

  static RealtimeChannel? _channel;
  static String? _userId;
  static AppLifecycleListener? _lifecycle;
  static bool _joined = false;
  static bool _visible = true;

  // How the connection is doing (shown on Settings -> Check notifications).
  static final ValueNotifier<String> state =
      ValueNotifier<String>('not started');

  static bool isOnline(String? userId) =>
      userId != null && online.value.contains(userId);

  static void start() {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;
    if (_userId == me && _channel != null) return;
    stop();
    _userId = me;
    _visible = true;
    state.value = 'connecting';

    final channel = supabase.channel(
      'online-users',
      opts: RealtimeChannelConfig(key: me, private: true),
    );
    channel
        .onPresenceSync((_) => _read(channel))
        .onPresenceJoin((_) => _read(channel))
        .onPresenceLeave((_) => _read(channel))
        .subscribe((status, error) {
      _joined = status == RealtimeSubscribeStatus.subscribed;
      if (_joined && _visible) _track();
      state.value = switch (status) {
        RealtimeSubscribeStatus.subscribed => 'connected',
        RealtimeSubscribeStatus.timedOut => 'timed out (will try again)',
        RealtimeSubscribeStatus.closed => 'closed',
        RealtimeSubscribeStatus.channelError => 'refused: ${error ?? '?'}',
      };
      if (error != null) debugPrint('Online status: $error');
    });
    _channel = channel;

    _lifecycle = AppLifecycleListener(
      onShow: () {
        _visible = true;
        _track();
      },
      onHide: () {
        _visible = false;
        _untrack();
      },
    );
  }

  // Called at log out.
  static void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    final channel = _channel;
    if (channel != null) supabase.removeChannel(channel);
    _channel = null;
    _userId = null;
    _joined = false;
    online.value = <String>{};
    state.value = 'not started';
  }

  static void _read(RealtimeChannel channel) {
    // The presence key is the user id (set in start()).
    online.value = {
      for (final s in channel.presenceState())
        if (s.presences.isNotEmpty) s.key,
    };
  }

  static Future<void> _track() async {
    final channel = _channel;
    if (channel == null || !_joined) return;
    try {
      final res = await channel
          .track({'at': DateTime.now().toUtc().toIso8601String()});
      if (res != ChannelResponse.ok) {
        state.value = 'connected, but my status was not shared (${res.name})';
      }
    } catch (e) {
      debugPrint('Online status (track): $e');
    }
  }

  static Future<void> _untrack() async {
    final channel = _channel;
    if (channel == null || !_joined) return;
    try {
      await channel.untrack();
    } catch (e) {
      debugPrint('Online status (untrack): $e');
    }
  }
}

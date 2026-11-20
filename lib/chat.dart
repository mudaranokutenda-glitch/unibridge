import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'app_theme.dart';
import 'profiles.dart';
import 'presence.dart';
import 'push.dart' show openChatRequestId, clearNotificationBar;
import 'chat_wallpaper.dart';
import 'errors.dart';
import 'l10n.dart';

// While the exchange is running: confirm and "report a problem" are possible.
const Set<String> kRunningStatuses = {
  'MATCHED',
  'IN_PROGRESS',
  'SENDER_DONE',
  'RECEIVER_DONE',
};

// ---------------- Chat screen (with confirm / dispute / rating) ----------------

class ChatScreen extends StatefulWidget {
  final String requestId;
  const ChatScreen({super.key, required this.requestId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> messagesStream;
  Map<String, dynamic>? request;
  Map<String, dynamic>? otherProfile;
  Map<String, dynamic>? myProfile;
  bool actionLoading = false;
  bool sendingPhoto = false;
  bool chatBlocked = false;

  bool hasRated = false;
  int selectedStars = 5;
  final ratingCommentController = TextEditingController();
  bool ratingLoading = false;
  bool sendingText = false;
  bool loadFailed = false; // the request could not be loaded

  // Live: when the other person confirms or reports a problem, this screen
  // updates by itself (no need to leave and come back).
  RealtimeChannel? requestChannel;
  Timer? reloadTimer;

  @override
  void initState() {
    super.initState();
    // While this chat is open, its new messages don't ring as notifications.
    openChatRequestId = widget.requestId;
    clearNotificationBar();
    messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('request_id', widget.requestId)
        .order('created_at');
    loadRequest();
    requestChannel = supabase
        .channel('chat-request-${widget.requestId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'transaction_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.requestId,
          ),
          callback: (_) => reloadSoon(),
        )
        .subscribe();
  }

  void reloadSoon() {
    reloadTimer?.cancel();
    reloadTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) loadRequest();
    });
  }

  @override
  void dispose() {
    if (openChatRequestId == widget.requestId) openChatRequestId = null;
    reloadTimer?.cancel();
    final channel = requestChannel;
    if (channel != null) supabase.removeChannel(channel);
    messageController.dispose();
    ratingCommentController.dispose();
    super.dispose();
  }

  Future<void> loadRequest() async {
    final Map<String, dynamic> data;
    try {
      data = await supabase
          .from('transaction_requests')
          .select()
          .eq('id', widget.requestId)
          .single();
    } catch (e) {
      debugPrint('Could not load the request: $e');
      if (mounted && request == null) setState(() => loadFailed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      request = data;
      loadFailed = false;
    });

    // The small round pictures beside the messages: loaded once per chat,
    // mine and the other person's, with one call to get_public_profiles.
    if (otherProfile == null || myProfile == null) {
      final myId = supabase.auth.currentUser!.id;
      final otherId = otherPartyId(data, myId);
      final profiles = await fetchPublicProfiles([myId, otherId]);
      if (mounted) {
        setState(() {
          myProfile = profiles[myId];
          if (otherId != null) otherProfile = profiles[otherId];
        });
      }
    }

    if (data['status'] == 'COMPLETED') {
      try {
        await checkIfRated();
      } catch (e) {
        debugPrint('Could not check the rating: $e');
      }
    }

    // If one of us blocked the other, new messages are not allowed.
    try {
      final blocked = await supabase
          .rpc('chat_is_blocked', params: {'p_request_id': widget.requestId});
      if (mounted) setState(() => chatBlocked = blocked == true);
    } catch (e) {
      debugPrint('Could not check block status: $e');
    }
  }

  Future<void> checkIfRated() async {
    final myId = supabase.auth.currentUser!.id;
    final existing = await supabase
        .from('ratings')
        .select()
        .eq('request_id', widget.requestId)
        .eq('rater_id', myId);
    if (mounted) {
      setState(() => hasRated = (existing as List).isNotEmpty);
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || sendingText) return;
    setState(() => sendingText = true);
    messageController.clear();
    try {
      await supabase.from('messages').insert({
        'request_id': widget.requestId,
        'sender_id': supabase.auth.currentUser!.id,
        'type': 'TEXT',
        'content': text,
      });
    } catch (e) {
      // Not sent: give the text back so it is not lost.
      if (mounted) {
        if (messageController.text.isEmpty) messageController.text = text;
        showError(tr('Message not sent: {error}',
            {'error': friendlyError(e, short: true)}));
        setState(() => sendingText = false);
      }
      return;
    }
    if (mounted) setState(() => sendingText = false);
    await notifyOtherPerson(text);
  }

  // The server finds the other person and sends the notification.
  // If this fails, the chat itself still works.
  Future<void> notifyOtherPerson(String text) async {
    try {
      await supabase.functions.invoke('notify-chat-message', body: {
        'request_id': widget.requestId,
        'message': text,
      });
    } catch (e) {
      debugPrint('Push notification error: $e');
    }
  }

  // Asks "camera or gallery?", then uploads the photo to the private
  // chat-photos bucket and sends it as an IMAGE message.
  Future<void> sendPhoto() async {
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Send a photo'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _sourceButton(context, Icons.photo_camera,
                    tr('Take a photo'), const Color(0xFFE5486C),
                    ImageSource.camera),
                _sourceButton(context, Icons.photo_library,
                    tr('Choose from gallery'), const Color(0xFF8E5CF7),
                    ImageSource.gallery),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
    } catch (e) {
      debugPrint('Could not open the camera / gallery: $e');
      showError(tr('Could not open the camera or the gallery.'));
      return;
    }
    if (picked == null) return;

    final name = picked.name.toLowerCase();
    final String ext;
    final String contentType;
    if (name.endsWith('.png')) {
      ext = 'png';
      contentType = 'image/png';
    } else if (name.endsWith('.webp')) {
      ext = 'webp';
      contentType = 'image/webp';
    } else {
      ext = 'jpg';
      contentType = 'image/jpeg';
    }

    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('This photo is too big (max 5 MB).'))),
        );
      }
      return;
    }

    setState(() => sendingPhoto = true);
    try {
      final myId = supabase.auth.currentUser!.id;
      // The first folder must be the request id (the storage rules check it).
      final path =
          '${widget.requestId}/${myId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('chat-photos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      await supabase.from('messages').insert({
        'request_id': widget.requestId,
        'sender_id': myId,
        'type': 'IMAGE',
        'content': '📷 Photo',
        'attachment_url': path,
      });
      await notifyOtherPerson('📷 Photo');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr('Could not send photo: {error}',
                  {'error': friendlyError(e, short: true)}))),
        );
      }
    } finally {
      if (mounted) setState(() => sendingPhoto = false);
    }
  }

  Widget _sourceButton(BuildContext context, IconData icon, String label,
      Color color, ImageSource source) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).pop(source),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void openOtherProfile() {
    final id = otherProfile?['id']?.toString();
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)),
    );
  }

  void showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> confirm(String role) async {
    // Confirming cannot be undone: ask first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(role == 'SENDER'
            ? tr('Did you really send the money?')
            : tr('Did you really receive the money?')),
        content: Text(tr(
            'Confirm only when it is really done. This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Not yet')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Yes, confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => actionLoading = true);
    try {
      await supabase.rpc('confirm_transaction', params: {
        'p_request_id': widget.requestId,
        'p_role': role,
      });
      await loadRequest();
      if (mounted && request?['status'] == 'COMPLETED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr('Transaction complete! You can now rate each other.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => actionLoading = false);
    }
  }

  Future<void> openDispute() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Report a problem')),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            hintText: tr('Describe what went wrong...'),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(reasonController.text),
            child: Text(tr('Submit')),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => actionLoading = true);
    try {
      await supabase.rpc('open_dispute', params: {
        'p_request_id': widget.requestId,
        'p_reason': reason.trim(),
      });
      await loadRequest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Dispute submitted.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => actionLoading = false);
    }
  }

  Future<void> submitRating() async {
    setState(() => ratingLoading = true);
    try {
      await supabase.rpc('rate_transaction', params: {
        'p_request_id': widget.requestId,
        'p_score': selectedStars,
        'p_comment': ratingCommentController.text.trim().isEmpty
            ? null
            : ratingCommentController.text.trim(),
      });
      if (mounted) {
        setState(() => hasRated = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Thanks for rating!'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => ratingLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser!.id;
    final r = request;
    final status = r?['status'];
    final iAmCreator = r != null && r['creator_id'] == myId;
    final myRole = (r != null && ((iAmCreator && r['type'] == 'SEND') ||
            (!iAmCreator && r['type'] == 'RECEIVE')))
        ? 'SENDER'
        : 'RECEIVER';
    final iHaveConfirmed = r != null &&
        ((myRole == 'SENDER' && r['sender_confirmed'] == true) ||
            (myRole == 'RECEIVER' && r['receiver_confirmed'] == true));

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final other = otherProfile;
    final otherId = other?['id']?.toString();
    return Scaffold(
      backgroundColor: dark ? AppColors.darkBackground : const Color(0xFFE8F1FB),
      appBar: AppBar(
        backgroundColor: AppColors.sky,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        titleSpacing: 0,
        title: other == null
            ? Text(tr('Chat'))
            : InkWell(
                onTap: openOtherProfile,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: OnlineStatus.online,
                    builder: (context, online, _) {
                      final isOnline =
                          otherId != null && online.contains(otherId);
                      return Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              avatar(other, radius: 19),
                              if (isOnline)
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25D366),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppColors.sky, width: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        publicDisplayName(other),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (other['is_verified'] == true) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified,
                                          size: 16, color: AppColors.verified),
                                    ],
                                  ],
                                ),
                                Text(
                                  isOnline ? tr('online') : tr('offline'),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isOnline
                                        ? const Color(0xFFB9FFD0)
                                        : Colors.white.withValues(alpha: 0.8),
                                    fontWeight: isOnline
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
        actions: [
          if (kRunningStatuses.contains(status))
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: tr('Report a problem'),
              onPressed: actionLoading ? null : openDispute,
            ),
        ],
      ),
      body: Column(
        children: [
          if (status == 'COMPLETED')
            Container(
              width: double.infinity,
              color: scheme.primaryContainer,
              padding: const EdgeInsets.all(12),
              child: hasRated
                  ? Column(
                      children: [
                        Text(tr('✅ Transaction completed — thanks for rating!'),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline, size: 16),
                            const SizedBox(width: 6),
                            Text(tr('This chat is closed.')),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Text(tr('✅ Transaction completed'),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(tr('Rate the other person:')),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) {
                            final starValue = i + 1;
                            return IconButton(
                              icon: Icon(
                                starValue <= selectedStars
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                              ),
                              onPressed: () =>
                                  setState(() => selectedStars = starValue),
                            );
                          }),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          child: TextField(
                            controller: ratingCommentController,
                            decoration: InputDecoration(
                              hintText: tr('Optional comment...'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: ratingLoading ? null : submitRating,
                          child: Text(
                              ratingLoading ? tr('Submitting...') : tr('Submit rating')),
                        ),
                      ],
                    ),
            )
          else if (status == 'DISPUTED')
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(tr('⚠️ Dispute opened on this transaction'),
                  textAlign: TextAlign.center),
            )
          else if (kRunningStatuses.contains(status))
            Container(
              width: double.infinity,
              color: scheme.secondaryContainer,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    iHaveConfirmed
                        ? tr('You confirmed. Waiting for the other side...')
                        : tr('Once the exchange is done outside the app, confirm here.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: (actionLoading || iHaveConfirmed)
                        ? null
                        : () => confirm(myRole),
                    child: Text(myRole == 'SENDER'
                        ? tr("I sent the money")
                        : tr("I received the money")),
                  ),
                ],
              ),
            )
          else if (status == 'CANCELLED')
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: Text(tr('This request was cancelled.'),
                  textAlign: TextAlign.center),
            )
          else if (loadFailed)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(tr('Could not load this exchange.'),
                          textAlign: TextAlign.center)),
                  TextButton(
                      onPressed: loadRequest, child: Text(tr('Try again'))),
                ],
              ),
            ),
          Expanded(
            child: ChatWallpaper(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: messagesStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final messages = snapshot.data!;
                  if (messages.isEmpty) {
                    return Center(child: Text(tr('No messages yet. Say hi!')));
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // The list is newest first (index 0 = bottom).
                      final m = messages[index];
                      final older =
                          index + 1 < messages.length ? messages[index + 1] : null;
                      final when = _localTime(m['created_at']);
                      final olderWhen =
                          older == null ? null : _localTime(older['created_at']);
                      final newDay = when != null &&
                          (olderWhen == null || !_sameDay(when, olderWhen));
                      final sameSenderAsOlder = older != null &&
                          !newDay &&
                          older['sender_id'] == m['sender_id'] &&
                          older['type'] != 'SYSTEM';
                      return Column(
                        children: [
                          if (newDay) _dayChip(context, when),
                          _messageBubble(context, m, myId,
                              when: when, firstOfGroup: !sameSenderAsOlder),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (chatBlocked && kRunningStatuses.contains(status))
            SafeArea(
              child: Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(12),
                child: Text(
                  tr("You can't send messages in this chat."),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (kRunningStatuses.contains(status))
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // The long rounded box: text + photo button inside.
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: dark ? AppColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        padding: const EdgeInsetsDirectional.only(
                            start: 18, end: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: messageController,
                                minLines: 1,
                                maxLines: 5,
                                keyboardType: TextInputType.multiline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: tr('Type a message...'),
                                  filled: false,
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: sendingPhoto
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(Icons.photo_camera_outlined,
                                      color: scheme.onSurfaceVariant),
                              tooltip: tr('Send a photo'),
                              onPressed: sendingPhoto ? null : sendPhoto,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Round send button.
                    Material(
                      color: AppColors.sky,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: sendingText ? null : sendMessage,
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: sendingText
                              ? const Padding(
                                  padding: EdgeInsets.all(15),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- message pieces ----------

  static DateTime? _localTime(dynamic iso) =>
      DateTime.tryParse(iso?.toString() ?? '')?.toLocal();

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _dayChip(BuildContext context, DateTime? when) {
    if (when == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final String label;
    if (_sameDay(when, now)) {
      label = tr('Today');
    } else if (_sameDay(when, now.subtract(const Duration(days: 1)))) {
      label = tr('Yesterday');
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      label = '${when.day} ${months[when.month - 1]} ${when.year}';
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _messageBubble(
      BuildContext context, Map<String, dynamic> m, String myId,
      {DateTime? when, bool firstOfGroup = true}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (m['type'] == 'SYSTEM') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.darkCard
                  : const Color(0xFFFFF5C4), // soft yellow, like WhatsApp
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m['content'] ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final isMine = m['sender_id'] == myId;
    final isPhoto = m['type'] == 'IMAGE' && m['attachment_url'] != null;
    // Location sharing was removed: old ones show as text.
    final isLocation = m['type'] == 'LOCATION';

    final bubbleColor = isMine
        ? (dark ? const Color(0xFF1D4F8F) : const Color(0xFFD3E7FF))
        : (dark ? AppColors.darkCard : Colors.white);
    final textColor = dark ? Colors.white : AppColors.text;
    final timeColor = (dark ? Colors.white : AppColors.text)
        .withValues(alpha: 0.55);
    const r = Radius.circular(16);
    const tail = Radius.circular(4);
    final radius = BorderRadius.only(
      topLeft: (!isMine && firstOfGroup) ? tail : r,
      topRight: (isMine && firstOfGroup) ? tail : r,
      bottomLeft: r,
      bottomRight: r,
    );
    final time = when == null
        ? const SizedBox.shrink()
        : Text(_hhmm(when),
            style: TextStyle(fontSize: 11, color: timeColor));

    final Widget content;
    if (isPhoto) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatPhoto(key: ValueKey(m['id']), path: m['attachment_url']),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 3, 6, 1),
            child: time,
          ),
        ],
      );
    } else {
      final text = isLocation ? tr('[Location]') : (m['content'] ?? '').toString();
      // Text with the time at the end, on the same line when it fits.
      content = Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        children: [
          Text(text, style: TextStyle(fontSize: 15.5, color: textColor)),
          Padding(padding: const EdgeInsets.only(top: 4), child: time),
        ],
      );
    }

    return Align(
      alignment: isMine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: EdgeInsets.only(top: firstOfGroup ? 6 : 2),
          padding: isPhoto
              ? const EdgeInsets.all(4)
              : const EdgeInsets.fromLTRB(12, 7, 10, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}

// ---------------- Chat photo (private bucket, signed link) ----------------

class ChatPhoto extends StatefulWidget {
  final String path;
  const ChatPhoto({super.key, required this.path});

  @override
  State<ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<ChatPhoto> {
  late final Future<String> urlFuture;

  @override
  void initState() {
    super.initState();
    // The bucket is private, so we ask for a link that works for 1 hour.
    urlFuture =
        supabase.storage.from('chat-photos').createSignedUrl(widget.path, 3600);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            width: 200,
            height: 150,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 200,
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final url = snapshot.data!;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => FullScreenPhoto(url: url)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const SizedBox(
                width: 200,
                height: 150,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class FullScreenPhoto extends StatelessWidget {
  final String url;
  const FullScreenPhoto({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }
}

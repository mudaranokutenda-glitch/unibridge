import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'profiles.dart';
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

  // Picks one photo from the gallery, uploads it to the private
  // chat-photos bucket and sends it as an IMAGE message.
  Future<void> sendPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
    );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Chat')),
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
          if (otherProfile != null) ...[
            Container(
              width: double.infinity,
              color: scheme.surface,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: ProfileSummary(profile: otherProfile),
            ),
            const Divider(height: 1),
          ],
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
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isSystem = m['type'] == 'SYSTEM';
                    final isMine = m['sender_id'] == myId;
                    final isPhoto = m['type'] == 'IMAGE' &&
                        m['attachment_url'] != null;
                    // Location sharing was removed: old ones show as text.
                    final isLocation = m['type'] == 'LOCATION';
                    if (isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Text(
                            m['content'] ?? '',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      );
                    }
                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: isPhoto
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isMine
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: isPhoto
                          ? ChatPhoto(
                              key: ValueKey(m['id']),
                              path: m['attachment_url'],
                            )
                          : isLocation
                              ? Text(tr('[Location]'))
                              : Text(m['content'] ?? ''),
                    );
                    // The other person: picture on the start side. Me: on the end side.
                    final pic = Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: avatar(isMine ? myProfile : otherProfile,
                          radius: 14),
                    );
                    return Row(
                      mainAxisAlignment: isMine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: isMine
                          ? [Flexible(child: bubble), const SizedBox(width: 6), pic]
                          : [pic, const SizedBox(width: 6), Flexible(child: bubble)],
                    );
                  },
                );
              },
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
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: sendingPhoto
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      tooltip: tr('Send a photo'),
                      onPressed: sendingPhoto ? null : sendPhoto,
                    ),
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        decoration: InputDecoration(
                          hintText: tr('Type a message...'),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      tooltip: tr('Send'),
                      onPressed: sendingText ? null : sendMessage,
                    ),
                  ],
                ),
              ),
            ),
        ],
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

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'profiles.dart';
import 'l10n.dart';

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
  bool actionLoading = false;
  bool sendingPhoto = false;
  bool sendingLocation = false;
  bool downloading = false;
  bool chatBlocked = false;

  bool hasRated = false;
  int selectedStars = 5;
  final ratingCommentController = TextEditingController();
  bool ratingLoading = false;

  @override
  void initState() {
    super.initState();
    messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('request_id', widget.requestId)
        .order('created_at');
    loadRequest();
  }

  Future<void> loadRequest() async {
    final data = await supabase
        .from('transaction_requests')
        .select()
        .eq('id', widget.requestId)
        .single();
    if (!mounted) return;
    setState(() => request = data);

    if (otherProfile == null) {
      final myId = supabase.auth.currentUser!.id;
      final otherId = otherPartyId(data, myId);
      if (otherId != null) {
        final profiles = await fetchPublicProfiles([otherId]);
        if (mounted) setState(() => otherProfile = profiles[otherId]);
      }
    }

    if (data['status'] == 'COMPLETED') {
      checkIfRated();
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
    if (text.isEmpty) return;
    messageController.clear();

    await supabase.from('messages').insert({
      'request_id': widget.requestId,
      'sender_id': supabase.auth.currentUser!.id,
      'type': 'TEXT',
      'content': text,
    });

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
          SnackBar(content: Text(tr('Could not send photo: {error}', {'error': e}))),
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

  // Reads the phone's position ONE time (no tracking) and sends it as a
  // LOCATION message. The Google Maps link is stored in attachment_url.
  Future<void> sendLocation() async {
    final otherName =
        otherProfile == null ? tr('the other person') : publicDisplayName(otherProfile!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Share location')),
        content: Text(tr('Send your current location to {name}?', {'name': otherName})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Send')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => sendingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showError(tr('Please turn on location (GPS) on your phone.'));
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showError(tr('Location permission was refused.'));
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final mapsUrl =
          'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';

      await supabase.from('messages').insert({
        'request_id': widget.requestId,
        'sender_id': supabase.auth.currentUser!.id,
        'type': 'LOCATION',
        'content': '📍 Location',
        'attachment_url': mapsUrl,
      });
      await notifyOtherPerson('📍 Location');
    } catch (e) {
      showError(tr('Could not send location: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => sendingLocation = false);
    }
  }

  String twoDigits(int n) => n.toString().padLeft(2, '0');

  String formatTime(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)} '
        '${twoDigits(d.hour)}:${twoDigits(d.minute)}';
  }

  // Builds a plain text copy of the whole chat and lets the user choose
  // where to save it (Android "Save as" screen).
  Future<void> downloadChat() async {
    setState(() => downloading = true);
    try {
      final messages = await supabase
          .from('messages')
          .select()
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: true);

      final myId = supabase.auth.currentUser!.id;
      final otherName = otherProfile == null
          ? 'Other person'
          : publicDisplayName(otherProfile!);

      final lines = <String>[
        'UniBridge chat',
        'Request: ${widget.requestId}',
        'With: $otherName',
        'Saved: ${formatTime(DateTime.now().toIso8601String())}',
        '',
      ];
      for (final m in messages) {
        final time = formatTime(m['created_at']);
        final content = (m['content'] ?? '').toString();
        if (m['type'] == 'SYSTEM') {
          lines.add('$time · --- $content ---');
          continue;
        }
        final who = m['sender_id'] == myId ? 'Me' : otherName;
        final String text;
        if (m['type'] == 'IMAGE') {
          text = '[Photo]';
        } else if (m['type'] == 'LOCATION') {
          text = '[Location: ${m['attachment_url'] ?? ''}]';
        } else {
          text = content;
        }
        lines.add('$time · $who: $text');
      }

      final now = DateTime.now();
      final fileName = 'unibridge-chat-${now.year}${twoDigits(now.month)}'
          '${twoDigits(now.day)}-${twoDigits(now.hour)}${twoDigits(now.minute)}.txt';
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save chat',
        fileName: fileName,
        bytes: utf8.encode(lines.join('\n')),
        mimeType: 'text/plain',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Chat saved.'))),
        );
      }
    } catch (e) {
      showError(tr('Could not save the chat: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> openMap(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) showError(tr('Could not open the map.'));
  }

  Future<void> confirm(String role) async {
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
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
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
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
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
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
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
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: tr('Download chat as text'),
            onPressed: downloading ? null : downloadChat,
          ),
          if (status != null && status != 'COMPLETED' && status != 'DISPUTED')
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
                  ? Text(tr('✅ Transaction completed — thanks for rating!'),
                      textAlign: TextAlign.center)
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
          else if (status != null)
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
                    final isLocation = m['type'] == 'LOCATION' &&
                        m['attachment_url'] != null;
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
                    return Align(
                      alignment: isMine
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: isPhoto
                            ? const EdgeInsets.all(4)
                            : const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMine
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isPhoto
                            ? ChatPhoto(
                                key: ValueKey(m['id']),
                                path: m['attachment_url'],
                              )
                            : isLocation
                                ? InkWell(
                                    onTap: () => openMap(m['attachment_url']),
                                    child: Text(
                                      isMine
                                          ? tr('📍 My location (tap to open map)')
                                          : tr('📍 Location (tap to open map)'),
                                      style: const TextStyle(
                                          decoration: TextDecoration.underline),
                                    ),
                                  )
                                : Text(m['content'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (chatBlocked && status != 'COMPLETED' && status != 'DISPUTED')
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
          else if (status != 'COMPLETED' && status != 'DISPUTED')
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
                    IconButton(
                      icon: sendingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.location_on_outlined),
                      tooltip: tr('Share my location'),
                      onPressed: sendingLocation ? null : sendLocation,
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
                      onPressed: sendMessage,
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

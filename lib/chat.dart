import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'profiles.dart';

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

    // The server finds the other person and sends the notification.
    // If this fails, the chat itself still works.
    try {
      await supabase.functions.invoke('notify-chat-message', body: {
        'request_id': widget.requestId,
        'message': text,
      });
    } catch (e) {
      debugPrint('Push notification error: $e');
    }
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
          const SnackBar(
              content: Text('Transaction complete! You can now rate each other.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
        title: const Text('Report a problem'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: 'Describe what went wrong...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(reasonController.text),
            child: const Text('Submit'),
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
          const SnackBar(content: Text('Dispute submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
          const SnackBar(content: Text('Thanks for rating!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (status != null && status != 'COMPLETED' && status != 'DISPUTED')
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Report a problem',
              onPressed: actionLoading ? null : openDispute,
            ),
        ],
      ),
      body: Column(
        children: [
          if (otherProfile != null) ...[
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: ProfileSummary(profile: otherProfile),
            ),
            const Divider(height: 1),
          ],
          if (status == 'COMPLETED')
            Container(
              width: double.infinity,
              color: Colors.green.shade100,
              padding: const EdgeInsets.all(12),
              child: hasRated
                  ? const Text('✅ Transaction completed — thanks for rating!',
                      textAlign: TextAlign.center)
                  : Column(
                      children: [
                        const Text('✅ Transaction completed',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        const Text('Rate the other person:'),
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
                            decoration: const InputDecoration(
                              hintText: 'Optional comment...',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: ratingLoading ? null : submitRating,
                          child: Text(
                              ratingLoading ? 'Submitting...' : 'Submit rating'),
                        ),
                      ],
                    ),
            )
          else if (status == 'DISPUTED')
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text('⚠️ Dispute opened on this transaction',
                  textAlign: TextAlign.center),
            )
          else if (status != null)
            Container(
              width: double.infinity,
              color: Colors.teal.shade50,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    iHaveConfirmed
                        ? 'You confirmed. Waiting for the other side...'
                        : 'Once the exchange is done outside the app, confirm here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: (actionLoading || iHaveConfirmed)
                        ? null
                        : () => confirm(myRole),
                    child: Text(myRole == 'SENDER'
                        ? "I sent the money"
                        : "I received the money"),
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
                  return const Center(child: Text('No messages yet. Say hi!'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isSystem = m['type'] == 'SYSTEM';
                    final isMine = m['sender_id'] == myId;
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
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.teal.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m['content'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (status != 'COMPLETED' && status != 'DISPUTED')
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
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

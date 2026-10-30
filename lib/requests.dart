import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'profiles.dart';
import 'chat.dart';

// ---------------- My requests (mine + matched) ----------------

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  String type = 'SEND';
  final amountController = TextEditingController();
  String currency = 'USD';
  bool loading = false;
  String? errorMessage;

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final amount = double.tryParse(amountController.text.trim());
      if (amount == null || amount <= 0) {
        setState(() {
          errorMessage = 'Enter a valid amount';
          loading = false;
        });
        return;
      }
      await supabase.from('transaction_requests').insert({
        'type': type,
        'amount': amount,
        'currency': currency,
        'creator_id': supabase.auth.currentUser!.id,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const Text('What do you want to do?'),
            RadioListTile<String>(
              title: const Text('I want to SEND money'),
              value: 'SEND',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            RadioListTile<String>(
              title: const Text('I want to RECEIVE money'),
              value: 'RECEIVE',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: ['USD', 'EUR'].map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (v) => setState(() => currency = v!),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: Text(loading ? 'Please wait...' : 'Post request'),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------- My requests (mine + matched) ----------------

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<Map<String, dynamic>> myRequests = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final myId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('transaction_requests')
        .select()
        .or('creator_id.eq.$myId,matched_with_id.eq.$myId')
        .order('updated_at', ascending: false);
    final loaded = List<Map<String, dynamic>>.from(data);
    final loadedProfiles = await fetchPublicProfiles(
      loaded.map((r) => otherPartyId(r, myId)),
    );
    if (!mounted) return;
    setState(() {
      myRequests = loaded;
      profiles = loadedProfiles;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('My requests')),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : myRequests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('You have no requests yet.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: myRequests.length,
                    itemBuilder: (context, index) {
                      final r = myRequests[index];
                      final status = r['status'];
                      final otherId = otherPartyId(r, myId);
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                              '${r['type']} • ${r['amount']} ${r['currency']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Status: $status'),
                              const SizedBox(height: 6),
                              if (otherId != null)
                                ProfileSummary(
                                  profile: profiles[otherId],
                                  tappable: false,
                                )
                              else if (status == 'CANCELLED')
                                const Text(
                                  'Cancelled',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                )
                              else
                                const Text(
                                  'Waiting for someone to match',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                ),
                            ],
                          ),
                          trailing: status == 'OPEN'
                              ? IconButton(
                                  icon: const Icon(Icons.cancel_outlined),
                                  tooltip: 'Cancel request',
                                  onPressed: () async {
                                    await cancelMyRequest(context, r['id']);
                                    load();
                                  },
                                )
                              : status == 'CANCELLED'
                                  ? const Icon(Icons.block, color: Colors.grey)
                                  : const Icon(Icons.chat_bubble_outline),
                          onTap: (status == 'OPEN' || status == 'CANCELLED')
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChatScreen(requestId: r['id']),
                                    ),
                                  );
                                },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
// ---------------- Cancel my request ----------------

Future<void> cancelMyRequest(BuildContext context, String requestId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel this request?'),
      content: const Text('It will no longer be visible to other users.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Cancel request'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await supabase.rpc('cancel_request', params: {'p_request_id': requestId});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e')),
      );
    }
  }
}

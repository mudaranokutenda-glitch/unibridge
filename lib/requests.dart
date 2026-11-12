import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'profiles.dart';
import 'chat.dart';
import 'request_row.dart';
import 'l10n.dart';

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
          errorMessage = tr('Enter a valid amount');
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
      setState(() => errorMessage = tr('Something went wrong: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('New request'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(tr('What do you want to do?')),
            RadioListTile<String>(
              title: Text(tr('I want to SEND money')),
              value: 'SEND',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            RadioListTile<String>(
              title: Text(tr('I want to RECEIVE money')),
              value: 'RECEIVE',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: InputDecoration(labelText: tr('Amount')),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: InputDecoration(labelText: tr('Currency')),
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
              child: Text(loading ? tr('Please wait...') : tr('Post request')),
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
    return Scaffold(
      appBar: AppBar(title: Text(tr('My requests'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : myRequests.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: 100),
                      Center(child: Text(tr('You have no requests yet.'))),
                    ],
                  )
                : ListView.separated(
                    itemCount: myRequests.length,
                    separatorBuilder: (_, _) => const RequestRowDivider(),
                    itemBuilder: (context, index) => myRequestRow(
                      context,
                      myRequests[index],
                      profiles,
                      onChanged: load,
                    ),
                  ),
      ),
    );
  }
}
// ---------------- One row of "my requests" ----------------
// Shared by the My requests screen and the home screen.
// Cancel on my own open request; tap opens the chat once matched.

Widget myRequestRow(
  BuildContext context,
  Map<String, dynamic> r,
  Map<String, Map<String, dynamic>> profiles, {
  required VoidCallback onChanged,
}) {
  final myId = supabase.auth.currentUser!.id;
  final status = r['status'];
  final otherId = otherPartyId(r, myId);
  final other = otherId == null ? null : profiles[otherId];
  final hasChat =
      otherId != null && status != 'OPEN' && status != 'CANCELLED';
  return RequestRow(
    person: other,
    placeholderIcon:
        status == 'CANCELLED' ? Icons.block : Icons.hourglass_empty,
    placeholderTitle: status == 'CANCELLED'
        ? tr('Cancelled')
        : otherId == null
            ? tr('Waiting for someone to match')
            : tr('UniBridge user'),
    subtitle: other == null
        ? typeLabel(r['type'])
        : [typeLabel(r['type']), ratingText(other), completedText(other)]
            .join(' · '),
    amount: formatAmount(r['amount'], r['currency']),
    status: statusLabel(status),
    action: status == 'OPEN' && r['creator_id'] == myId
        ? IconButton(
            icon: const Icon(Icons.cancel_outlined),
            tooltip: tr('Cancel request'),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await cancelMyRequest(context, r['id']);
              onChanged();
            },
          )
        : null,
    onTap: hasChat
        ? () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(requestId: r['id']),
              ),
            );
            onChanged();
          }
        : null,
  );
}

// ---------------- Cancel my request ----------------

Future<void> cancelMyRequest(BuildContext context, String requestId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('Cancel this request?')),
      content: Text(tr('It will no longer be visible to other users.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(tr('Keep it')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(tr('Cancel request')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await supabase.rpc('cancel_request', params: {'p_request_id': requestId});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Request cancelled.'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not cancel: {error}', {'error': e}))),
      );
    }
  }
}

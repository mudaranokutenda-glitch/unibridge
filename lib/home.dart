import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'push.dart';
import 'profiles.dart';
import 'auth.dart';
import 'requests.dart';
import 'marketplace.dart';
import 'chat.dart';
import 'rates.dart';
import 'notifications.dart';

// ---------------- Home screen: browse + create requests ----------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> requests = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadRequests();
    // Covers the case where the app was already signed in from a previous
    // session (so AuthScreen's submit() never ran this time).
    setupPushNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) listenForForegroundNotifications(context);
    });
  }

  Future<void> loadRequests() async {
    setState(() => loading = true);
    final myId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('transaction_requests')
        .select()
        .eq('status', 'OPEN')
        .neq('creator_id', myId)
        .order('created_at', ascending: false);
    // Hide requests from people I blocked or who blocked me.
    final hidden = await fetchHiddenUserIds();
    final loaded = List<Map<String, dynamic>>.from(data)
        .where((r) => !hidden.contains(r['creator_id']))
        .toList();
    final loadedProfiles = await fetchPublicProfiles(
      loaded.map((r) => r['creator_id'] as String?),
    );
    if (!mounted) return;
    setState(() {
      requests = loaded;
      profiles = loadedProfiles;
      loading = false;
    });
  }

  Future<void> matchWithRequest(String requestId) async {
    try {
      await supabase.rpc('match_request', params: {'p_request_id': requestId});
      loadRequests();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(requestId: requestId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniBridge'),
        actions: [
                    const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditMyProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.currency_exchange),
            tooltip: 'Exchange rates',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExchangeRatesScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Marketplace',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'My requests',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;

              await clearPushToken();
              await supabase.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadRequests,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : requests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No open requests right now.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final r = requests[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['type']} • ${r['amount']} ${r['currency']}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        matchWithRequest(r['id']),
                                    child: const Text('Match'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ProfileSummary(
                                profile: profiles[r['creator_id']],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CreateRequestScreen()),
          );
          loadRequests();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

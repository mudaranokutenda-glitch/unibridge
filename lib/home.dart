import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'push.dart';
import 'profiles.dart';
import 'requests.dart';
import 'marketplace.dart';
import 'chat.dart';
import 'rates.dart';
import 'notifications.dart';
import 'posters.dart';
import 'l10n.dart';

// ---------------- Home: bottom navigation with 4 tabs ----------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    // Covers the case where the app was already signed in from a previous
    // session (so AuthScreen's submit() never ran this time).
    setupPushNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) listenForForegroundNotifications(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps each tab as it was when you come back to it.
      // A new language rebuilds all tabs so every text is translated.
      body: ValueListenableBuilder<String>(
        valueListenable: AppSettings.language,
        builder: (context, language, _) => KeyedSubtree(
          key: ValueKey(language),
          child: IndexedStack(
            index: tab,
            children: const [
              OpenRequestsScreen(),
              MarketplaceScreen(),
              ExchangeRatesScreen(),
              EditMyProfileScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.swap_horiz),
            label: tr('Requests'),
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: tr('Marketplace'),
          ),
          NavigationDestination(
            icon: Icon(Icons.currency_exchange),
            label: tr('Rates'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: tr('Profile'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Requests tab: browse + create requests ----------------

class OpenRequestsScreen extends StatefulWidget {
  const OpenRequestsScreen({super.key});
  @override
  State<OpenRequestsScreen> createState() => _OpenRequestsScreenState();
}

class _OpenRequestsScreenState extends State<OpenRequestsScreen> {
  List<Map<String, dynamic>> requests = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  // Filters (null = all)
  String? filterType;
  String? filterCurrency;
  String? filterWilaya;

  String creatorWilaya(Map<String, dynamic> r) {
    final w = (profiles[r['creator_id']]?['wilaya'] ?? '').toString().trim();
    return w == 'OTHER' ? '' : w;
  }

  List<String> optionsOf(String Function(Map<String, dynamic>) read) {
    final values = <String, String>{}; // lower case -> as written
    for (final r in requests) {
      final v = read(r).trim();
      if (v.isNotEmpty) values.putIfAbsent(v.toLowerCase(), () => v);
    }
    return values.values.toList()..sort();
  }

  List<Map<String, dynamic>> get visibleRequests => requests.where((r) {
        if (filterType != null && r['type'] != filterType) return false;
        if (filterCurrency != null && r['currency'] != filterCurrency) {
          return false;
        }
        if (filterWilaya != null &&
            creatorWilaya(r).toLowerCase() != filterWilaya!.toLowerCase()) {
          return false;
        }
        return true;
      }).toList();

  bool get hasFilters =>
      filterType != null || filterCurrency != null || filterWilaya != null;

  Widget filterDropdown({
    required String label,
    required String? value,
    required Map<String, String> options, // value -> text shown
    required ValueChanged<String?> onChanged,
  }) {
    // Keep the chosen value in the list even if no request uses it anymore
    // (a dropdown crashes when its value is missing from the items).
    if (value != null && !options.containsKey(value)) {
      options = {...options, value: value};
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: DropdownButton<String?>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(tr('{label}: All', {'label': label}))),
          for (final e in options.entries)
            DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          filterDropdown(
            label: tr('Type'),
            value: filterType,
            options: {'SEND': tr('Send'), 'RECEIVE': tr('Receive')},
            onChanged: (v) => setState(() => filterType = v),
          ),
          filterDropdown(
            label: tr('Currency'),
            value: filterCurrency,
            options: {
              for (final c in optionsOf((r) => '${r['currency'] ?? ''}')) c: c
            },
            onChanged: (v) => setState(() => filterCurrency = v),
          ),
          filterDropdown(
            label: tr('Wilaya'),
            value: filterWilaya,
            options: {for (final w in optionsOf(creatorWilaya)) w: w},
            onChanged: (v) => setState(() => filterWilaya = v),
          ),
          if (hasFilters)
            TextButton(
              onPressed: () => setState(() {
                filterType = null;
                filterCurrency = null;
                filterWilaya = null;
              }),
              child: Text(tr('Clear filters')),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    loadRequests();
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
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
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
            icon: const Icon(Icons.list_alt),
            tooltip: tr('My requests'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const PosterCarousel(),
          if (!loading && requests.isNotEmpty) filterBar(),
          Expanded(child: requestList()),
        ],
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

  Widget requestList() {
    final visible = visibleRequests;
    return RefreshIndicator(
        onRefresh: loadRequests,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : visible.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Text(requests.isEmpty
                            ? tr('No open requests right now.')
                            : tr('No requests match these filters.')),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final r = visible[index];
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
                                      tr(r['type'] == 'SEND' ? 'Wants to send {amount}' : 'Wants to receive {amount}',
                                          {'amount': '${r['amount']} ${r['currency']}'}),
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        matchWithRequest(r['id']),
                                    child: Text(tr('Match')),
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
    );
  }
}

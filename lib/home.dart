import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'push.dart';
import 'profiles.dart';
import 'requests.dart';
import 'marketplace.dart';
import 'chat.dart';
import 'rates.dart';
import 'notifications.dart';
import 'posters.dart';
import 'request_row.dart';
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
            children: [
              // Tapping my profile bar on the Requests tab opens the Profile tab.
              OpenRequestsScreen(onOpenProfile: () => setState(() => tab = 3)),
              const MarketplaceScreen(),
              const ExchangeRatesScreen(),
              const EditMyProfileScreen(),
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
  final VoidCallback? onOpenProfile;
  const OpenRequestsScreen({super.key, this.onOpenProfile});
  @override
  State<OpenRequestsScreen> createState() => _OpenRequestsScreenState();
}

class _OpenRequestsScreenState extends State<OpenRequestsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> requests = []; // other people's open requests
  List<Map<String, dynamic>> myRequests = []; // I created it or I matched it
  Set<String> ratedIds = {}; // requests I already rated
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
      padding: const EdgeInsetsDirectional.only(end: 8),
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
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
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

  // Live updates: any change in transaction_requests reloads both lists.
  RealtimeChannel? requestsChannel;
  Timer? reloadTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadRequests();
    requestsChannel = supabase
        .channel('home-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transaction_requests',
          callback: (_) => reloadSoon(),
        )
        .subscribe();
  }

  // Several changes often come together (match + status). Wait half a
  // second and reload once.
  void reloadSoon() {
    reloadTimer?.cancel();
    reloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) loadRequests(quiet: true);
    });
  }

  // Coming back to the app: reload, in case we missed a change while away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reloadSoon();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reloadTimer?.cancel();
    final channel = requestsChannel;
    if (channel != null) supabase.removeChannel(channel);
    super.dispose();
  }

  // quiet = no spinner (used by live updates, so the list does not flash).
  Future<void> loadRequests({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final myId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase
            .from('transaction_requests')
            .select()
            .eq('status', 'OPEN')
            .neq('creator_id', myId)
            .isFilter('archived_at', null)
            .order('created_at', ascending: false),
        supabase
            .from('transaction_requests')
            .select()
            .or('creator_id.eq.$myId,matched_with_id.eq.$myId')
            .isFilter('archived_at', null)
            .order('updated_at', ascending: false),
      ]);
      // Hide requests from people I blocked or who blocked me.
      final hidden = await fetchHiddenUserIds();
      final loaded = List<Map<String, dynamic>>.from(results[0])
          .where((r) => !hidden.contains(r['creator_id']))
          .toList();
      final mine = List<Map<String, dynamic>>.from(results[1]);
      final rated = await fetchMyRatedRequestIds();
      // My own profile is loaded too, for the profile bar at the top.
      final loadedProfiles = await fetchPublicProfiles([
        myId,
        ...loaded.map((r) => r['creator_id'] as String?),
        ...mine.map((r) => otherPartyId(r, myId)),
      ]);
      if (!mounted) return;
      setState(() {
        requests = loaded;
        myRequests = mine;
        ratedIds = rated;
        profiles = loadedProfiles;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
        );
      }
    }
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
      // Maybe someone else matched it first: refresh the list.
      loadRequests(quiet: true);
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
          MyProfileBar(
            profile: profiles[supabase.auth.currentUser!.id],
            loading: loading,
            onTap: () => widget.onOpenProfile?.call(),
          ),
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

  // Small section title ("My requests", "Open requests").
  Widget sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget emptyLine(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  // Rows with a thin divider between them (none after the last one).
  List<Widget> withDividers(List<Widget> rows) => [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const RequestRowDivider(),
          rows[i],
        ],
      ];

  // One scrolling page: posters, My requests, then Open requests.
  Widget requestList() {
    final visible = visibleRequests;
    return RefreshIndicator(
      onRefresh: loadRequests,
      child: ListView(
        // Room at the bottom so the + button never covers the last row.
        padding: const EdgeInsetsDirectional.only(bottom: 88),
        children: [
          const PosterCarousel(),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            sectionHeader(tr('My requests')),
            if (myRequests.isEmpty)
              emptyLine(tr('You have no requests yet.'))
            else
              ...withDividers([
                for (final r in myRequests)
                  myRequestRow(context, r, profiles,
                      ratedIds: ratedIds,
                      onChanged: () => loadRequests(quiet: true)),
              ]),
            sectionHeader(tr('Open requests')),
            if (requests.isNotEmpty) filterBar(),
            if (visible.isEmpty)
              emptyLine(requests.isEmpty
                  ? tr('No open requests right now.')
                  : tr('No requests match these filters.'))
            else
              ...withDividers([
                for (final r in visible) openRequestRow(r),
              ]),
          ],
        ],
      ),
    );
  }

  Widget openRequestRow(Map<String, dynamic> r) {
    final creator = profiles[r['creator_id']];
    return RequestRow(
      person: creator,
      subtitle: [
        typeLabel(r['type']),
        ratingText(creator),
        completedText(creator),
      ].join(' · '),
      amount: formatAmount(r['amount'], r['currency']),
      status: statusLabel(r['status']),
      action: SmallRowButton(
        label: tr('Match'),
        onPressed: () => matchWithRequest(r['id']),
      ),
      // Not matched yet, so no chat: show who created it.
      onTap: creator == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      UserProfileScreen(userId: creator['id'].toString()),
                ),
              ),
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'push.dart';
import 'profiles.dart';
import 'requests.dart';
import 'marketplace.dart';
import 'chat.dart';
import 'rates.dart';
import 'student_space.dart';
import 'staff_tools.dart';
import 'notifications.dart';
import 'posters.dart';
import 'request_row.dart';
import 'bottom_bar.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'errors.dart';
import 'l10n.dart';

// ---------------- Home: bottom navigation with 4 tabs ----------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  // Bumped each time the Marketplace tab is opened (it then reloads).
  final marketplaceReload = ValueNotifier<int>(0);
  // Bumped after a new request was made (the Requests tab then reloads).
  final requestsReload = ValueNotifier<int>(0);

  void selectTab(int i) {
    setState(() => tab = i);
    if (i == 1) marketplaceReload.value++;
  }

  // The round "+" in the middle of the bottom bar.
  Future<void> openNewRequest() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateRequestScreen()),
    );
    if (!mounted) return;
    selectTab(0);
    requestsReload.value++;
  }

  @override
  void dispose() {
    marketplaceReload.dispose();
    requestsReload.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Covers the case where the app was already signed in from a previous
    // session (so AuthScreen's submit() never ran this time).
    setupPushNotifications();
    // The red number on every bell (live).
    NotificationCenter.start();
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
              OpenRequestsScreen(
                  onOpenProfile: () => selectTab(3),
                  reloadSignal: requestsReload),
              MarketplaceScreen(reloadSignal: marketplaceReload),
              const StudentSpaceScreen(),
              const EditMyProfileScreen(),
            ],
          ),
        ),
      ),
      floatingActionButton: NewRequestButton(onPressed: openNewRequest),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar:
          AppBottomBar(selectedIndex: tab, onSelect: selectTab),
    );
  }
}

// ---------------- Requests tab: browse + create requests ----------------

class OpenRequestsScreen extends StatefulWidget {
  final VoidCallback? onOpenProfile;
  final ValueListenable<int>? reloadSignal;
  const OpenRequestsScreen({super.key, this.onOpenProfile, this.reloadSignal});
  @override
  State<OpenRequestsScreen> createState() => _OpenRequestsScreenState();
}

class _OpenRequestsScreenState extends State<OpenRequestsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> requests = []; // other people's open requests
  List<Map<String, dynamic>> myRequests = []; // I created it or I matched it
  Set<String> ratedIds = {}; // requests I already rated
  List<Map<String, dynamic>> suggestions = []; // suggested matches for me
  Map<String, dynamic>? recentAlert; // emergency alert of the last 3 days
  String? hiddenAlertId; // the alert I closed
  String? respondingTo; // suggestion being accepted / declined
  String? matchingId; // request being matched (the button is locked meanwhile)
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  // The wilaya of the person who posted the request ('' if unknown).
  String creatorWilaya(Map<String, dynamic> r) {
    final w = (profiles[r['creator_id']]?['wilaya'] ?? '').toString().trim();
    return w == 'OTHER' ? '' : w;
  }

  // Live updates: any change in transaction_requests reloads both lists.
  RealtimeChannel? requestsChannel;
  Timer? reloadTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadRequests();
    widget.reloadSignal?.addListener(reloadFromSignal);
    // An emergency alert arrived while the app is open: show the banner.
    onEmergencyAlertReceived = () => reloadSoon();
    requestsChannel = supabase
        .channel('home-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transaction_requests',
          callback: (_) => reloadSoon(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'match_suggestions',
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

  void reloadFromSignal() => loadRequests(quiet: true);

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(reloadFromSignal);
    WidgetsBinding.instance.removeObserver(this);
    onEmergencyAlertReceived = null;
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
      await loadRequestExpiryHours();
      // An expired request leaves the open list at once (the database job
      // cancels it within 15 minutes).
      final loaded = List<Map<String, dynamic>>.from(results[0])
          .where((r) => !hidden.contains(r['creator_id']))
          .where((r) => !requestIsExpired(r))
          .toList();
      final mine = List<Map<String, dynamic>>.from(results[1]);
      List<Map<String, dynamic>> loadedSuggestions = [];
      try {
        loadedSuggestions = List<Map<String, dynamic>>.from(
            await supabase.rpc('my_match_suggestions') as List);
      } catch (e) {
        debugPrint('Could not load suggestions: $e');
      }
      final rated = await fetchMyRatedRequestIds();
      final alert = await loadRecentAlert();
      // My own profile is loaded too, for the profile bar at the top.
      final loadedProfiles = await fetchPublicProfiles([
        myId,
        ...loaded.map((r) => r['creator_id'] as String?),
        ...mine.map((r) => otherPartyId(r, myId)),
        ...loadedSuggestions.map((x) => x['other_user_id']?.toString()),
      ]);
      if (!mounted) return;
      setState(() {
        requests = loaded;
        myRequests = mine;
        suggestions = loadedSuggestions;
        ratedIds = rated;
        recentAlert = alert;
        profiles = loadedProfiles;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> matchWithRequest(Map<String, dynamic> r) async {
    final String requestId = r['id'].toString();
    if (matchingId != null) return;
    // Matching opens a real exchange with this person: ask first.
    final creator = profiles[r['creator_id']];
    final name = creator == null ? tr('this student') : publicDisplayName(creator);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Match with {name}?', {'name': name})),
        content: Text(tr(
            '{request}. A chat opens with this student. Only exchange money when you both agree.',
            {'request': requestHeadline(r)})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Match')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => matchingId = requestId);
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
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => matchingId = null);
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
            icon: const AppIcon(
                name: 'rates',
                fallback: Icons.currency_exchange,
                size: 22,
                circle: true),
            tooltip: tr('Exchange rates'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExchangeRatesScreen()),
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

  // "New requests (9)": the title with the number in green.
  Widget newRequestsHeader(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
          children: [
            TextSpan(text: tr('New requests')),
            const TextSpan(text: ' '),
            TextSpan(
              text: '($count)',
              style: const TextStyle(
                  color: AppColors.success, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // One scrolling page: posters, NEW requests (on top), suggestions, mine.
  Widget requestList() {
    return RefreshIndicator(
      onRefresh: loadRequests,
      child: ListView(
        // Room at the bottom so the + button never covers the last row.
        padding: const EdgeInsetsDirectional.only(bottom: 88),
        children: [
          if (recentAlert != null && recentAlert!['id'] != hiddenAlertId)
            AlertBanner(
              alert: recentAlert!,
              onClose: () =>
                  setState(() => hiddenAlertId = recentAlert!['id']?.toString()),
            ),
          const PosterCarousel(),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            newRequestsHeader(requests.length),
            if (requests.isEmpty)
              emptyLine(tr('No open requests right now.'))
            else
              ...withDividers([
                for (final r in requests) openRequestRow(r),
              ]),
            if (suggestions.isNotEmpty) ...[
              sectionHeader(tr('Suggested matches')),
              for (final x in suggestions) suggestionCard(x),
            ],
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
          ],
        ],
      ),
    );
  }

  // Accept or decline a suggested match. Both must accept.
  Future<void> respondToSuggestion(String id, bool accept) async {
    setState(() => respondingTo = id);
    try {
      final matched = await supabase.rpc('respond_match_suggestion',
          params: {'p_id': id, 'p_accept': accept});
      await loadRequests(quiet: true);
      if (!mounted) return;
      if (matched != null) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(requestId: matched.toString())));
      } else {
        // After an accept, a suggestion that has disappeared from my list
        // was closed by the database (a request is no longer open, or a block).
        final gone = accept && !suggestions.any((x) => x['id'].toString() == id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(gone
                ? tr('This match is no longer available.')
                : accept
                    ? tr('Accepted. Waiting for the other student.')
                    : tr('Suggestion declined.'))));
      }
    } catch (e) {
      await loadRequests(quiet: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => respondingTo = null);
    }
  }

  Widget suggestionCard(Map<String, dynamic> x) {
    final id = x['id'].toString();
    final other = profiles[x['other_user_id']?.toString()];
    final busy = respondingTo == id;
    final iAccepted = x['i_accepted'] == true;
    final expires = DateTime.tryParse('${x['expires_at']}')?.toLocal();
    final hoursLeft =
        expires?.difference(DateTime.now()).inHours;
    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('A match is available. Accept or decline'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            RequestRow(
              person: other,
              subtitle: [ratingText(other), completedText(other)].join(' · '),
              amount: formatAmount(x['amount'], x['currency']),
              status: tr('Your request: {type}', {'type': typeLabel(x['my_type'])}),
            ),
            if (hoursLeft != null)
              Text(tr('Expires in {hours} h', {'hours': hoursLeft < 0 ? 0 : hoursLeft}),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            if (iAccepted)
              Text(tr('You accepted. Waiting for the other student.'))
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => respondToSuggestion(id, false),
                    child: Text(tr('Decline')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : () => respondToSuggestion(id, true),
                    child: Text(tr('Accept')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget openRequestRow(Map<String, dynamic> r) {
    final creator = profiles[r['creator_id']];
    final busy = matchingId == r['id'].toString();
    return RequestRow(
      person: creator,
      // "Anyone to receive 30 USD" right under the name.
      headline: requestHeadline(r),
      subtitle: [
        if (creatorWilaya(r).isNotEmpty) creatorWilaya(r),
        ratingText(creator),
        completedText(creator),
      ].join(' · '),
      action: SmallRowButton(
        label: busy ? '...' : tr('Match'),
        onPressed: matchingId != null ? null : () => matchWithRequest(r),
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

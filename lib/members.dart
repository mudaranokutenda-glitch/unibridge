import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'config.dart';
import 'profiles.dart';
import 'student_info.dart';
import 'student_space.dart';
import 'l10n.dart';
import 'errors.dart';

// Student space membership approval (SQL: sql/2026-11-16-01-members.sql).
// The REAL protection is in the database rules (RLS). This file only shows the
// right screen: "Join the student space", "Waiting", "Not approved", or the
// normal Student space for approved members and staff.

// ---------------- The gate around the Student space ----------------

class MembershipGate extends StatefulWidget {
  final Widget child; // the normal Student space
  const MembershipGate({super.key, required this.child});

  @override
  State<MembershipGate> createState() => _MembershipGateState();
}

enum _Gate { loading, member, none, pending, rejected, error }

class _MembershipGateState extends State<MembershipGate> {
  _Gate state = _Gate.loading;
  String? wilaya; // my profile wilaya
  String? errorText;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => state = _Gate.loading);
    try {
      final member = await supabase.rpc('is_member');
      if (member == true) {
        if (mounted) setState(() => state = _Gate.member);
        return;
      }
      final myId = supabase.auth.currentUser!.id;
      final row = await supabase
          .from('space_members')
          .select('status')
          .eq('user_id', myId)
          .maybeSingle();
      final profile = await supabase
          .from('profiles')
          .select('wilaya')
          .eq('id', myId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        wilaya = (profile?['wilaya'] ?? '').toString().trim();
        if (wilaya!.isEmpty) wilaya = null;
        final status = row?['status']?.toString();
        state = status == 'PENDING'
            ? _Gate.pending
            : status == 'REJECTED'
                ? _Gate.rejected
                : _Gate.none;
      });
    } on PostgrestException catch (e) {
      // The SQL file was not run yet: the function does not exist, and the
      // database does not close the Student space either. Show it as before.
      if (e.code == 'PGRST202' || e.code == '42883') {
        if (mounted) setState(() => state = _Gate.member);
        return;
      }
      if (mounted) {
        setState(() {
          state = _Gate.error;
          errorText = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          state = _Gate.error;
          errorText = friendlyError(e);
        });
      }
    }
  }

  Future<void> requestToJoin() async {
    setState(() => busy = true);
    try {
      await supabase.rpc('request_membership');
      if (mounted) showSnack(context, tr('Request sent.'));
    } on PostgrestException catch (e) {
      // Messages written by the database are shown as they are.
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _Gate.member:
        return widget.child;
      case _Gate.loading:
        return Scaffold(
          appBar: AppBar(title: Text(tr('Student space'))),
          body: const Center(child: CircularProgressIndicator()),
        );
      case _Gate.error:
        return Scaffold(
          appBar: AppBar(title: Text(tr('Student space'))),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Error: {error}', {'error': errorText ?? ''}),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: load, child: Text(tr('Try again'))),
                ],
              ),
            ),
          ),
        );
      case _Gate.pending:
        return _gateScaffold(
          icon: Icons.hourglass_top_outlined,
          title: tr('Waiting for approval by your Governor'),
          body: tr('You will get a notification when your request is answered.'),
          button: OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: Text(tr('Check again')),
          ),
        );
      case _Gate.rejected:
        return _gateScaffold(
          icon: Icons.block_outlined,
          title: tr('Your request was not approved.'),
          body: tr('You can ask again 24 hours after the answer, or contact your Governor.'),
          button: FilledButton(
            onPressed: busy ? null : requestToJoin,
            child: Text(tr('Request to join')),
          ),
        );
      case _Gate.none:
        return _gateScaffold(
          icon: Icons.groups_outlined,
          title: tr('Join the student space'),
          body: wilaya == null
              ? tr('Choose your wilaya in your profile first.')
              : tr('The student space has your contacts, the guide and your appointments. The Governor of your wilaya approves new members.'),
          extra: wilaya == null
              ? null
              : Text(tr('Your wilaya: {wilaya}', {'wilaya': wilaya!}),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
          button: FilledButton(
            onPressed: (busy || wilaya == null) ? null : requestToJoin,
            child: Text(tr('Request to join')),
          ),
        );
    }
  }

  Widget _gateScaffold({
    required IconData icon,
    required String title,
    required String body,
    Widget? extra,
    required Widget button,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Student space'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: scheme.primary),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              if (extra != null) ...[const SizedBox(height: 12), extra],
              const SizedBox(height: 20),
              button,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Join requests (Governors, attaché, admin) ----------------

class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? busyId;
  String? errorText;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final data = await supabase.rpc('pending_members');
      if (!mounted) return;
      setState(() {
        items = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          errorText = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          errorText = friendlyError(e);
        });
      }
    }
  }

  Future<void> decide(Map<String, dynamic> r, bool approve) async {
    final name = publicDisplayName(r);
    final ok = await confirmDialog(
      context,
      approve
          ? tr('Approve {name} as a member of the student space?', {'name': name})
          : tr('Reject the request of {name}?', {'name': name}),
      okLabel: approve ? tr('Approve') : tr('Reject'),
    );
    if (!ok) return;
    final id = r['user_id'].toString();
    setState(() => busyId = id);
    try {
      await supabase.rpc('decide_membership',
          params: {'p_user': id, 'p_approve': approve});
      if (mounted) {
        showSnack(context, approve ? tr('Approved.') : tr('Rejected.'));
      }
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Join requests'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : errorText != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Error: {error}', {'error': errorText!}),
                        textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: items.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                  child: Text(tr('No requests are waiting.'))),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = items[i];
                            final id = r['user_id'].toString();
                            final busy = busyId == id;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      avatar(r, radius: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(publicDisplayName(r),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            Text(
                                                '${r['wilaya'] ?? ''} · ${shortDate(r['requested_at'])}'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed:
                                            busy ? null : () => decide(r, false),
                                        child: Text(tr('Reject')),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed:
                                            busy ? null : () => decide(r, true),
                                        child: Text(tr('Approve')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

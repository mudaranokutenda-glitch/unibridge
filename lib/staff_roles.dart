import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'errors.dart';
import 'l10n.dart';
import 'student_space.dart';
import 'wilayas.dart';

// ---------------- Staff hub -> Roles (admin only) ----------------
// Find a person by name or email and make them Student, Governor (with
// their wilaya), Educational Attache or Admin. The database checks again
// that the person pressing the button is an admin, and logs every change.

String roleLabel(String? role) => switch (role) {
      'rep' => tr('Governor'),
      'attache' => tr('Educational Attaché'),
      'admin' => tr('Admin'),
      _ => tr('Student'),
    };

class StaffRolesScreen extends StatefulWidget {
  const StaffRolesScreen({super.key});
  @override
  State<StaffRolesScreen> createState() => _StaffRolesScreenState();
}

class _StaffRolesScreenState extends State<StaffRolesScreen> {
  final searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> people = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    search(); // empty search = the current staff and Governors
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void onTyping(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), search);
  }

  Future<void> search() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await supabase.rpc('admin_find_users',
          params: {'p_query': searchController.text.trim()});
      if (!mounted) return;
      setState(() {
        people = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = friendlyError(e, short: true);
      });
    }
  }

  Future<void> edit(Map<String, dynamic> person) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleSheet(person: person),
    );
    if (changed == true) search();
  }

  @override
  Widget build(BuildContext context) {
    final searching = searchController.text.trim().isNotEmpty;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Roles'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottom),
        children: [
          TextField(
            controller: searchController,
            onChanged: onTyping,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: tr('Name or email'),
              helperText: tr('Type at least 2 letters.'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            searching ? tr('Results') : tr('Staff and Governors now'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Text(error!, style: const TextStyle(color: Colors.redAccent))
          else if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(searching
                  ? tr('Nobody found.')
                  : tr('Nobody has a role yet. Search for a person above.')),
            )
          else
            for (final p in people)
              Card(
                child: ListTile(
                  leading: Icon(p['role'] == 'student'
                      ? Icons.person_outline
                      : Icons.verified_user_outlined),
                  title: Text((p['full_name'] ?? '').toString().trim().isEmpty
                      ? tr('AZSA user')
                      : p['full_name'].toString()),
                  subtitle: Text([
                    (p['email'] ?? '').toString(),
                    p['role'] == 'rep'
                        ? '${roleLabel('rep')} · ${p['rep_wilaya'] ?? ''}'
                        : roleLabel(p['role']?.toString()),
                  ].where((s) => s.isNotEmpty).join('\n')),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => edit(p),
                ),
              ),
        ],
      ),
    );
  }
}

class _RoleSheet extends StatefulWidget {
  final Map<String, dynamic> person;
  const _RoleSheet({required this.person});
  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late String role = (widget.person['role'] ?? 'student').toString();
  late String? wilaya = validWilaya(widget.person['rep_wilaya']);
  bool saving = false;

  Future<void> save() async {
    if (role == 'rep' && wilaya == null) {
      showSnack(context, tr("Choose the Governor's wilaya."));
      return;
    }
    setState(() => saving = true);
    try {
      await supabase.rpc('admin_set_role', params: {
        'p_user': widget.person['id'],
        'p_role': role,
        'p_wilaya': role == 'rep' ? wilaya : null,
      });
      if (!mounted) return;
      showSnack(
          context,
          tr('Saved. They see the new role after reopening the app.'));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      showSnack(context, tr('Could not save: {error}', {'error': e.message}));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      showSnack(context,
          tr('Could not save: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.person['full_name'] ?? '').toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name.isEmpty ? tr('AZSA user') : name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text((widget.person['email'] ?? '').toString(),
              style: const TextStyle(color: kMutedText)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: role,
            onChanged: (v) => setState(() => role = v ?? role),
            child: Column(
              children: [
                for (final r in const ['student', 'rep', 'attache', 'admin'])
                  RadioListTile<String>(
                    value: r,
                    title: Text(roleLabel(r)),
                    subtitle: Text(switch (r) {
                      'rep' => tr('Sees only the students of their wilaya. Never passports.'),
                      'attache' => tr('Sees all students and documents. Every opening is recorded.'),
                      'admin' => tr('Everything, and can give roles.'),
                      _ => tr('A normal member.'),
                    }),
                  ),
              ],
            ),
          ),
          if (role == 'rep')
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: WilayaDropdown(
                value: wilaya,
                label: tr("Governor's wilaya"),
                onChanged: (w) => setState(() => wilaya = w),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: saving ? null : save,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('Save')),
          ),
        ],
      ),
    );
  }
}

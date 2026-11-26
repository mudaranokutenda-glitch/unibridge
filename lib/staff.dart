import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'app_theme.dart';
import 'roles.dart';
import 'wilayas.dart';
import 'student_space.dart';
import 'posters.dart';
import 'student_info.dart';
import 'staff_tools.dart';
import 'staff_roles.dart';
import 'rates.dart';
import 'l10n.dart';
import 'errors.dart';

// ---------------- Staff screens (attache, admin, rep) ----------------
// Hiding these buttons is NOT the security. The database rules and the
// Edge Functions check the role again for every request.

// Calls an Edge Function and returns its JSON answer, or throws a readable error.
Future<Map<String, dynamic>> callFunction(
    String name, Map<String, dynamic> body) async {
  try {
    final res = await supabase.functions.invoke(name, body: body);
    return Map<String, dynamic>.from(res.data as Map);
  } on FunctionException catch (e) {
    final d = e.details;
    throw Exception(d is Map ? d['error'] : d);
  }
}

// Opens a student's results or passport through staff-documents (logged).
Future<void> openStaffDocument(
    BuildContext context, String kind, String id) async {
  try {
    final res =
        await callFunction('staff-documents', {'action': 'open', 'kind': kind, 'id': id});
    if (context.mounted) await openLink(context, res['url'] as String);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, tr('Could not open the file: {error}', {'error': friendlyError(e, short: true)}));
    }
  }
}

String studentName(Map<String, dynamic>? r) =>
    r == null ? tr('No student record') : '${r['last_name']} ${r['first_name']}';

// The staff buttons shown in the Profile tab.
// ---------------- Staff hub ----------------
// On the Profile tab staff and Governors see ONE card. It opens the Staff hub:
// a search box and all their tools as coloured tiles, grouped by topic.

class StaffTool {
  final IconData icon;
  final String label;
  final String description;
  final String group;
  final Color color;
  final Widget Function() screen;
  const StaffTool(this.icon, this.label, this.description, this.group,
      this.color, this.screen);
}

List<StaffTool> staffToolsFor(MyRole role) {
  const students = Color(0xFF2F80ED);
  const documents = Color(0xFF8E5CF7);
  const contact = Color(0xFFE08A1E);
  const money = Color(0xFF2E9E5B);
  if (role.isStaff) {
    return [
      StaffTool(Icons.person_search_outlined, tr('Search students'),
          tr('Find a student by name or number'), tr('Students'), students,
          () => const StaffSearchScreen()),
      StaffTool(Icons.groups_outlined, tr('Students'),
          tr('All students and their records'), tr('Students'), students,
          () => StudentsScreen(role: role)),
      StaffTool(Icons.bar_chart_outlined, tr('Dashboard'),
          tr('Numbers per wilaya'), tr('Students'), students,
          () => const StudentsDashboardScreen()),
      StaffTool(Icons.table_chart_outlined, tr('Final list of students'),
          tr('The list to export'), tr('Students'), students,
          () => const FinalListScreen()),
      StaffTool(Icons.workspace_premium_outlined, tr('Attestation requests'),
          tr('Review and issue attestations'), tr('Documents'), documents,
          () => const AttestationRequestsScreen()),
      StaffTool(Icons.event_outlined, tr('Appointments'),
          tr('Requests to meet the Attaché'), tr('Documents'), documents,
          () => const StaffAppointmentsScreen()),
      StaffTool(Icons.history, tr('Recent access'),
          tr('Who opened which document'), tr('Documents'), documents,
          () => const RecentAccessScreen()),
      StaffTool(Icons.currency_exchange, tr('Parallel rates'),
          tr("Type today's square rate"), tr('Communication'), contact,
          () => const ParallelRatesEditScreen()),
      StaffTool(Icons.campaign_outlined, tr('Emergency alert'),
          tr('Urgent message to every student'), tr('Communication'), contact,
          () => const EmergencyAlertScreen()),
      StaffTool(Icons.view_carousel_outlined, tr('Posters'),
          tr('Images on the home screen'), tr('Communication'), contact,
          () => const ManagePostersScreen()),
      StaffTool(Icons.contact_phone_outlined, tr('Governors\' contacts'),
          tr('Phone numbers of the Governors'), tr('Communication'), contact,
          () => const ManageContactsScreen(onlyKind: 'governor')),
      StaffTool(Icons.edit_note_outlined, tr('Manage contacts'),
          tr('Contacts shown to students'), tr('Communication'), contact,
          () => const ManageContactsScreen()),
      // Only the admin can give roles (the database checks it again).
      if (role.isAdmin)
        StaffTool(Icons.admin_panel_settings_outlined, tr('Roles'),
            tr('Make someone Governor, Attaché or Admin'), tr('Admin'),
            const Color(0xFFD64545), () => const StaffRolesScreen()),
    ];
  }
  if (role.isRep) {
    return [
      StaffTool(Icons.groups_outlined, tr('Students'),
          tr('Students of your wilaya'), tr('Students'), students,
          () => StudentsScreen(role: role)),
      StaffTool(Icons.bar_chart_outlined, tr('Dashboard'),
          tr('Numbers for your wilaya'), tr('Students'), students,
          () => const StudentsDashboardScreen()),
      StaffTool(Icons.fact_check_outlined, tr('Results tracker'),
          tr('Who sent their results'), tr('Students'), students,
          () => const ResultsTrackerScreen()),
      StaffTool(Icons.assignment_late_outlined, tr('No student record yet'),
          tr('Students to remind'), tr('Students'), students,
          () => const MissingRecordsScreen()),
      StaffTool(Icons.account_balance_outlined, tr('Bank accounts'),
          tr('Opening one is recorded'), tr('Money'), money,
          () => const GovernorBankAccountsScreen()),
      StaffTool(Icons.support_agent_outlined, tr('Contact the Educational Attaché'),
          tr('Phone numbers and emails'), tr('Communication'), contact,
          () => const ContactsScreen()),
    ];
  }
  return [];
}

// The single card on the Profile tab.
class StaffSection extends StatelessWidget {
  final MyRole role;
  const StaffSection({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    if (!role.canSeeStudents) return const SizedBox.shrink();
    final tools = staffToolsFor(role);
    final title = role.isStaff
        ? tr('Staff ({role})', {'role': role.role})
        : tr('Governor of {wilaya}', {'wilaya': role.repWilaya});
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StaffHubScreen(role: role))),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1F63C2), Color(0xFF6A3FD1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.admin_panel_settings_outlined,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Staff hub'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '$title · ${tr('{count} tools', {'count': tools.length})}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// All tools: search box + tiles grouped by topic.
class StaffHubScreen extends StatefulWidget {
  final MyRole role;
  const StaffHubScreen({super.key, required this.role});

  @override
  State<StaffHubScreen> createState() => _StaffHubScreenState();
}

class _StaffHubScreenState extends State<StaffHubScreen> {
  final searchController = TextEditingController();
  String query = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Widget tile(StaffTool t) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => t.screen())),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: t.color.withValues(alpha: 0.14),
                child: Icon(t.icon, color: t.color),
              ),
              const Spacer(),
              Text(t.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(t.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final tools = staffToolsFor(widget.role)
        .where((t) =>
            q.isEmpty ||
            t.label.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q) ||
            t.group.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<StaffTool>>{};
    for (final t in tools) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Staff hub'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: searchController,
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: tr('Search a tool (attestation, alert, bank...)'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Clear'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        searchController.clear();
                        query = '';
                      }),
                    ),
            ),
          ),
          if (tools.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(tr('No tool matches "{q}".', {'q': query}),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
              child: Text(entry.key,
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [for (final t in entry.value) tile(t)],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------- C2. Attestation requests (attache, admin) ----------------

class AttestationRequestsScreen extends StatefulWidget {
  const AttestationRequestsScreen({super.key});

  @override
  State<AttestationRequestsScreen> createState() =>
      _AttestationRequestsScreenState();
}

class _AttestationRequestsScreenState extends State<AttestationRequestsScreen> {
  List<Map<String, dynamic>> requests = [];
  Map<String, Map<String, dynamic>> records = {};
  bool loading = true;
  bool openOnly = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      var query = supabase.from('attestation_requests').select();
      if (openOnly) query = query.inFilter('status', ['PENDING', 'IN_REVIEW']);
      final data = await query.order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(data);
      final ids = list.map((r) => r['user_id']).toSet().toList();
      final recs = ids.isEmpty
          ? []
          : await supabase.from('student_records').select().inFilter('user_id', ids);
      if (!mounted) return;
      setState(() {
        requests = list;
        records = {for (final r in recs) r['user_id'].toString(): r};
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Attestation requests'))),
      body: Column(
        children: [
          SwitchListTile(
            title: Text(tr('Only requests still to do')),
            value: openOnly,
            onChanged: (v) {
              setState(() => openOnly = v);
              load();
            },
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : requests.isEmpty
                    ? Center(child: Text(tr('No requests.')))
                    : RefreshIndicator(
                        onRefresh: load,
                        child: ListView.builder(
                          itemCount: requests.length,
                          itemBuilder: (context, i) {
                            final r = requests[i];
                            final rec = records[r['user_id']];
                            return ListTile(
                              leading: Icon(Icons.circle,
                                  size: 12, color: attestationColor(r['status'])),
                              title: Text(studentName(rec)),
                              subtitle: Text(
                                  '${tr(kAttestationStatus[r['status']] ?? '${r['status']}')} · ${shortDate(r['created_at'])}'
                                  '${rec == null ? '' : ' · ${rec['wilaya']}'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => AttestationReviewScreen(
                                      request: r, record: rec),
                                ));
                                load();
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class AttestationReviewScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final Map<String, dynamic>? record;
  const AttestationReviewScreen(
      {super.key, required this.request, required this.record});

  @override
  State<AttestationReviewScreen> createState() =>
      _AttestationReviewScreenState();
}

class _AttestationReviewScreenState extends State<AttestationReviewScreen> {
  late Map<String, dynamic> r = widget.request;
  bool busy = false;

  String get id => r['id'].toString();
  bool get isClosed => r['status'] == 'ISSUED' || r['status'] == 'REJECTED';

  Future<void> reload() async {
    final data = await supabase
        .from('attestation_requests')
        .select()
        .eq('id', id)
        .single();
    if (mounted) setState(() => r = data);
  }

  Future<void> run(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      await reload();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setStatus(String status, {String? note, String? path}) =>
      supabase.rpc('set_attestation_status', params: {
        'p_request_id': id,
        'p_status': status,
        'p_note': note,
        'p_attestation_path': path,
      });

  Future<void> issue() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;
    if ((file.extension ?? '').toLowerCase() != 'pdf') {
      if (mounted) showSnack(context, tr('Please choose a PDF file.'));
      return;
    }
    if ((await file.length() ?? 0) > kMaxDocumentBytes) {
      if (mounted) showSnack(context, tr('This file is too big (max 10 MB).'));
      return;
    }
    await run(() async {
      final path =
          '${r['user_id']}/${id}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await supabase.storage.from('attestations').uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      await setStatus('ISSUED', path: path);
    }, tr('Attestation issued. The student was notified.'));
  }

  Future<void> reject() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Reject request')),
        content: TextField(
          controller: note,
          maxLength: 1000,
          maxLines: 3,
          decoration: InputDecoration(
              hintText: tr('Note for the student (required)')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Reject')),
          ),
        ],
      ),
    );
    if (ok != true || note.text.trim().isEmpty) return;
    await run(() => setStatus('REJECTED', note: note.text.trim()),
        tr('Request rejected. The student was notified.'));
  }

  Future<void> deletePassport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete the passport scan now?')),
        content: Text(tr('This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run(
        () => callFunction(
            'staff-documents', {'action': 'delete_passport', 'id': id}),
        tr('Passport scan deleted.'));
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.record;
    final hasPassport = r['passport_path'] != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Attestation request'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(studentName(rec), style: Theme.of(context).textTheme.titleLarge),
          if (rec != null) ...[
            Text('${tr('Inscription number')}: ${rec['inscription_number']}'),
            Text('${rec['program']} · ${tr('${rec['level']}')}'),
            Text('${rec['wilaya']} · ${rec['academic_year']}'),
          ],
          const SizedBox(height: 12),
          Text(
            '${tr('Status')}: ${tr(kAttestationStatus[r['status']] ?? '${r['status']}')}',
            style: TextStyle(
                color: attestationColor(r['status']),
                fontWeight: FontWeight.w600),
          ),
          Text('${tr('Sent on')}: ${shortDate(r['created_at'])}'),
          Text('${tr('Date of entry into Algeria')}: ${r['entry_date'] == null ? '—' : shortDate(r['entry_date'])}'),
          if ((r['note'] ?? '').toString().isNotEmpty)
            Text(tr('Note: {note}', {'note': r['note']})),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy || !hasPassport
                ? null
                : () => openStaffDocument(context, 'PASSPORT', id),
            icon: const Icon(Icons.badge_outlined),
            label: Text(hasPassport
                ? tr('Open passport (recorded in the access log)')
                : tr('Passport scan deleted on {date}',
                    {'date': shortDate(r['passport_deleted_at'])})),
          ),
          const SizedBox(height: 12),
          if (!isClosed) ...[
            if (r['status'] == 'PENDING')
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() => setStatus('IN_REVIEW'),
                        tr('Marked as being reviewed.')),
                child: Text(tr('Mark as being reviewed')),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: busy ? null : issue,
              icon: const Icon(Icons.upload_file),
              label: Text(tr('Upload attestation (PDF) and issue')),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy ? null : reject,
              style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
              child: Text(tr('Reject with a note')),
            ),
          ],
          if (isClosed && r['attestation_path'] != null)
            OutlinedButton.icon(
              onPressed: () =>
                  openPrivateFile(context, 'attestations', r['attestation_path']),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(tr('Open issued attestation')),
            ),
          if (isClosed && hasPassport) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: busy ? null : deletePassport,
              style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
              icon: const Icon(Icons.delete_forever),
              label: Text(tr('Delete passport scan now')),
            ),
            Text(
              tr('Otherwise it is deleted automatically 30 days after the attestation is issued.'),
              style: const TextStyle(fontSize: 12, color: kMutedText),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------- D1. Students list (staff: all, rep: own wilaya) ----------------

class StudentsScreen extends StatefulWidget {
  final MyRole role;
  const StudentsScreen({super.key, required this.role});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Map<String, dynamic>> students = [];
  bool loading = true;
  String? wilaya;
  String? year;

  @override
  void initState() {
    super.initState();
    // A rep always sees their own wilaya (the database enforces it too).
    if (!widget.role.isStaff) wilaya = widget.role.repWilaya;
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      var query = supabase.from('student_records').select();
      if (wilaya != null) query = query.eq('wilaya', wilaya!);
      if (year != null) query = query.eq('academic_year', year!);
      final data = await query.order('last_name').order('first_name');
      if (!mounted) return;
      setState(() {
        students = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Students'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: widget.role.isStaff
                      ? WilayaDropdown(
                          value: wilaya,
                          allowAll: true,
                          onChanged: (v) {
                            setState(() => wilaya = v);
                            load();
                          },
                        )
                      : InputDecorator(
                          decoration: InputDecoration(labelText: tr('Wilaya')),
                          child: Text(wilaya ?? ''),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: year,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Academic year')),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null, child: Text(tr('All years'))),
                      for (final y in academicYearChoices())
                        DropdownMenuItem<String?>(value: y, child: Text(y)),
                    ],
                    onChanged: (v) {
                      setState(() => year = v);
                      load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('{count} students', {'count': students.length}),
                      style: const TextStyle(color: kMutedText)),
                ),
                TextButton.icon(
                  onPressed: wilaya == null || year == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CompileResultsScreen(
                                wilaya: wilaya!, academicYear: year!),
                          )),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(wilaya == null || year == null
                      ? tr('Choose wilaya and year to compile')
                      : tr('Compile results PDF')),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : students.isEmpty
                    ? Center(child: Text(tr('No students.')))
                    : RefreshIndicator(
                        onRefresh: load,
                        child: ListView.builder(
                          itemCount: students.length,
                          itemBuilder: (context, i) {
                            final s = students[i];
                            return ListTile(
                              title: Text(studentName(s)),
                              subtitle: Text(
                                  '${s['wilaya']} · ${s['academic_year']} · ${tr('${s['level']}')}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        StudentDetailScreen(record: s)),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class StudentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> record;
  const StudentDetailScreen({super.key, required this.record});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  List<Map<String, dynamic>> results = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('academic_results')
          .select('id, academic_year, semester, file_name, uploaded_at')
          .eq('user_id', widget.record['user_id'])
          .order('academic_year', ascending: false)
          .order('semester');
      if (!mounted) return;
      setState(() {
        results = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.record;
    Widget row(String label, dynamic value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: Text(label, style: const TextStyle(color: kMutedText))),
              Expanded(child: Text('${value ?? ''}')),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(studentName(s))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          row(tr('Inscription number'), s['inscription_number']),
          row(tr('Program'), s['program']),
          row(tr('Level'), tr('${s['level']}')),
          row(tr('Current academic year'), s['academic_year']),
          row(tr('Start year'), s['start_year']),
          row(tr('Expected finish year'), s['expected_finish_year']),
          row(tr('Wilaya'), s['wilaya']),
          row(tr('Phone'), s['phone']),
          if ((s['phone'] ?? '').toString().isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ContactActions(phone: '${s['phone']}'),
            ),
          const Divider(height: 32),
          Text(tr('Results'), style: Theme.of(context).textTheme.titleMedium),
          Text(tr('Opening a file is recorded in the access log.'),
              style: const TextStyle(fontSize: 12, color: kMutedText)),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('No results uploaded yet.')),
            )
          else
            for (final r in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(
                    '${r['academic_year']} · ${tr(kSemesters[r['semester']] ?? '${r['semester']}')}'),
                subtitle: Text('${r['file_name']} · ${shortDate(r['uploaded_at'])}'),
                onTap: () => openStaffDocument(context, 'RESULTS', r['id']),
              ),
        ],
      ),
    );
  }
}

// ---------------- D2. Compile one wilaya into PDF parts ----------------

class CompileResultsScreen extends StatefulWidget {
  final String wilaya;
  final String academicYear;
  const CompileResultsScreen(
      {super.key, required this.wilaya, required this.academicYear});

  @override
  State<CompileResultsScreen> createState() => _CompileResultsScreenState();
}

class _CompileResultsScreenState extends State<CompileResultsScreen> {
  // part number -> link (valid 1 hour)
  final Map<int, String> links = {};
  int? totalParts;
  int? studentCount;
  int? building;
  String? error;

  Future<void> buildPart(int part) async {
    setState(() {
      building = part;
      error = null;
    });
    try {
      final res = await callFunction('staff-reports', {
        'action': 'compile',
        'wilaya': widget.wilaya,
        'academic_year': widget.academicYear,
        'part': part,
      });
      if (!mounted) return;
      setState(() {
        links[part] = res['url'] as String;
        totalParts = res['total_parts'] as int?;
        studentCount = res['students'] as int?;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => building = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = totalParts;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Compile results'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${widget.wilaya} · ${widget.academicYear}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(tr(
              'The PDF has a cover page with the list of students, then each student\'s results. Big wilayas are split into several parts. Each link works for 1 hour.')),
          if (studentCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('{count} students, {parts} part(s).',
                  {'count': studentCount, 'parts': total})),
            ),
          const SizedBox(height: 16),
          for (var p = 1; p <= (total ?? 1); p++)
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(tr('Part {n}', {'n': p})),
                subtitle: Text(links[p] != null
                    ? tr('Ready. Tap Open.')
                    : building == p
                        ? tr('Building... this can take a minute.')
                        : tr('Not built yet')),
                trailing: links[p] != null
                    ? TextButton(
                        onPressed: () => openLink(context, links[p]!),
                        child: Text(tr('Open')),
                      )
                    : TextButton(
                        onPressed: building != null ? null : () => buildPart(p),
                        child: Text(tr('Build')),
                      ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Could not build: {error}', {'error': error}),
                  style: const TextStyle(color: AppColors.cancelled)),
            ),
        ],
      ),
    );
  }
}

// ---------------- D3. Final list of all students (attache, admin) ----------------

class FinalListScreen extends StatefulWidget {
  const FinalListScreen({super.key});

  @override
  State<FinalListScreen> createState() => _FinalListScreenState();
}

class _FinalListScreenState extends State<FinalListScreen> {
  String? building;
  String? wilaya; // null = all wilayas
  bool includeBank = false;

  Future<void> export(String format) async {
    if (includeBank &&
        !await confirmDialog(
            context,
            tr('This export contains bank account numbers. It will be recorded in the access log. Continue?'),
            okLabel: tr('Export'))) {
      return;
    }
    setState(() => building = format);
    try {
      final res = await callFunction('staff-reports', {
        'action': 'final_list',
        'format': format,
        'wilaya': wilaya,
        'include_bank': includeBank,
      });
      if (mounted) await openLink(context, res['url'] as String);
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not build: {error}', {'error': friendlyError(e, short: true)}));
    } finally {
      if (mounted) setState(() => building = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Final list of students'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr(
              'Students sorted by wilaya and name. Columns: number, last name, first name, inscription number, wilaya, program, level, academic year, start year, expected finish year, phone, and the bank account if you choose it. The link works for 1 hour.')),
          const SizedBox(height: 16),
          WilayaDropdown(
            value: wilaya,
            allowAll: true,
            onChanged: (v) => setState(() => wilaya = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Include the bank account column')),
            subtitle: Text(tr('Recorded in the access log.')),
            value: includeBank,
            onChanged: (v) => setState(() => includeBank = v),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: building != null ? null : () => export('pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(building == 'pdf' ? tr('Building...') : tr('Export as PDF')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: building != null ? null : () => export('csv'),
            icon: const Icon(Icons.grid_on),
            label: Text(building == 'csv' ? tr('Building...') : tr('Export as CSV (Excel)')),
          ),
        ],
      ),
    );
  }
}

// ---------------- D4. Access log (attache, admin) ----------------

const Map<String, String> kLogKinds = {
  'RESULTS_OPENED': 'Opened results',
  'PASSPORT_OPENED': 'Opened passport',
  'PASSPORT_DELETED': 'Deleted passport',
  'RESULTS_COMPILED': 'Compiled results',
  'FINAL_LIST_EXPORTED': 'Exported final list',
  'FINAL_LIST_EXPORTED_WITH_BANK': 'Exported final list with bank accounts',
  'STUDENT_DETAILS_VIEWED': 'Opened student details (bank, passport number)',
  'BANK_ACCOUNT_VIEWED': 'Opened a bank account',
  'BANK_LIST_VIEWED': 'Opened the bank account list',
  'RESULTS_TRACKER_VIEWED': 'Opened the results tracker',
};

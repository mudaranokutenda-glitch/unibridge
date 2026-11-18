import 'package:flutter/material.dart';
import 'config.dart';
import 'app_theme.dart';
import 'roles.dart';
import 'staff.dart';
import 'student_info.dart';
import 'student_space.dart';
import 'wilayas.dart';
import 'l10n.dart';

// ---------------- Educational Attaché and Governor tools ----------------
// Every check is done in the database (sql/2026-11-11-13 and -14) or in the
// Edge Functions. These screens only show what the server allows.

// ---------------- 26. Search students (attache, admin) ----------------

class StaffSearchScreen extends StatefulWidget {
  const StaffSearchScreen({super.key});
  @override
  State<StaffSearchScreen> createState() => _StaffSearchScreenState();
}

class _StaffSearchScreenState extends State<StaffSearchScreen> {
  final query = TextEditingController();
  String? wilaya;
  List<Map<String, dynamic>> results = [];
  bool searching = false;
  bool searched = false;

  Future<void> search() async {
    final q = query.text.trim();
    if (q.length < 2 && wilaya == null) {
      showSnack(context, tr('Type at least 2 letters or choose a wilaya.'));
      return;
    }
    setState(() => searching = true);
    try {
      final data = await supabase.rpc('staff_search_students',
          params: {'p_query': q, 'p_wilaya': wilaya});
      if (!mounted) return;
      setState(() {
        results = List<Map<String, dynamic>>.from(data as List);
        searched = true;
      });
    } catch (e) {
      if (mounted) showSnack(context, tr('Error: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  String nameOf(Map<String, dynamic> s) {
    final last = (s['last_name'] ?? '').toString();
    if (last.isNotEmpty) return '$last ${s['first_name'] ?? ''}';
    final full = (s['full_name'] ?? '').toString();
    return full.isEmpty ? tr('UniBridge user') : full;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Search students'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: tr('Name or inscription number'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: WilayaDropdown(
              value: wilaya,
              allowAll: true,
              onChanged: (v) => setState(() => wilaya = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: searching ? null : search,
              icon: const Icon(Icons.search),
              label: Text(searching ? tr('Searching...') : tr('Search')),
            ),
          ),
          Expanded(
            child: !searched
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        tr('Search by name, inscription number or wilaya. At most 50 results.'),
                        textAlign: TextAlign.center),
                  ))
                : results.isEmpty
                    ? Center(child: Text(tr('Nothing found.')))
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final s = results[i];
                          return ListTile(
                            title: Text(nameOf(s)),
                            subtitle: Text([
                              '${s['wilaya'] ?? ''}',
                              if (s['inscription_number'] != null)
                                '${s['inscription_number']}',
                              if (s['has_record'] != true) tr('No student record'),
                            ].join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => StaffStudentScreen(
                                    userId: s['user_id'].toString()))),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// One student's details (attache, admin). Opening it is logged.
class StaffStudentScreen extends StatefulWidget {
  final String userId;
  const StaffStudentScreen({super.key, required this.userId});
  @override
  State<StaffStudentScreen> createState() => _StaffStudentScreenState();
}

class _StaffStudentScreenState extends State<StaffStudentScreen> {
  Map<String, dynamic>? data;
  List<Map<String, dynamic>> results = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await supabase
          .rpc('staff_student_details', params: {'p_user': widget.userId});
      final r = await supabase
          .from('academic_results')
          .select('id, academic_year, semester, file_name, uploaded_at')
          .eq('user_id', widget.userId)
          .order('academic_year', ascending: false)
          .order('semester');
      if (!mounted) return;
      setState(() {
        data = Map<String, dynamic>.from(d as Map);
        results = List<Map<String, dynamic>>.from(r);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Widget row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 150,
                child: Text(label, style: const TextStyle(color: kMutedText))),
            Expanded(child: SelectableText('${value ?? '—'}')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final rec = d?['record'] is Map ? Map<String, dynamic>.from(d!['record']) : null;
    final phone = d?['phone'] ?? rec?['phone'];
    String gender(dynamic g) =>
        g == 'MALE' ? tr('Male') : (g == 'FEMALE' ? tr('Female') : '—');
    return Scaffold(
      appBar: AppBar(
          title: Text(rec != null ? studentName(rec) : '${d?['full_name'] ?? ''}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? Center(child: Text(tr('Student not found')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(tr('Opening this page is recorded in the access log.'),
                        style: const TextStyle(fontSize: 12, color: kMutedText)),
                    const SizedBox(height: 8),
                    Text(tr('Contact'), style: Theme.of(context).textTheme.titleMedium),
                    row(tr('Name'), d['full_name']),
                    row(tr('Phone'), phone),
                    if (phone != null) ContactActions(phone: '$phone'),
                    const Divider(height: 24),
                    Text(tr('Student record'), style: Theme.of(context).textTheme.titleMedium),
                    if (rec == null)
                      Text(tr('No student record'))
                    else ...[
                      row(tr('Gender'), gender(rec['gender'])),
                      row(tr('Inscription number'), rec['inscription_number']),
                      row(tr('Program'), rec['program']),
                      row(tr('Level'), tr('${rec['level']}')),
                      row(tr('Current academic year'), rec['academic_year']),
                      row(tr('Start year'), rec['start_year']),
                      row(tr('Expected finish year'), rec['expected_finish_year']),
                      row(tr('Wilaya'), rec['wilaya']),
                    ],
                    const Divider(height: 24),
                    Text(tr('Private information'),
                        style: Theme.of(context).textTheme.titleMedium),
                    row(tr('Bank account'), d['bank_account']),
                    row(tr('Passport number'), d['passport_number']),
                    const Divider(height: 24),
                    Text(tr('Results'), style: Theme.of(context).textTheme.titleMedium),
                    Text(tr('Opening a file is recorded in the access log.'),
                        style: const TextStyle(fontSize: 12, color: kMutedText)),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(tr('No results uploaded yet.')),
                      ),
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

// ---------------- 30 / 35. Dashboard: students per wilaya ----------------

class StudentsDashboardScreen extends StatefulWidget {
  const StudentsDashboardScreen({super.key});
  @override
  State<StudentsDashboardScreen> createState() => _StudentsDashboardScreenState();
}

class _StudentsDashboardScreenState extends State<StudentsDashboardScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase.rpc('students_per_wilaya');
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  int n(dynamic v) => int.tryParse('$v') ?? 0;

  // A summary card with a big number.
  Widget bigNumber(String label, int value, {Color? color, bool large = false}) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xs),
          Text('$value',
              style: TextStyle(
                  fontSize: large ? 44 : 32, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  // One wilaya: its name, a horizontal bar and the number of students.
  // The solid part of the bar = students with a record, the pale part = without.
  Widget wilayaBar(Map<String, dynamic> r, int biggest) {
    final scheme = Theme.of(context).colorScheme;
    final students = n(r['students']);
    final withRecord = n(r['with_record']).clamp(0, students);
    final whole = biggest == 0 ? 0.0 : students / biggest;
    final solid = biggest == 0 ? 0.0 : withRecord / biggest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r['wilaya']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('$students',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(
                  height: 12,
                  width: box.maxWidth,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Container(
                  height: 12,
                  width: box.maxWidth * whole,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Container(
                  height: 12,
                  width: box.maxWidth * solid,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget legendDot(Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<int>(0, (a, r) => a + n(r['students']));
    final withRecord = rows.fold<int>(0, (a, r) => a + n(r['with_record']));
    final without = total - withRecord;
    final scheme = Theme.of(context).colorScheme;
    // Biggest wilaya first. A Governor gets only their own wilaya from the database.
    final sorted = [...rows]..sort((a, b) => n(b['students']).compareTo(n(a['students'])));
    final biggest = sorted.isEmpty ? 0 : n(sorted.first['students']);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Dashboard'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.screen, AppSpace.s, AppSpace.screen, AppSpace.xxl),
                children: [
                  bigNumber(tr('Total students'), total, large: true),
                  const SizedBox(height: AppSpace.m),
                  Row(
                    children: [
                      Expanded(
                          child: bigNumber(tr('With a record'), withRecord,
                              color: AppColors.success)),
                      const SizedBox(width: AppSpace.m),
                      Expanded(
                          child: bigNumber(tr('Without a record'), without,
                              color: AppColors.warning)),
                    ],
                  ),
                  const SizedBox(height: AppSpace.l),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpace.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Students per wilaya'),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: AppSpace.s),
                        Wrap(
                          spacing: AppSpace.l,
                          children: [
                            legendDot(scheme.primary, tr('With a record')),
                            legendDot(scheme.primary.withValues(alpha: 0.3),
                                tr('Without a record')),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s),
                        if (sorted.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
                            child: Center(child: Text(tr('No students.'))),
                          ),
                        for (final r in sorted) wilayaBar(r, biggest),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------- 29. Emergency alert (attache, admin) ----------------

class EmergencyAlertScreen extends StatefulWidget {
  const EmergencyAlertScreen({super.key});
  @override
  State<EmergencyAlertScreen> createState() => _EmergencyAlertScreenState();
}

class _EmergencyAlertScreenState extends State<EmergencyAlertScreen> {
  final title = TextEditingController();
  final message = TextEditingController();
  bool sending = false;

  // test: true sends only to my own phone (nothing is saved, no dialog).
  Future<void> send({bool test = false}) async {
    final t = title.text.trim();
    final m = message.text.trim();
    if (t.isEmpty || m.isEmpty) {
      showSnack(context, tr('Write a title and a message.'));
      return;
    }
    if (test) {
      setState(() => sending = true);
      try {
        final res = await callFunction(
            'emergency-alert', {'title': t, 'message': m, 'test': true});
        if (!mounted) return;
        showSnack(
            context,
            (res['sent'] ?? 0) == 1
                ? tr('Test sent to your phone only.')
                : tr('The test could not be sent to your phone.'));
      } catch (e) {
        if (mounted) showSnack(context, tr('Could not send: {error}', {'error': e}));
      } finally {
        if (mounted) setState(() => sending = false);
      }
      return;
    }
    final ok = await confirmDialog(
      context,
      tr('Send this emergency alert to EVERY user now? Their phones will ring with the alarm sound.'),
      okLabel: tr('Send to everyone'),
    );
    if (!ok) return;
    setState(() => sending = true);
    try {
      final res = await callFunction('emergency-alert', {'title': t, 'message': m});
      if (!mounted) return;
      if (res['ok'] == false) {
        // Some phones were not reached: show the warning from the server.
        showSnack(context, '${res['warning'] ?? tr('The alert was not sent to every phone.')}');
      } else {
        showSnack(context, tr('Alert sent to {count} phones.', {'count': res['sent'] ?? 0}));
      }
      title.clear();
      message.clear();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not send: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Emergency alert'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr('Use this only for real emergencies. The alert goes to every user as a high-priority notification and is saved in the app.'),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            maxLength: 100,
            decoration: InputDecoration(labelText: tr('Title')),
          ),
          TextField(
            controller: message,
            maxLength: 1000,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(labelText: tr('Message'), alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: sending ? null : () => send(),
            icon: const Icon(Icons.campaign_outlined),
            label: Text(sending ? tr('Sending...') : tr('Send to everyone')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: sending ? null : () => send(test: true),
            icon: const Icon(Icons.phone_android_outlined),
            label: Text(tr('Send a test to myself')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
            icon: const Icon(Icons.history),
            label: Text(tr('Past alerts')),
          ),
        ],
      ),
    );
  }
}

// Everyone: the list of alerts.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> alerts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('alerts')
          .select('id, title, message, created_at')
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        alerts = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Alerts'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : alerts.isEmpty
              ? Center(child: Text(tr('No alerts.')))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    children: [
                      for (final a in alerts)
                        ListTile(
                          leading: Icon(Icons.campaign_outlined, color: scheme.error),
                          title: Text('${a['title']}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${a['message']}\n${dateTimeText(a['created_at'])}'),
                          isThreeLine: true,
                        ),
                    ],
                  ),
                ),
    );
  }
}

// The newest alert of the last 3 days, shown at the top of the home screen.
Future<Map<String, dynamic>?> loadRecentAlert() async {
  try {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 3));
    final rows = await supabase
        .from('alerts')
        .select('id, title, message, created_at')
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  } catch (e) {
    debugPrint('Could not load alerts: $e');
    return null;
  }
}

class AlertBanner extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onClose;
  const AlertBanner({super.key, required this.alert, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${alert['title']}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
                    Text('${alert['message']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onErrorContainer)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: scheme.onErrorContainer),
                tooltip: tr('Hide'),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- 31. Governor: results tracker ----------------

class ResultsTrackerScreen extends StatefulWidget {
  const ResultsTrackerScreen({super.key});
  @override
  State<ResultsTrackerScreen> createState() => _ResultsTrackerScreenState();
}

class _ResultsTrackerScreenState extends State<ResultsTrackerScreen> {
  String year = currentAcademicYear();
  String semester = 'S1';
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final data = await supabase.rpc('rep_results_tracker',
          params: {'p_year': year, 'p_semester': semester});
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = rows.where((r) => r['has_uploaded'] == true).length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Results tracker'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: year,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Academic year')),
                    items: [
                      for (final y in academicYearChoices())
                        DropdownMenuItem(value: y, child: Text(y)),
                    ],
                    onChanged: (v) {
                      setState(() => year = v ?? year);
                      load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: semester,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Semester')),
                    items: [
                      for (final e in kSemesters.entries)
                        DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
                    ],
                    onChanged: (v) {
                      setState(() => semester = v ?? semester);
                      load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('{done} of {total} have uploaded their results',
                {'done': done, 'total': rows.length})),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(child: Text(tr('No students.')))
                    : ListView(
                        children: [
                          for (final r in rows)
                            ListTile(
                              leading: Icon(
                                r['has_uploaded'] == true
                                    ? Icons.check_circle
                                    : Icons.cancel_outlined,
                                color: r['has_uploaded'] == true
                                    ? AppColors.success
                                    : scheme.error,
                              ),
                              title: Text('${r['last_name']} ${r['first_name']}'),
                              subtitle: Text(r['has_uploaded'] == true
                                  ? tr('Uploaded on {date}',
                                      {'date': shortDate(r['uploaded_at'])})
                                  : tr('Not uploaded yet')),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 32. Governor: users without a student record ----------------

class MissingRecordsScreen extends StatefulWidget {
  const MissingRecordsScreen({super.key});
  @override
  State<MissingRecordsScreen> createState() => _MissingRecordsScreenState();
}

class _MissingRecordsScreenState extends State<MissingRecordsScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase.rpc('rep_students_without_record');
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('No student record yet'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(child: Text(tr('Everyone has filled in their student record.')))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(tr('{count} users of your wilaya have not filled in their student record.',
                            {'count': rows.length})),
                      ),
                      for (final r in rows)
                        ListTile(
                          title: Text('${r['full_name'] ?? tr('UniBridge user')}'),
                          subtitle: Text('${r['phone'] ?? tr('No phone number')}'),
                          trailing: r['phone'] == null
                              ? null
                              : ContactActions(phone: '${r['phone']}'),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ---------------- 34. Governor: bank accounts (view only, logged) ----------------

class GovernorBankAccountsScreen extends StatefulWidget {
  const GovernorBankAccountsScreen({super.key});
  @override
  State<GovernorBankAccountsScreen> createState() =>
      _GovernorBankAccountsScreenState();
}

class _GovernorBankAccountsScreenState extends State<GovernorBankAccountsScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase.rpc('rep_bank_accounts');
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bank accounts'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      tr('View only. Opening this list is recorded in the access log.'),
                      style: const TextStyle(fontSize: 12, color: kMutedText)),
                ),
                if (rows.isEmpty) Center(child: Text(tr('No students.'))),
                for (final r in rows)
                  ListTile(
                    title: Text('${r['last_name']} ${r['first_name']}'),
                    subtitle: SelectableText(
                        '${r['account_number'] ?? tr('Not given yet')}'),
                  ),
              ],
            ),
    );
  }
}

// ---------------- Buttons in the Profile tab ----------------

class StaffToolsSection extends StatelessWidget {
  final MyRole role;
  const StaffToolsSection({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    Widget button(IconData icon, String label, Widget screen) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: () => open(screen),
            icon: Icon(icon),
            label: Text(label),
          ),
        );

    if (role.isStaff) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button(Icons.person_search_outlined, tr('Search students'),
              const StaffSearchScreen()),
          button(Icons.bar_chart_outlined, tr('Dashboard'),
              const StudentsDashboardScreen()),
          button(Icons.event_outlined, tr('Appointments'),
              const StaffAppointmentsScreen()),
          button(Icons.contact_phone_outlined, tr('Governors\' contacts'),
              const ManageContactsScreen(onlyKind: 'governor')),
          button(Icons.edit_note_outlined, tr('Manage contacts'),
              const ManageContactsScreen()),
          button(Icons.campaign_outlined, tr('Emergency alert'),
              const EmergencyAlertScreen()),
        ],
      );
    }
    if (role.isRep) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button(Icons.bar_chart_outlined, tr('Dashboard'),
              const StudentsDashboardScreen()),
          button(Icons.fact_check_outlined, tr('Results tracker'),
              const ResultsTrackerScreen()),
          button(Icons.assignment_late_outlined, tr('No student record yet'),
              const MissingRecordsScreen()),
          button(Icons.account_balance_outlined, tr('Bank accounts'),
              const GovernorBankAccountsScreen()),
          button(Icons.support_agent_outlined, tr('Contact the Educational Attaché'),
              const ContactsScreen()),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}


// ---------------- Recent access (attaché, admin) ----------------
// The last 100 rows of the access log, read ONLY through the SQL function
// recent_access (it checks is_staff()). It never returns a phone, a bank
// account or a passport number.

class RecentAccessScreen extends StatefulWidget {
  const RecentAccessScreen({super.key});

  @override
  State<RecentAccessScreen> createState() => _RecentAccessScreenState();
}

class _RecentAccessScreenState extends State<RecentAccessScreen> {
  final person = TextEditingController();
  String? kind; // null = all kinds
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? errorText;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    person.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final text = person.text.trim();
      final data = await supabase.rpc('recent_access', params: {
        'p_person': text.isEmpty ? null : text,
        'p_kind': kind,
      });
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorText = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = person.text.trim().isNotEmpty || kind != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Recent access'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: person,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                labelText: tr('Person (name)'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: person.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          person.clear();
                          load();
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<String?>(
              initialValue: kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('What')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('All'))),
                for (final e in kLogKinds.entries)
                  DropdownMenuItem<String?>(
                      value: e.key,
                      child: Text(tr(e.value), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                kind = v;
                load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('The last 100 rows, newest first.'),
                  style: const TextStyle(fontSize: 12, color: kMutedText)),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : errorText != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              tr('Could not load: {error}', {'error': errorText!}),
                              textAlign: TextAlign.center),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: load,
                        child: rows.isEmpty
                            ? ListView(children: [
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                      child: Text(filtered
                                          ? tr('No matching rows.')
                                          : tr('Nothing recorded yet.'))),
                                ),
                              ])
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final r = rows[i];
                                  final role = '${r['actor_role']}';
                                  final who = role == 'system'
                                      ? tr('Automatic cleanup')
                                      : (r['actor_name'] ?? '').toString().isEmpty
                                          ? tr('UniBridge user')
                                          : '${r['actor_name']}';
                                  final student = r['student_id'] == null
                                      ? ''
                                      : ' · ${(r['student_name'] ?? '').toString().isEmpty ? tr('deleted account') : r['student_name']}';
                                  final label = kLogKinds['${r['kind']}'];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                        '${label == null ? r['kind'] : tr(label)}$student'),
                                    subtitle: Text(
                                        '$who ($role) · ${dateTimeText(r['created_at'])}'
                                        '${r['wilaya'] == null ? '' : ' · ${r['wilaya']}'}'),
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

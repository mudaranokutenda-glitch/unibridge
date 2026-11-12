import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'consent.dart';
import 'wilayas.dart';
import 'profile_setup.dart';
import 'l10n.dart';

// ---------------- Student space: record, results, attestation ----------------
// Security is in sql/2026-11-05-04-student-space.sql and 05-attestations.sql.
// A student only ever sees their own record and files here.

const int kMaxDocumentBytes = 10 * 1024 * 1024;

const List<String> kStudyLevels = [
  'Preparatory / language year',
  'Licence 1',
  'Licence 2',
  'Licence 3',
  'Master 1',
  'Master 2',
  'Engineering',
  'Doctorate',
  'Other',
];

const Map<String, String> kSemesters = {
  'S1': 'Semester 1',
  'S2': 'Semester 2',
  'ANNUAL': 'Whole year',
};

void showSnack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String shortDate(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

// Opens a file from a private bucket with a short link (10 minutes).
Future<void> openPrivateFile(
    BuildContext context, String bucket, String path) async {
  try {
    final url = await supabase.storage.from(bucket).createSignedUrl(path, 600);
    if (!context.mounted) return;
    await openLink(context, url);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, tr('Could not open the file: {error}', {'error': e}));
    }
  }
}

Future<void> openLink(BuildContext context, String url) async {
  final ok =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showSnack(context, tr('Could not open the file.'));
}

String contentTypeFor(String ext) {
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    default:
      return 'image/jpeg';
  }
}

class StudentSpaceScreen extends StatefulWidget {
  const StudentSpaceScreen({super.key});

  @override
  State<StudentSpaceScreen> createState() => _StudentSpaceScreenState();
}

class _StudentSpaceScreenState extends State<StudentSpaceScreen> {
  DateTime? consentDate;

  @override
  void initState() {
    super.initState();
    loadConsent();
  }

  Future<void> loadConsent() async {
    try {
      final d = await myConsentDate();
      if (mounted) setState(() => consentDate = d);
    } catch (e) {
      debugPrint('Could not load consent: $e');
    }
  }

  void open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    loadConsent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Student space'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(tr('My student record')),
            subtitle: Text(tr('Program, level, year, wilaya')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const StudentRecordScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr('My results')),
            subtitle: Text(tr('Upload your results (PDF)')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const MyResultsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(tr('Attestation de bourse')),
            subtitle: Text(tr('Ask for it and download it')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const AttestationScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Who can see my documents')),
            subtitle: Text(consentDate == null
                ? tr('You will be asked before your first upload.')
                : tr('You agreed on {date}.',
                    {'date': shortDate(consentDate!.toIso8601String())})),
            onTap: () => open(const ConsentScreen()),
          ),
        ],
      ),
    );
  }
}

// ---------------- B1. My student record ----------------

class StudentRecordScreen extends StatefulWidget {
  const StudentRecordScreen({super.key});

  @override
  State<StudentRecordScreen> createState() => _StudentRecordScreenState();
}

class _StudentRecordScreenState extends State<StudentRecordScreen> {
  final formKey = GlobalKey<FormState>();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final program = TextEditingController();
  final phone = TextEditingController();
  final inscription = TextEditingController();
  String? level;
  String? wilaya;
  String? academicYear;
  int? startYear;
  int? finishYear;
  bool loading = true;
  bool saving = false;
  bool exists = false;

  List<int> get years {
    final now = DateTime.now().year;
    return [for (var y = now + 8; y >= now - 15; y--) y];
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await supabase
          .from('student_records')
          .select()
          .eq('user_id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        if (r != null) {
          exists = true;
          firstName.text = '${r['first_name'] ?? ''}';
          lastName.text = '${r['last_name'] ?? ''}';
          program.text = '${r['program'] ?? ''}';
          phone.text = '${r['phone'] ?? ''}'.replaceAll(' ', '');
          inscription.text = '${r['inscription_number'] ?? ''}';
          level = kStudyLevels.contains(r['level']) ? r['level'] : null;
          wilaya = validWilaya(r['wilaya']);
          academicYear = r['academic_year']?.toString();
          startYear = r['start_year'] as int?;
          finishYear = r['expected_finish_year'] as int?;
        }
        loading = false;
      });
      // No phone in the record yet: start with the one from my profile.
      if (phone.text.isEmpty) {
        final p = await loadMyPhone();
        if (p != null && mounted) setState(() => phone.text = p);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await supabase.from('student_records').upsert({
        'user_id': supabase.auth.currentUser!.id,
        'first_name': firstName.text.trim(),
        'last_name': lastName.text.trim(),
        'program': program.text.trim(),
        'level': level,
        'start_year': startYear,
        'academic_year': academicYear,
        'phone': phone.text.trim(),
        'wilaya': wilaya,
        'inscription_number': inscription.text.trim(),
        'expected_finish_year': finishYear,
      });
      exists = true;
      if (mounted) showSnack(context, tr('Record saved.'));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not save: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String? required(String? v) =>
      (v == null || v.trim().isEmpty) ? tr('Required') : null;

  Widget text(TextEditingController c, String label,
      {TextInputType? keyboard, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: validator ?? required,
      ),
    );
  }

  Widget dropdown<T>(String label, T? value, List<T> items,
      ValueChanged<T?> onChanged, {String Function(T)? show}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final i in items)
            DropdownMenuItem<T>(
                value: i, child: Text(show == null ? '$i' : show(i))),
        ],
        onChanged: onChanged,
        validator: (v) => v == null ? tr('Required') : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('My student record'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    tr('Only you, the Educational Attaché and the Governor of your wilaya can see this. Other students never see your inscription number or phone.'),
                    style: const TextStyle(fontSize: 12, color: kMutedText),
                  ),
                  const SizedBox(height: 12),
                  text(firstName, tr('First name')),
                  text(lastName, tr('Last name')),
                  text(program, tr('Program (e.g. Civil engineering)')),
                  dropdown<String>(tr('Level'), level, kStudyLevels,
                      (v) => setState(() => level = v),
                      show: (v) => tr(v)),
                  dropdown<int>(tr('Start year'), startYear, years,
                      (v) => setState(() => startYear = v)),
                  dropdown<String>(tr('Current academic year'), academicYear,
                      academicYearChoices(),
                      (v) => setState(() => academicYear = v)),
                  dropdown<int>(tr('Expected finish year'), finishYear, years,
                      (v) => setState(() => finishYear = v)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: wilaya,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Wilaya')),
                      items: [
                        for (final w in kWilayas)
                          DropdownMenuItem(value: w, child: Text(w)),
                      ],
                      onChanged: (v) => setState(() => wilaya = v),
                      validator: (v) => v == null ? tr('Required') : null,
                    ),
                  ),
                  text(phone, tr('Phone (e.g. +213555123456)'),
                      keyboard: TextInputType.phone,
                      validator: (v) => isValidPhone(v)
                          ? null
                          : tr('Use +213 or +263 followed by 8 to 10 digits.')),
                  text(inscription, tr('Inscription number')),
                  if (startYear != null &&
                      finishYear != null &&
                      finishYear! < startYear!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                          tr('The finish year cannot be before the start year.'),
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ElevatedButton(
                    onPressed: saving ||
                            (startYear != null &&
                                finishYear != null &&
                                finishYear! < startYear!)
                        ? null
                        : save,
                    child: Text(saving
                        ? tr('Saving...')
                        : exists
                            ? tr('Save changes')
                            : tr('Save my record')),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------- B2. My results ----------------

class MyResultsScreen extends StatefulWidget {
  const MyResultsScreen({super.key});

  @override
  State<MyResultsScreen> createState() => _MyResultsScreenState();
}

class _MyResultsScreenState extends State<MyResultsScreen> {
  List<Map<String, dynamic>> results = [];
  bool loading = true;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('academic_results')
          .select()
          .eq('user_id', supabase.auth.currentUser!.id)
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
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  // Asks for the year and semester, then the PDF.
  Future<void> upload() async {
    if (!await ensureDocumentConsent(context)) return;
    if (!mounted) return;

    String year = currentAcademicYear();
    String semester = 'S1';
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('Upload results')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: year,
                decoration: InputDecoration(labelText: tr('Academic year')),
                items: [
                  for (final y in academicYearChoices())
                    DropdownMenuItem(value: y, child: Text(y)),
                ],
                onChanged: (v) => setDialogState(() => year = v ?? year),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: semester,
                decoration: InputDecoration(labelText: tr('Semester')),
                items: [
                  for (final e in kSemesters.entries)
                    DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
                ],
                onChanged: (v) =>
                    setDialogState(() => semester = v ?? semester),
              ),
              const SizedBox(height: 12),
              Text(tr('PDF only, max 10 MB.'),
                  style: const TextStyle(fontSize: 12, color: kMutedText)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Choose PDF')),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null || !mounted) return;
    if ((file.extension ?? '').toLowerCase() != 'pdf') {
      showSnack(context, tr('Please choose a PDF file.'));
      return;
    }
    final size = await file.length() ?? 0;
    if (size > kMaxDocumentBytes) {
      if (mounted) showSnack(context, tr('This file is too big (max 10 MB).'));
      return;
    }

    setState(() => uploading = true);
    final myId = supabase.auth.currentUser!.id;
    final path = '$myId/$year/${DateTime.now().millisecondsSinceEpoch}.pdf';
    try {
      final bytes = await file.readAsBytes();
      await supabase.storage.from('academic-results').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      try {
        await supabase.from('academic_results').insert({
          'user_id': myId,
          'academic_year': year,
          'semester': semester,
          'file_path': path,
          'file_name': file.name.length > 200 ? file.name.substring(0, 200) : file.name,
          'size_bytes': bytes.length,
        });
      } catch (e) {
        // Do not leave a file without its row.
        await supabase.storage.from('academic-results').remove([path]);
        rethrow;
      }
      await load();
      if (mounted) showSnack(context, tr('Results uploaded.'));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not upload: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this file?')),
        content: Text('${r['file_name']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.storage.from('academic-results').remove([r['file_path']]);
      await supabase.from('academic_results').delete().eq('id', r['id']);
      await load();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('My results'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploading ? null : upload,
        icon: uploading
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: Text(uploading ? tr('Uploading...') : tr('Upload results')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : results.isEmpty
              ? Center(child: Text(tr('No results uploaded yet.')))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final r = results[i];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                          '${r['academic_year']} · ${tr(kSemesters[r['semester']] ?? '${r['semester']}')}'),
                      subtitle: Text('${r['file_name']} · ${shortDate(r['uploaded_at'])}'),
                      onTap: () => openPrivateFile(
                          context, 'academic-results', r['file_path']),
                      trailing: IconButton(
                        tooltip: tr('Delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => delete(r),
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------------- C1. Attestation de bourse (student side) ----------------

const Map<String, String> kAttestationStatus = {
  'PENDING': 'Sent, waiting',
  'IN_REVIEW': 'Being reviewed',
  'ISSUED': 'Issued',
  'REJECTED': 'Not accepted',
};

Color attestationColor(String? status) {
  switch (status) {
    case 'ISSUED':
      return Colors.green;
    case 'REJECTED':
      return Colors.red;
    case 'IN_REVIEW':
      return Colors.blue;
    default:
      return Colors.orange;
  }
}

class AttestationScreen extends StatefulWidget {
  const AttestationScreen({super.key});

  @override
  State<AttestationScreen> createState() => _AttestationScreenState();
}

class _AttestationScreenState extends State<AttestationScreen> {
  List<Map<String, dynamic>> requests = [];
  bool loading = true;
  bool sending = false;

  bool get hasOpenRequest => requests
      .any((r) => r['status'] == 'PENDING' || r['status'] == 'IN_REVIEW');

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('attestation_requests')
          .select()
          .eq('user_id', supabase.auth.currentUser!.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        requests = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> ask() async {
    if (!await ensureDocumentConsent(context)) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (file == null || !mounted) return;
    final ext = (file.extension ?? '').toLowerCase().replaceAll('jpeg', 'jpg');
    if (!['jpg', 'png', 'pdf'].contains(ext)) {
      showSnack(context, tr('Please choose a photo (JPG, PNG) or a PDF.'));
      return;
    }
    final size = await file.length() ?? 0;
    if (size > kMaxDocumentBytes) {
      if (mounted) showSnack(context, tr('This file is too big (max 10 MB).'));
      return;
    }

    setState(() => sending = true);
    final myId = supabase.auth.currentUser!.id;
    final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await supabase.storage.from('passports').uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(contentType: contentTypeFor(ext)),
          );
      await supabase.from('attestation_requests').insert({
        'user_id': myId,
        'passport_path': path,
      });
      await load();
      if (mounted) showSnack(context, tr('Request sent.'));
    } catch (e) {
      // If only the upload worked, the scan stays in the student's private
      // folder (only they can see it) until they delete their account.
      if (mounted) showSnack(context, tr('Could not send: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Attestation de bourse'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(tr(
                      'Send a clear scan or photo of your passport (photo page). The educational attaché checks it and issues your attestation here. Your passport scan is deleted after the attestation is issued.')),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: sending || hasOpenRequest ? null : ask,
                    icon: const Icon(Icons.upload_file),
                    label: Text(sending
                        ? tr('Sending...')
                        : hasOpenRequest
                            ? tr('You already have a request in progress')
                            : tr('Ask for an attestation')),
                  ),
                  const SizedBox(height: 16),
                  for (final r in requests)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle,
                                    size: 12,
                                    color: attestationColor(r['status'])),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr(kAttestationStatus[r['status']] ??
                                        '${r['status']}'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(shortDate(r['created_at']),
                                    style: const TextStyle(
                                        fontSize: 12, color: kMutedText)),
                              ],
                            ),
                            if ((r['note'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(tr('Note: {note}', {'note': r['note']})),
                            ],
                            if (r['status'] == 'ISSUED' &&
                                r['attestation_path'] != null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () => openPrivateFile(context,
                                    'attestations', r['attestation_path']),
                                icon: const Icon(Icons.download),
                                label: Text(tr('Download my attestation')),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

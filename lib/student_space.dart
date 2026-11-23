import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'app_theme.dart';
import 'profiles.dart';
import 'staff.dart';
import 'consent.dart';
import 'members.dart';
import 'staff_tools.dart';
import 'roles.dart';
import 'wilayas.dart';
import 'profile_setup.dart';
import 'student_info.dart';
import 'l10n.dart';
import 'errors.dart';
import 'notifications.dart';

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
      showSnack(context, tr('Could not open the file: {error}', {'error': friendlyError(e, short: true)}));
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
  MyRole role = MyRole.student;
  Map<String, dynamic>? me; // my public profile (name and photo for the header)
  String? attestationStatus; // status of my latest attestation request

  @override
  void initState() {
    super.initState();
    loadConsent();
    loadMyRole().then((r) {
      if (mounted) setState(() => role = r);
    });
    loadHeader();
  }

  // The header (name, photo) and the attestation status shown on its card.
  Future<void> loadHeader() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    final profiles = await fetchPublicProfiles([myId]);
    String? status;
    try {
      final rows = await supabase
          .from('attestation_requests')
          .select('status')
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(1);
      if ((rows as List).isNotEmpty) status = '${rows.first['status']}';
    } catch (e) {
      debugPrint('Could not load the attestation status: $e');
    }
    if (!mounted) return;
    setState(() {
      me = profiles[myId];
      attestationStatus = status;
    });
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
    loadHeader();
  }

  @override
  Widget build(BuildContext context) {
    // Only approved members (and staff) see the Student space; the others see
    // the "Join the student space" screen (lib/members.dart).
    return MembershipGate(child: _spaceHome());
  }

  // ---- The home of the Student space: a header and large rounded cards ----

  String roleLabel() {
    if (role.isStaff) {
      return role.role == 'admin' ? tr('Administrator') : tr('Educational Attaché');
    }
    if (role.isRep) return tr('Governor of {wilaya}', {'wilaya': role.repWilaya});
    return tr('Student');
  }

  Widget header() {
    final scheme = Theme.of(context).colorScheme;
    final name = me == null ? '' : publicDisplayName(me!);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.l),
      child: Row(
        children: [
          avatar(me, radius: 32),
          const SizedBox(width: AppSpace.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? tr('AZSA user') : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  roleLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // One large card: a round coloured icon, a title and a short line.
  Widget spaceCard(IconData icon, String title, String? subtitle, Widget screen,
      {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => open(screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconCircle(icon: icon, size: 46, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget cardGrid(List<Widget> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.m,
        crossAxisSpacing: AppSpace.m,
        mainAxisExtent: 156,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => cards[i],
    );
  }

  Widget sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xl, 0, AppSpace.s),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _spaceHome() {
    const violet = Color(0xFF8E6CF2);
    const teal = Color(0xFF00A3BF);
    final attestationLine = attestationStatus == null
        ? tr('Ask for it and download it')
        : tr(kAttestationStatus[attestationStatus] ?? attestationStatus!);

    // Extra cards for staff and Governors (the same screens as in the Profile tab).
    // Hiding a card is not the security: the database checks the role again.
    final extra = <Widget>[
      if (role.canSeeStudents)
        spaceCard(Icons.how_to_reg_outlined, tr('Join requests'),
            tr('Approve new members of the student space'), const JoinRequestsScreen(),
            color: AppColors.success),
      if (role.isStaff)
        spaceCard(Icons.person_search_outlined, tr('Search students'), null,
            const StaffSearchScreen()),
      if (role.isRep)
        spaceCard(Icons.groups_outlined, tr('Students'), null,
            StudentsScreen(role: role)),
      if (role.isStaff)
        spaceCard(Icons.table_chart_outlined, tr('Final list of students'), null,
            const FinalListScreen(),
            color: teal),
      if (role.canSeeStudents)
        spaceCard(Icons.bar_chart_outlined, tr('Dashboard'), null,
            const StudentsDashboardScreen(),
            color: violet),
      if (role.isRep)
        spaceCard(Icons.fact_check_outlined, tr('Results tracker'), null,
            const ResultsTrackerScreen(),
            color: teal),
      if (role.isStaff)
        spaceCard(Icons.history, tr('Recent access'),
            tr('Who opened student information'), const RecentAccessScreen(),
            color: AppColors.warning),
      if (role.isStaff)
        spaceCard(Icons.campaign_outlined, tr('Emergency alert'), null,
            const EmergencyAlertScreen(),
            color: AppColors.cancelled),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Student space')),
        actions: const [NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await loadHeader();
          await loadConsent();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.screen, AppSpace.s, AppSpace.screen, AppSpace.xxl),
          children: [
            header(),
            const SizedBox(height: AppSpace.l),
            cardGrid([
              spaceCard(Icons.badge_outlined, tr('My student record'),
                  tr('Program, level, year, wilaya'), const StudentRecordScreen()),
              spaceCard(Icons.description_outlined, tr('My results'),
                  tr('Upload your results (PDF)'), const MyResultsScreen(),
                  color: AppColors.success),
              spaceCard(Icons.workspace_premium_outlined, tr('Attestation de bourse'),
                  attestationLine, const AttestationScreen(),
                  color: AppColors.verified),
              spaceCard(Icons.event_outlined, tr('Appointments'),
                  tr('Meet the Educational Attaché'), const AppointmentsScreen(),
                  color: violet),
              spaceCard(Icons.contact_phone_outlined, tr('Contacts'),
                  tr('The Educational Attaché and your Governor'),
                  const ContactsScreen(),
                  color: teal),
              spaceCard(Icons.menu_book_outlined, tr('Guide for new students'),
                  tr('Police, bank, bourse, medical'), const GuideScreen(),
                  color: AppColors.warning),
              spaceCard(Icons.help_outline, tr('Help'),
                  tr('Frequently asked questions'), const HelpScreen()),
            ]),
            if (extra.isNotEmpty) ...[
              sectionTitle(tr('Staff tools')),
              cardGrid(extra),
            ],
            const SizedBox(height: AppSpace.l),
            AppCard(
              onTap: () => open(const ConsentScreen()),
              child: Row(
                children: [
                  const IconCircle(icon: Icons.privacy_tip_outlined, size: 40),
                  const SizedBox(width: AppSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Who can see my documents'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          consentDate == null
                              ? tr('You will be asked before your first upload.')
                              : tr('You agreed on {date}.', {
                                  'date': shortDate(consentDate!.toIso8601String())
                                }),
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
        ),
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
  // Private: only me, the Educational Attaché and my Governor (bank account);
  // only me and the Educational Attaché (passport number). Separate tables.
  final bankAccount = TextEditingController();
  final passportNumber = TextEditingController();
  String? gender; // MALE or FEMALE
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
          gender = const ['MALE', 'FEMALE'].contains(r['gender'])
              ? r['gender']
              : null;
        }
        loading = false;
      });
      final me = supabase.auth.currentUser!.id;
      final bank = await supabase
          .from('bank_accounts')
          .select('account_number')
          .eq('user_id', me)
          .maybeSingle();
      final passport = await supabase
          .from('passport_numbers')
          .select('passport_number')
          .eq('user_id', me)
          .maybeSingle();
      if (mounted) {
        setState(() {
          bankAccount.text = '${bank?['account_number'] ?? ''}';
          passportNumber.text = '${passport?['passport_number'] ?? ''}';
        });
      }
      // No phone in the record yet: start with the one from my profile.
      if (phone.text.isEmpty) {
        final p = await loadMyPhone();
        if (p != null && mounted) setState(() => phone.text = p);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    if (!isNewPhoneFormat(phone.text)) {
      showSnack(context, tr('Choose +213 or +263 and enter the 9 digits.'));
      return;
    }
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
        'gender': gender,
      });
      final me = supabase.auth.currentUser!.id;
      await supabase.from('bank_accounts').upsert({
        'user_id': me,
        'account_number': bankAccount.text.trim(),
      });
      await supabase.from('passport_numbers').upsert({
        'user_id': me,
        'passport_number': passportNumber.text.trim().toUpperCase(),
      });
      exists = true;
      if (mounted) showSnack(context, tr('Record saved.'));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not save: {error}', {'error': friendlyError(e, short: true)}));
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
                // Extra space at the bottom so "Save my record" is not hidden
                // behind the phone's navigation buttons.
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Text(
                    tr('Only you, the Educational Attaché and the Governor of your wilaya can see this. Other students never see your inscription number or phone.'),
                    style: const TextStyle(fontSize: 12, color: kMutedText),
                  ),
                  const SizedBox(height: 12),
                  text(firstName, tr('First name')),
                  text(lastName, tr('Last name')),
                  dropdown<String>(tr('Gender'), gender, const ['MALE', 'FEMALE'],
                      (v) => setState(() => gender = v),
                      show: (v) => v == 'MALE' ? tr('Male') : tr('Female')),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PhoneField(
                      controller: phone,
                      label: tr('Phone'),
                      helper: tr('9 digits, without the first 0.'),
                    ),
                  ),
                  text(inscription, tr('Inscription number')),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: bankAccount,
                      keyboardType: TextInputType.number,
                      maxLength: 20, // shows the 0/20 counter
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: InputDecoration(
                        labelText: tr('Bank account number (20 digits)'),
                        helperText: tr(
                            'Only the Educational Attaché and your Governor can see your bank account number.'),
                        helperMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => RegExp(r'^[0-9]{20}$').hasMatch(v ?? '')
                          ? null
                          : tr('Exactly 20 digits'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: passportNumber,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(12),
                        TextInputFormatter.withFunction((oldValue, newValue) =>
                            newValue.copyWith(text: newValue.text.toUpperCase())),
                      ],
                      decoration: InputDecoration(
                        labelText: tr('Passport number'),
                        helperText: tr(
                            'Only you and the Educational Attaché can see your passport number.'),
                        helperMaxLines: 3,
                      ),
                      validator: (v) =>
                          RegExp(r'^[A-Z0-9]{6,12}$').hasMatch((v ?? '').toUpperCase())
                              ? null
                              : tr('6 to 12 letters and digits'),
                    ),
                  ),
                  if (startYear != null &&
                      finishYear != null &&
                      finishYear! < startYear!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                          tr('The finish year cannot be before the start year.'),
                          style: const TextStyle(color: AppColors.cancelled)),
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
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
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
      if (mounted) showSnack(context, tr('Could not upload: {error}', {'error': friendlyError(e, short: true)}));
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
            style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
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
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': friendlyError(e, short: true)}));
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
      return AppColors.success;
    case 'REJECTED':
      return AppColors.cancelled;
    case 'IN_REVIEW':
      return AppColors.sky;
    default:
      return AppColors.warning;
  }
}

// Progress of one attestation request: Received, In review, Issued (or Rejected).
// A step shows its date when the database has one (a step can be done without a date,
// for older requests or when staff skipped "In review").
class AttestationTracker extends StatelessWidget {
  final Map<String, dynamic> request;
  const AttestationTracker({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final status = '${request['status']}';
    final rejected = status == 'REJECTED';
    final reviewDone =
        status == 'IN_REVIEW' || status == 'ISSUED' || status == 'REJECTED';
    final finalDone = status == 'ISSUED' || rejected;

    Widget step(String label, bool done, dynamic date,
        {bool current = false, bool bad = false}) {
      final color = bad
          ? AppColors.cancelled
          : done
              ? AppColors.success
              : current
                  ? AppColors.warning
                  : kMutedText;
      final icon = bad
          ? Icons.cancel
          : done
              ? Icons.check_circle
              : current
                  ? Icons.timelapse
                  : Icons.radio_button_unchecked;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: done || current ? FontWeight.w600 : null,
                      color: done || current ? null : kMutedText)),
            ),
            Text(shortDate(date),
                style: const TextStyle(fontSize: 12, color: kMutedText)),
          ],
        ),
      );
    }

    return Column(
      children: [
        step(tr('Received'), true, request['created_at']),
        step(tr('In review'), reviewDone, request['reviewed_at'],
            current: status == 'PENDING'),
        if (rejected)
          step(tr('Rejected'), true, request['rejected_at'], bad: true)
        else
          step(tr('Issued'), finalDone, request['issued_at']),
      ],
    );
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
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  Future<void> ask() async {
    if (!await ensureDocumentConsent(context)) return;
    if (!mounted) return;
    // 1. The date of entry into Algeria (required).
    final now = DateTime.now();
    final entry = await showDatePicker(
      context: context,
      helpText: tr('Date of entry into Algeria'),
      initialDate: now,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (entry == null || !mounted) {
      if (mounted) {
        showSnack(context, tr('The date of entry into Algeria is required.'));
      }
      return;
    }
    // 2. The passport scan (required).
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
      String two(int n) => n.toString().padLeft(2, '0');
      await supabase.from('attestation_requests').insert({
        'user_id': myId,
        'passport_path': path,
        'entry_date': '${entry.year}-${two(entry.month)}-${two(entry.day)}',
      });
      await load();
      if (mounted) showSnack(context, tr('Request sent.'));
    } catch (e) {
      // If only the upload worked, the scan stays in the student's private
      // folder (only they can see it) until they delete their account.
      if (mounted) showSnack(context, tr('Could not send: {error}', {'error': friendlyError(e, short: true)}));
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
                      'You need two things: the date you entered Algeria, and a clear scan or photo of your passport (photo page). The Educational Attaché checks it and issues your attestation here. Your passport scan is deleted after the attestation is issued.')),
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
                            AttestationTracker(request: r),
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

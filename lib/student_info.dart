import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'profiles.dart';
import 'profile_setup.dart';
import 'roles.dart';
import 'student_space.dart';
import 'wilayas.dart';
import 'l10n.dart';

// ---------------- Student space: contacts, guide, help, appointments --------
// Security is in sql/2026-11-11-09 (contacts), -10 (guide, help) and
// -11 (appointments). Staff = Educational Attaché (attache) and admin.

String dateTimeText(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

// Asks for a date, then a time. Returns null if cancelled.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(days: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: const TimeOfDay(hour: 10, minute: 0),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<void> launchOrSay(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showSnack(context, tr('Could not open it.'));
}

// Call, WhatsApp and email buttons for one contact.
class ContactActions extends StatelessWidget {
  final String? phone;
  final String? email;
  const ContactActions({super.key, this.phone, this.email});

  @override
  Widget build(BuildContext context) {
    final p = (phone ?? '').trim();
    final e = (email ?? '').trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p.isNotEmpty) ...[
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: tr('Call'),
            onPressed: () => launchOrSay(context, Uri(scheme: 'tel', path: p)),
          ),
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            tooltip: 'WhatsApp',
            onPressed: () => launchOrSay(context,
                Uri.parse('https://wa.me/${p.replaceAll(RegExp(r'[^0-9]'), '')}')),
          ),
        ],
        if (e.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: tr('Email'),
            onPressed: () => launchOrSay(context, Uri(scheme: 'mailto', path: e)),
          ),
      ],
    );
  }
}

// ---------------- 21. Contacts ----------------

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> contacts = [];
  String? myWilaya;
  MyRole role = MyRole.student;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('staff_contacts')
          .select()
          .order('sort_order')
          .order('name');
      final w = await supabase.rpc('student_wilaya',
          params: {'p_user': supabase.auth.currentUser!.id});
      final r = await loadMyRole();
      if (!mounted) return;
      setState(() {
        contacts = List<Map<String, dynamic>>.from(data);
        myWilaya = w?.toString();
        role = r;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Widget contactTile(Map<String, dynamic> c) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text('${c['name']}'),
        subtitle: Text([
          if (c['wilaya'] != null) '${c['wilaya']}',
          if (c['phone'] != null) '${c['phone']}',
          if (c['email'] != null) '${c['email']}',
        ].join('\n')),
        isThreeLine: c['phone'] != null && c['email'] != null,
        trailing: ContactActions(phone: c['phone'], email: c['email']),
      );

  @override
  Widget build(BuildContext context) {
    final attache = contacts.where((c) => c['kind'] == 'attache').toList();
    final governors = contacts
        .where((c) => c['kind'] == 'governor' && c['wilaya'] == myWilaya)
        .toList();
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Contacts')),
        actions: [
          if (role.isStaff)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: tr('Manage contacts'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ManageContactsScreen()));
                load();
              },
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                children: [
                  ListTile(
                    title: Text(tr('Contact the Educational Attaché'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (attache.isEmpty)
                    ListTile(title: Text(tr('No contact yet.'), style: muted)),
                  for (final c in attache) contactTile(c),
                  const Divider(),
                  ListTile(
                    title: Text(tr('Contact your Governor'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: myWilaya == null ? null : Text(myWilaya!),
                  ),
                  if (myWilaya == null)
                    ListTile(
                        title: Text(tr('Choose your wilaya in your profile first.'),
                            style: muted))
                  else if (governors.isEmpty)
                    ListTile(title: Text(tr('No contact yet.'), style: muted)),
                  for (final c in governors) contactTile(c),
                ],
              ),
            ),
    );
  }
}

// Staff (attache, admin): add, change and delete contacts.
class ManageContactsScreen extends StatefulWidget {
  final String? onlyKind; // 'governor' = list of Governors only
  const ManageContactsScreen({super.key, this.onlyKind});
  @override
  State<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends State<ManageContactsScreen> {
  List<Map<String, dynamic>> contacts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      var q = supabase.from('staff_contacts').select();
      if (widget.onlyKind != null) q = q.eq('kind', widget.onlyKind!);
      final data = await q.order('kind').order('wilaya').order('sort_order');
      if (!mounted) return;
      setState(() {
        contacts = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> edit([Map<String, dynamic>? c]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ContactEditDialog(contact: c),
    );
    if (saved == true) load();
  }

  Future<void> delete(Map<String, dynamic> c) async {
    final ok = await confirmDialog(context, tr('Delete this contact?'));
    if (!ok) return;
    try {
      await supabase.from('staff_contacts').delete().eq('id', c['id']);
      load();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.onlyKind == 'governor'
              ? tr('Governors\' contacts')
              : tr('Manage contacts'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        tooltip: tr('Add a contact'),
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : contacts.isEmpty
              ? Center(child: Text(tr('No contact yet.')))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final c in contacts)
                      ListTile(
                        title: Text('${c['name']}'),
                        subtitle: Text([
                          c['kind'] == 'attache'
                              ? tr('Educational Attaché')
                              : '${tr('Governor')} · ${c['wilaya']}',
                          if (c['phone'] != null) '${c['phone']}',
                          if (c['email'] != null) '${c['email']}',
                        ].join('\n')),
                        isThreeLine: true,
                        onTap: () => edit(c),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ContactActions(phone: c['phone'], email: c['email']),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: tr('Delete'),
                              onPressed: () => delete(c),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String question,
    {String? okLabel}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel'))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(okLabel ?? tr('Delete'))),
      ],
    ),
  );
  return ok == true;
}

class ContactEditDialog extends StatefulWidget {
  final Map<String, dynamic>? contact;
  const ContactEditDialog({super.key, this.contact});
  @override
  State<ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<ContactEditDialog> {
  late String kind = widget.contact?['kind'] ?? 'governor';
  late String? wilaya = validWilaya(widget.contact?['wilaya']);
  late final name = TextEditingController(text: widget.contact?['name'] ?? '');
  late final phone = TextEditingController(text: widget.contact?['phone'] ?? '');
  late final email = TextEditingController(text: widget.contact?['email'] ?? '');
  late final order =
      TextEditingController(text: '${widget.contact?['sort_order'] ?? 0}');
  bool saving = false;
  String? error;

  Future<void> save() async {
    final p = phone.text.trim();
    final e = email.text.trim();
    if (name.text.trim().isEmpty) {
      setState(() => error = tr('Write a name.'));
      return;
    }
    if (kind == 'governor' && wilaya == null) {
      setState(() => error = tr('Choose the wilaya.'));
      return;
    }
    if (p.isEmpty && e.isEmpty) {
      setState(() => error = tr('Give a phone number or an email.'));
      return;
    }
    if (p.isNotEmpty && !isNewPhoneFormat(p)) {
      setState(() => error = tr('Choose +213 or +263 and enter the 9 digits.'));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final row = {
      'kind': kind,
      'name': name.text.trim(),
      'wilaya': kind == 'governor' ? wilaya : null,
      'phone': p.isEmpty ? null : p,
      'email': e.isEmpty ? null : e,
      'sort_order': int.tryParse(order.text.trim()) ?? 0,
    };
    try {
      if (widget.contact == null) {
        await supabase.from('staff_contacts').insert(row);
      } else {
        await supabase.from('staff_contacts').update(row).eq('id', widget.contact!['id']);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() {
          saving = false;
          error = tr('Could not save: {error}', {'error': err});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.contact == null ? tr('Add a contact') : tr('Edit contact')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: InputDecoration(labelText: tr('Kind')),
              items: [
                DropdownMenuItem(value: 'attache', child: Text(tr('Educational Attaché'))),
                DropdownMenuItem(value: 'governor', child: Text(tr('Governor'))),
              ],
              onChanged: (v) => setState(() => kind = v ?? kind),
            ),
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            if (kind == 'governor')
              WilayaDropdown(value: wilaya, onChanged: (v) => setState(() => wilaya = v)),
            PhoneField(
              controller: phone,
              label: tr('Phone'),
              helper: tr('9 digits, without the first 0.'),
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('Email')),
            ),
            TextField(
              controller: order,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Order')),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel'))),
        FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? tr('Saving...') : tr('Save'))),
      ],
    );
  }
}

// ---------------- 22. Guide for new students ----------------

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  List<Map<String, dynamic>> sections = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('guide_sections')
          .select('id, title, sort_order, guide_items(count)')
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        sections = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  int countOf(Map<String, dynamic> s) {
    final c = s['guide_items'];
    if (c is List && c.isNotEmpty && c.first is Map) {
      return int.tryParse('${c.first['count']}') ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Guide for new students'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                children: [
                  for (final s in sections)
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(tr('${s['title']}')),
                      subtitle: Text(countOf(s) == 0
                          ? tr('Coming soon')
                          : tr('{count} items', {'count': countOf(s)})),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GuideSectionScreen(section: s)));
                        load();
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

class GuideSectionScreen extends StatefulWidget {
  final Map<String, dynamic> section;
  const GuideSectionScreen({super.key, required this.section});
  @override
  State<GuideSectionScreen> createState() => _GuideSectionScreenState();
}

class _GuideSectionScreenState extends State<GuideSectionScreen> {
  List<Map<String, dynamic>> items = [];
  MyRole role = MyRole.student;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('guide_items')
          .select()
          .eq('section_id', widget.section['id'])
          .order('sort_order')
          .order('title');
      final r = await loadMyRole();
      if (!mounted) return;
      setState(() {
        items = List<Map<String, dynamic>>.from(data);
        role = r;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> edit([Map<String, dynamic>? item]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GuideItemEditScreen(
            sectionId: widget.section['id'].toString(), item: item)));
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('${widget.section['title']}'))),
      floatingActionButton: role.isStaff
          ? FloatingActionButton(
              onPressed: () => edit(),
              tooltip: tr('Add'),
              child: const Icon(Icons.add),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(child: Text(tr('Coming soon')))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final i in items)
                      ExpansionTile(
                        title: Text('${i['title']}'),
                        childrenPadding:
                            const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('${i['body'] ?? ''}'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (i['pdf_path'] != null)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  label: Text(tr('Open the PDF')),
                                  onPressed: () => openGuidePdf(
                                      context, i['pdf_path'].toString()),
                                ),
                              if (role.isStaff)
                                TextButton.icon(
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(tr('Edit')),
                                  onPressed: () => edit(i),
                                ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}

// Guide PDFs: private bucket, link valid 1 hour.
Future<void> openGuidePdf(BuildContext context, String path) async {
  try {
    final url = await supabase.storage.from('guide').createSignedUrl(path, 3600);
    if (context.mounted) await openLink(context, url);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, tr('Could not open the file: {error}', {'error': e}));
    }
  }
}

class GuideItemEditScreen extends StatefulWidget {
  final String sectionId;
  final Map<String, dynamic>? item;
  const GuideItemEditScreen({super.key, required this.sectionId, this.item});
  @override
  State<GuideItemEditScreen> createState() => _GuideItemEditScreenState();
}

class _GuideItemEditScreenState extends State<GuideItemEditScreen> {
  late final title = TextEditingController(text: widget.item?['title'] ?? '');
  late final body = TextEditingController(text: widget.item?['body'] ?? '');
  late final order = TextEditingController(text: '${widget.item?['sort_order'] ?? 0}');
  late String? pdfPath = widget.item?['pdf_path'];
  PlatformFile? newPdf;
  bool removePdf = false;
  bool saving = false;

  Future<void> choosePdf() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (f == null || !mounted) return;
    if ((f.extension ?? '').toLowerCase() != 'pdf') {
      showSnack(context, tr('Please choose a PDF file.'));
      return;
    }
    if ((await f.length() ?? 0) > kMaxDocumentBytes) {
      if (mounted) showSnack(context, tr('This file is too big (max 10 MB).'));
      return;
    }
    setState(() {
      newPdf = f;
      removePdf = false;
    });
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      showSnack(context, tr('Write a title.'));
      return;
    }
    setState(() => saving = true);
    final storage = supabase.storage.from('guide');
    try {
      String? path = removePdf ? null : pdfPath;
      if (newPdf != null) {
        path = '${_uuid()}.pdf';
        await storage.uploadBinary(path, await newPdf!.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'application/pdf'));
      }
      final row = {
        'section_id': widget.sectionId,
        'title': title.text.trim(),
        'body': body.text.trim(),
        'sort_order': int.tryParse(order.text.trim()) ?? 0,
        'pdf_path': path,
      };
      if (widget.item == null) {
        await supabase.from('guide_items').insert(row);
      } else {
        await supabase.from('guide_items').update(row).eq('id', widget.item!['id']);
      }
      // The old file is no longer used: delete it.
      if (pdfPath != null && pdfPath != path) {
        await storage.remove([pdfPath!]);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not save: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> delete() async {
    if (!await confirmDialog(context, tr('Delete this item?'))) return;
    try {
      await supabase.from('guide_items').delete().eq('id', widget.item!['id']);
      if (pdfPath != null) await supabase.storage.from('guide').remove([pdfPath!]);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = newPdf != null || (pdfPath != null && !removePdf);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? tr('Add') : tr('Edit')),
        actions: [
          if (widget.item != null)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: tr('Delete'),
                onPressed: saving ? null : delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: title, decoration: InputDecoration(labelText: tr('Title'))),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 5,
            maxLines: 15,
            decoration: InputDecoration(labelText: tr('Text'), alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: order,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Order')),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(newPdf != null
                ? newPdf!.name
                : hasPdf
                    ? tr('PDF attached')
                    : tr('No PDF (optional)')),
            trailing: Wrap(children: [
              TextButton(onPressed: saving ? null : choosePdf, child: Text(tr('Choose PDF'))),
              if (hasPdf)
                TextButton(
                  onPressed: saving
                      ? null
                      : () => setState(() {
                            newPdf = null;
                            removePdf = true;
                          }),
                  child: Text(tr('Remove')),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? tr('Saving...') : tr('Save')),
          ),
        ],
      ),
    );
  }
}

// A random id (UUID v4) for file names, with no extra package.
String _uuid() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ---------------- 23. Help (frequently asked questions) ----------------

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  List<Map<String, dynamic>> faqs = [];
  MyRole role = MyRole.student;
  bool loading = true;
  String search = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase.from('faqs').select().order('sort_order').order('question');
      final r = await loadMyRole();
      if (!mounted) return;
      setState(() {
        faqs = List<Map<String, dynamic>>.from(data);
        role = r;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> edit([Map<String, dynamic>? f]) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => FaqEditDialog(faq: f));
    if (saved == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final visible = q.isEmpty
        ? faqs
        : faqs
            .where((f) =>
                '${f['question']} ${f['answer']}'.toLowerCase().contains(q))
            .toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Help'))),
      floatingActionButton: role.isStaff
          ? FloatingActionButton(
              onPressed: () => edit(),
              tooltip: tr('Add'),
              child: const Icon(Icons.add),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('Search the questions'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(faqs.isEmpty
                              ? tr('No questions yet.')
                              : tr('Nothing found.')))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          children: [
                            for (final f in visible)
                              ExpansionTile(
                                title: Text('${f['question']}'),
                                childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                                    16, 0, 16, 12),
                                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText('${f['answer']}'),
                                  if (role.isStaff)
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_outlined),
                                      label: Text(tr('Edit')),
                                      onPressed: () => edit(f),
                                    ),
                                ],
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class FaqEditDialog extends StatefulWidget {
  final Map<String, dynamic>? faq;
  const FaqEditDialog({super.key, this.faq});
  @override
  State<FaqEditDialog> createState() => _FaqEditDialogState();
}

class _FaqEditDialogState extends State<FaqEditDialog> {
  late final question = TextEditingController(text: widget.faq?['question'] ?? '');
  late final answer = TextEditingController(text: widget.faq?['answer'] ?? '');
  late final order = TextEditingController(text: '${widget.faq?['sort_order'] ?? 0}');
  bool saving = false;

  Future<void> save() async {
    if (question.text.trim().isEmpty || answer.text.trim().isEmpty) {
      showSnack(context, tr('Write the question and the answer.'));
      return;
    }
    setState(() => saving = true);
    final row = {
      'question': question.text.trim(),
      'answer': answer.text.trim(),
      'sort_order': int.tryParse(order.text.trim()) ?? 0,
    };
    try {
      if (widget.faq == null) {
        await supabase.from('faqs').insert(row);
      } else {
        await supabase.from('faqs').update(row).eq('id', widget.faq!['id']);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showSnack(context, tr('Could not save: {error}', {'error': e}));
      }
    }
  }

  Future<void> delete() async {
    if (!await confirmDialog(context, tr('Delete this question?'))) return;
    try {
      await supabase.from('faqs').delete().eq('id', widget.faq!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': e}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.faq == null ? tr('Add') : tr('Edit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: question, decoration: InputDecoration(labelText: tr('Question'))),
            TextField(
              controller: answer,
              minLines: 3,
              maxLines: 10,
              decoration: InputDecoration(labelText: tr('Answer')),
            ),
            TextField(
              controller: order,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Order')),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.faq != null)
          TextButton(onPressed: saving ? null : delete, child: Text(tr('Delete'))),
        TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel'))),
        FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? tr('Saving...') : tr('Save'))),
      ],
    );
  }
}

// ---------------- 24. Appointments with the Educational Attaché ----------------

String appointmentStatusLabel(String? s) {
  switch (s) {
    case 'REQUESTED':
      return tr('Waiting for an answer');
    case 'ACCEPTED':
      return tr('Confirmed');
    case 'PROPOSED':
      return tr('Another time proposed');
    case 'DECLINED':
      return tr('Declined');
    case 'CANCELLED':
      return tr('Cancelled');
    default:
      return '$s';
  }
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('appointments')
          .select()
          .eq('student_id', supabase.auth.currentUser!.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        items = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> ask() async {
    final when = await pickDateTime(context);
    if (when == null || !mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Ask for an appointment')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateTimeText(when.toIso8601String())),
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(labelText: tr('Reason')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Send'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (reason.text.trim().length < 3) {
      showSnack(context, tr('Write the reason (at least 3 letters).'));
      return;
    }
    setState(() => busy = true);
    try {
      await supabase.from('appointments').insert({
        'student_id': supabase.auth.currentUser!.id,
        'requested_at': when.toUtc().toIso8601String(),
        'reason': reason.text.trim(),
      });
      if (mounted) showSnack(context, tr('Request sent to the Educational Attaché.'));
      load();
    } on PostgrestException catch (e) {
      // Messages written by the database (for example the limit of 3
      // appointments) are shown as they are.
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not send: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> answer(String id, String action) async {
    setState(() => busy = true);
    try {
      await supabase.rpc('student_answer_appointment',
          params: {'p_id': id, 'p_action': action});
      load();
    } catch (e) {
      if (mounted) showSnack(context, tr('Error: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Appointments'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : ask,
        icon: const Icon(Icons.event_available_outlined),
        label: Text(tr('Ask for an appointment')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Ask the Educational Attaché for an appointment: choose a date, a time and the reason.'),
                      textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final a in items)
                        Card(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(appointmentStatusLabel(a['status']),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: a['status'] == 'DECLINED' ||
                                                a['status'] == 'CANCELLED'
                                            ? scheme.error
                                            : null)),
                                const SizedBox(height: 4),
                                Text(tr('Asked for: {date}',
                                    {'date': dateTimeText(a['requested_at'])})),
                                if (a['proposed_at'] != null)
                                  Text(tr('Proposed: {date}',
                                      {'date': dateTimeText(a['proposed_at'])})),
                                Text('${a['reason']}',
                                    style: TextStyle(color: scheme.onSurfaceVariant)),
                                if (a['staff_note'] != null)
                                  Text(tr('Note: {note}', {'note': a['staff_note']})),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (['REQUESTED', 'PROPOSED', 'ACCEPTED']
                                        .contains(a['status']))
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                if (await confirmDialog(context,
                                                    tr('Cancel this appointment?'),
                                                    okLabel: tr('Cancel appointment'))) {
                                                  answer(a['id'], 'CANCEL');
                                                }
                                              },
                                        child: Text(tr('Cancel appointment')),
                                      ),
                                    if (a['status'] == 'PROPOSED')
                                      FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => answer(a['id'], 'ACCEPT_PROPOSAL'),
                                        child: Text(tr('Accept this time')),
                                      ),
                                  ],
                                ),
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

// Staff: answer appointment requests.
class StaffAppointmentsScreen extends StatefulWidget {
  const StaffAppointmentsScreen({super.key});
  @override
  State<StaffAppointmentsScreen> createState() => _StaffAppointmentsScreenState();
}

class _StaffAppointmentsScreenState extends State<StaffAppointmentsScreen> {
  List<Map<String, dynamic>> items = [];
  Map<String, String> names = {};
  bool onlyOpen = true;
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      var q = supabase.from('appointments').select();
      if (onlyOpen) q = q.inFilter('status', ['REQUESTED', 'PROPOSED', 'ACCEPTED']);
      final data = await q.order('requested_at');
      final list = List<Map<String, dynamic>>.from(data);
      final ids = list.map((a) => a['student_id'].toString()).toSet().toList();
      final found = <String, String>{};
      if (ids.isNotEmpty) {
        final recs = await supabase
            .from('student_records')
            .select('user_id, first_name, last_name')
            .inFilter('user_id', ids);
        for (final r in recs) {
          found[r['user_id'].toString()] = '${r['last_name']} ${r['first_name']}';
        }
        final missing = ids.where((i) => !found.containsKey(i));
        final profiles = await fetchPublicProfiles(missing);
        profiles.forEach((k, v) => found[k] = publicDisplayName(v));
      }
      if (!mounted) return;
      setState(() {
        items = list;
        names = found;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': e}));
    }
  }

  Future<void> act(Map<String, dynamic> a, String action) async {
    DateTime? time;
    String? note;
    if (action == 'PROPOSE') {
      time = await pickDateTime(context);
      if (time == null) return;
    }
    if (!mounted) return;
    if (action != 'ACCEPT') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action == 'DECLINE' ? tr('Decline') : tr('Propose another time')),
          content: TextField(
            controller: c,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: action == 'DECLINE'
                    ? tr('Note for the student')
                    : tr('Note for the student (optional)')),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr('Cancel'))),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr('Send'))),
          ],
        ),
      );
      if (ok != true) return;
      note = c.text.trim();
    }
    setState(() => busy = true);
    try {
      await supabase.rpc('staff_answer_appointment', params: {
        'p_id': a['id'],
        'p_action': action,
        'p_time': time?.toUtc().toIso8601String(),
        'p_note': note,
      });
      load();
    } catch (e) {
      if (mounted) showSnack(context, tr('Error: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Appointments'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                children: [
                  SwitchListTile(
                    title: Text(tr('Only open appointments')),
                    value: onlyOpen,
                    onChanged: (v) {
                      setState(() => onlyOpen = v);
                      load();
                    },
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(tr('No appointments.'))),
                    ),
                  for (final a in items)
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(names[a['student_id'].toString()] ?? tr('UniBridge user'),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(appointmentStatusLabel(a['status'])),
                            Text(tr('Asked for: {date}',
                                {'date': dateTimeText(a['requested_at'])})),
                            if (a['proposed_at'] != null)
                              Text(tr('Proposed: {date}',
                                  {'date': dateTimeText(a['proposed_at'])})),
                            Text('${a['reason']}', style: muted),
                            if (['REQUESTED', 'PROPOSED'].contains(a['status']))
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                children: [
                                  TextButton(
                                      onPressed: busy ? null : () => act(a, 'DECLINE'),
                                      child: Text(tr('Decline'))),
                                  TextButton(
                                      onPressed: busy ? null : () => act(a, 'PROPOSE'),
                                      child: Text(tr('Propose another time'))),
                                  if (a['status'] == 'REQUESTED')
                                    FilledButton(
                                        onPressed: busy ? null : () => act(a, 'ACCEPT'),
                                        child: Text(tr('Accept'))),
                                ],
                              ),
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

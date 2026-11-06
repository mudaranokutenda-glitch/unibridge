import 'package:flutter/material.dart';
import 'config.dart';
import 'l10n.dart';

// ---------------- Consent before uploading personal documents ----------------
// Shown before the first upload of a student card, results or passport.
// The date is stored in document_consents (sql/2026-11-05-03-consent.sql).
// The upload rules in the database also check this consent.
//
// If the text below changes in a way that matters, change kConsentVersion:
// everyone is then asked again before their next upload.

const String kConsentVersion = '2026-11-05';

const List<(String, String)> kConsentSections = [
  (
    'What you upload',
    'Your student record, your results (PDF), your passport scan for an '
        'attestation de bourse, and the photo of your student card.',
  ),
  (
    'Who can see what',
    '• The Educational Attaché of Zimbabwe: everything you upload in the '
        'student space (record, results, passport, attestation).\n'
        '• The representative of your wilaya: your student record and your '
        'results only. Never your passport or your attestation.\n'
        '• The app administrator: can technically access all files in '
        'storage to keep the app running.\n'
        '• Other students: nothing. They never see your documents, your '
        'inscription number or your phone.',
  ),
  (
    'How it is protected',
    'Files are kept in private storage. Every time the attaché or a '
        'representative opens your passport or your results, it is recorded '
        'with the date. Links to a file stop working after a short time.',
  ),
  (
    'How long it is kept',
    'Your passport scan is deleted after your attestation is issued. Your '
        'record and results stay until you delete them or delete your account. '
        'Deleting your account deletes all your files.',
  ),
];

// Returns the date I accepted the current consent, or null.
Future<DateTime?> myConsentDate() async {
  final rows = await supabase
      .from('document_consents')
      .select('accepted_at')
      .eq('user_id', supabase.auth.currentUser!.id)
      .eq('version', kConsentVersion)
      .order('accepted_at', ascending: false)
      .limit(1);
  final list = rows as List;
  if (list.isEmpty) return null;
  return DateTime.tryParse('${list.first['accepted_at']}')?.toLocal();
}

// true when the user has (now or before) accepted. Call before an upload.
Future<bool> ensureDocumentConsent(BuildContext context) async {
  try {
    if (await myConsentDate() != null) return true;
  } catch (e) {
    debugPrint('Could not check consent: $e');
  }
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const ConsentScreen()),
  );
  return ok == true;
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool agreed = false;
  bool saving = false;

  Future<void> accept() async {
    setState(() => saving = true);
    try {
      await supabase.rpc('give_document_consent',
          params: {'p_version': kConsentVersion});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not save: {error}', {'error': e}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Your documents'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('Please read this before you upload a personal document.'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final (title, body) in kConsentSections) ...[
            const SizedBox(height: 16),
            Text(tr(title), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(tr(body)),
          ],
          const SizedBox(height: 16),
          CheckboxListTile(
            value: agreed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(tr('I have read this and I agree.')),
            onChanged: saving ? null : (v) => setState(() => agreed = v == true),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: agreed && !saving ? accept : null,
            child: Text(saving ? tr('Saving...') : tr('Continue')),
          ),
          TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            child: Text(tr('Not now')),
          ),
        ],
      ),
    );
  }
}

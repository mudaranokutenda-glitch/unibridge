import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'app_theme.dart';
import 'profiles.dart';
import 'consent.dart';
import 'l10n.dart';

// ---------------- Student verification request ----------------

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  Map<String, dynamic>? latest; // my most recent request, if any
  bool isVerified = false;
  Uint8List? cardBytes;
  bool loading = true;
  bool submitting = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final myId = supabase.auth.currentUser!.id;
    try {
      final profiles = await fetchPublicProfiles([myId]);
      final data = await supabase
          .from('verification_requests')
          .select('status, note, created_at')
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(1);
      final rows = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      setState(() {
        isVerified = profiles[myId]?['is_verified'] == true;
        latest = rows.isEmpty ? null : rows.first;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = tr('Could not load: {error}', {'error': e});
        loading = false;
      });
    }
  }

  Future<void> pickCard() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => cardBytes = bytes);
  }

  Future<void> submit() async {
    if (cardBytes == null) {
      setState(() => errorMessage = tr('Choose a photo of your student card first'));
      return;
    }
    if (!await ensureDocumentConsent(context)) return;
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      final myId = supabase.auth.currentUser!.id;
      final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('verification').uploadBinary(
            path,
            cardBytes!,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      await supabase.from('verification_requests').insert({
        'user_id': myId,
        'card_photo_path': path,
      });
      cardBytes = null;
      await load();
    } catch (e) {
      setState(() => errorMessage = tr('Could not send: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = latest?['status']?.toString();
    final note = (latest?['note'] ?? '').toString().trim();

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (isVerified) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, size: 64, color: AppColors.verified),
              SizedBox(height: 12),
              Text(tr('You are verified'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                tr('Other users can see the blue tick next to your name.'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else if (status == 'PENDING') {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 64, color: AppColors.warning),
              const SizedBox(height: 12),
              Text(tr('Under review'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                tr('We received your student card and will check it soon. You will see a blue tick here once it is approved.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: load, child: Text(tr('Check again'))),
            ],
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (status == 'REJECTED')
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  note.isEmpty
                      ? tr('Your last request was not approved. You can send a new photo.')
                      : tr('Your last request was not approved: {note}', {'note': note}),
                ),
              ),
            ),
          Text(
            tr('A blue tick tells other students that we checked your student card.'),
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Send a clear photo of your student card. Your name and student number must be readable and must match your account. Only the UniBridge team can view this photo. It is used for this check and is never shown to other users.'),
            style: TextStyle(fontSize: 13, color: kMutedText),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: submitting ? null : pickCard,
            child: Container(
              height: 190,
              decoration: BoxDecoration(
                color: kPlaceholderBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: cardBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(cardBytes!, fit: BoxFit.cover),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined, size: 40),
                          SizedBox(height: 6),
                          Text(tr('Tap to choose a photo of your student card')),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(errorMessage!,
                  style: const TextStyle(color: AppColors.cancelled)),
            ),
          ElevatedButton(
            onPressed: submitting ? null : submit,
            child: Text(submitting ? tr('Sending...') : tr('Send for review')),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Get verified'))),
      body: body,
    );
  }
}

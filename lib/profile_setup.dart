import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'auth.dart';
import 'home.dart';
import 'profiles.dart';
import 'wilayas.dart';
import 'l10n.dart';

// ---------------- Profile photo (shared with the My profile screen) ----------

// Opens the gallery. Returns the photo, or null if nothing was chosen.
Future<Uint8List?> pickProfilePhotoBytes() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 70,
    maxWidth: 600,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}

// Uploads the photo and returns its public link (for profile_picture_url).
Future<String> uploadProfilePhoto(Uint8List bytes) async {
  final myId = supabase.auth.currentUser!.id;
  final fileName =
      'avatars/${myId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await supabase.storage.from('listings').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
  return supabase.storage.from('listings').getPublicUrl(fileName);
}

// ---------------- Is my profile complete? ----------------

bool hasProfilePhoto(Map<String, dynamic>? p) =>
    (p?['profile_picture_url'] ?? '').toString().trim().isNotEmpty;

// Complete = a photo AND a wilaya from the fixed list of 58.
bool isProfileComplete(Map<String, dynamic>? p) =>
    hasProfilePhoto(p) && validWilaya(p?['wilaya']) != null;

// Used when my profile could not be loaded: the name from sign-up or Google.
Map<String, dynamic> myFallbackProfile() {
  final user = supabase.auth.currentUser;
  final meta = user?.userMetadata ?? const {};
  final name = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
  return {'id': user?.id, 'full_name': name};
}

// Reads my own profile. Unlike fetchPublicProfiles, errors are NOT hidden,
// so a network problem is not mistaken for an empty profile.
Future<Map<String, dynamic>?> loadMyProfileStrict() async {
  final myId = supabase.auth.currentUser!.id;
  final data = await supabase.rpc('get_public_profiles', params: {
    'p_ids': [myId]
  });
  final rows = List<Map<String, dynamic>>.from(data as List);
  return rows.isEmpty ? null : rows.first;
}

// ---------------- Gate: shown after login and at every app start ----------

// Shows the set-up page while my profile is incomplete, otherwise the app.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  bool loading = true;
  bool failed = false;
  Map<String, dynamic>? me;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final p = await loadMyProfileStrict();
      if (!mounted) return;
      setState(() {
        me = p;
        loading = false;
      });
    } catch (e) {
      debugPrint('Profile check failed: $e');
      if (!mounted) return;
      setState(() {
        failed = true;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (failed) {
      // No connection: we cannot know if the profile is complete. Retry.
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Could not load your profile. Check your connection.'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: check, child: Text(tr('Try again'))),
                TextButton(
                  onPressed: () => confirmAndLogOut(context),
                  child: Text(tr('Log out')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!isProfileComplete(me)) {
      return ProfileSetupScreen(profile: me, onSaved: check);
    }
    return const HomeScreen(); // opens on the Requests tab
  }
}

// ---------------- "Set up your profile" (cannot be skipped) ----------------

class ProfileSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;
  // Called after a successful save; the gate then checks again.
  final Future<void> Function() onSaved;
  const ProfileSetupScreen(
      {super.key, required this.profile, required this.onSaved});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  Uint8List? newPhotoBytes;
  String? wilaya;
  final locationController = TextEditingController();
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    wilaya = validWilaya(widget.profile?['wilaya']);
    locationController.text = (widget.profile?['location'] ?? '').toString();
  }

  @override
  void dispose() {
    locationController.dispose();
    super.dispose();
  }

  bool get hasPhoto => newPhotoBytes != null || hasProfilePhoto(widget.profile);
  bool get canSave => hasPhoto && wilaya != null && !saving;

  Future<void> pickPhoto() async {
    final bytes = await pickProfilePhotoBytes();
    if (bytes != null && mounted) setState(() => newPhotoBytes = bytes);
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      final myId = supabase.auth.currentUser!.id;
      final location = locationController.text.trim();
      final updates = <String, dynamic>{
        'wilaya': wilaya,
        'location': location.isEmpty ? null : location,
      };
      if (newPhotoBytes != null) {
        updates['profile_picture_url'] = await uploadProfilePhoto(newPhotoBytes!);
      }
      await supabase.from('profiles').update(updates).eq('id', myId);

      // Check that it was really saved (if the account has no profile row,
      // the update changes nothing and gives no error).
      final saved = await loadMyProfileStrict();
      if (!isProfileComplete(saved)) {
        if (mounted) {
          setState(() => errorMessage = tr(
              'Your profile could not be saved. Please contact UniBridge support.'));
        }
        return;
      }
      await widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() =>
            errorMessage = tr('Could not save: {error}', {'error': e}));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (widget.profile?['full_name'] ?? '').toString().trim();
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    // PopScope: the back button cannot leave this page.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Set up your profile')),
          automaticallyImplyLeading: false, // no back arrow
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              tr('Add a photo and your wilaya so other students can trust you.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: saving ? null : pickPhoto,
                child: newPhotoBytes != null
                    ? CircleAvatar(
                        radius: 48,
                        backgroundImage: MemoryImage(newPhotoBytes!),
                      )
                    : hasProfilePhoto(widget.profile)
                        ? avatar(widget.profile, radius: 48)
                        : CircleAvatar(
                            radius: 48,
                            backgroundColor: scheme.surfaceContainerHighest,
                            foregroundColor: scheme.onSurfaceVariant,
                            child: const Icon(Icons.add_a_photo, size: 32),
                          ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                hasPhoto
                    ? tr('Tap the picture to change it')
                    : tr('Tap to add a photo (required)'),
                style: muted,
              ),
            ),
            const SizedBox(height: 20),
            // The name cannot be changed in the app (database rules).
            Text(tr('Name'), style: muted),
            const SizedBox(height: 2),
            name.isNotEmpty
                ? Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))
                : Text(
                    tr('Your name is missing. Contact UniBridge support to add it.'),
                    style: TextStyle(color: scheme.error),
                  ),
            const SizedBox(height: 16),
            WilayaDropdown(
              value: wilaya,
              label: tr('Wilaya (required)'),
              onChanged: saving ? null : (v) => setState(() => wilaya = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              enabled: !saving,
              decoration: InputDecoration(
                  labelText: tr('City or area (optional)')),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: TextStyle(color: scheme.error)),
              ),
            FilledButton(
              onPressed: canSave ? save : null,
              child: Text(saving ? tr('Please wait...') : tr('Save')),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: saving ? null : () => confirmAndLogOut(context),
                child: Text(tr('Log out')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

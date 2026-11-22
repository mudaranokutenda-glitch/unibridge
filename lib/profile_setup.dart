import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'auth.dart';
import 'home.dart';
import 'profiles.dart';
import 'wilayas.dart';
import 'l10n.dart';

// ---------------- Profile photo (shared with the My profile screen) ----------

// Asks "Take a photo" or "Choose from gallery", then opens it.
// Returns the photo, or null if nothing was chosen.
Future<Uint8List?> pickProfilePhotoBytes(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('Profile photo'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Take a photo')),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Choose from gallery')),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  } catch (e) {
    debugPrint('Could not open the camera / gallery: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Could not open the camera or the gallery.'))));
    }
    return null;
  }
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

// ---------------- Phone number (private table user_phones) ----------------
// Only I, the Educational Attaché / admin and the Governor of my wilaya can
// read it (database rules in sql/2026-11-11-02-phone.sql).

final RegExp kPhonePattern = RegExp(r'^\+(263|213)[0-9]{8,10}$');

bool isValidPhone(String? v) => kPhonePattern.hasMatch((v ?? '').trim());

// The phone fields in the app accept exactly 9 digits after +213 / +263.
// (The database rule is wider, 8 to 10 digits, so older numbers still work.)
final RegExp kNewPhonePattern = RegExp(r'^\+(263|213)[0-9]{9}$');
bool isNewPhoneFormat(String? v) => kNewPhonePattern.hasMatch((v ?? '').trim());

// Only "+" and digits can be typed.
final List<TextInputFormatter> kPhoneInput = [
  FilteringTextInputFormatter.allow(RegExp(r'[+0-9]')),
  LengthLimitingTextInputFormatter(14),
];

Future<String?> loadMyPhone() async {
  final row = await supabase
      .from('user_phones')
      .select('phone')
      .eq('user_id', supabase.auth.currentUser!.id)
      .maybeSingle();
  return row?['phone']?.toString();
}

Future<void> saveMyPhone(String phone) async {
  await supabase.from('user_phones').upsert({
    'user_id': supabase.auth.currentUser!.id,
    'phone': phone.trim(),
  });
}

// ---------------- Is my profile complete? ----------------

bool hasProfilePhoto(Map<String, dynamic>? p) =>
    (p?['profile_picture_url'] ?? '').toString().trim().isNotEmpty;

bool hasName(Map<String, dynamic>? p) =>
    (p?['full_name'] ?? '').toString().trim().isNotEmpty;

// Cleans a typed name: no spaces at the ends, single spaces inside.
String cleanName(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');
bool isValidName(String v) {
  final n = cleanName(v);
  return n.length >= 2 && n.length <= 80;
}

// Complete = a photo AND a wilaya from the fixed list of 58.
// (The gate also checks the name and the phone number, see ProfileGate.)
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

// true when an error means "this login is no longer valid" (not "no internet").
bool isSessionExpired(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    return !(m.contains('network') || m.contains('socket') ||
        m.contains('failed host lookup') || m.contains('timeout'));
  }
  if (e is PostgrestException) {
    return e.code == 'PGRST301' || e.code == 'PGRST303' ||
        e.message.toLowerCase().contains('jwt');
  }
  return false;
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
  String? phone;

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
      // If the phone cannot be read (no internet), the whole check fails and
      // the "Try again" screen is shown. The phone is never skipped.
      final ph = await loadMyPhone();
      if (!mounted) return;
      setState(() {
        me = p;
        phone = ph;
        loading = false;
      });
    } catch (e) {
      debugPrint('Profile check failed: $e');
      if (!mounted) return;
      if (isSessionExpired(e)) {
        // The login on this phone is no longer valid (password changed,
        // account deleted, logged out elsewhere): back to the login screen.
        try {
          await supabase.auth.signOut();
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
        return;
      }
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
    if (!isProfileComplete(me) || !hasName(me) || !isValidPhone(phone)) {
      return ProfileSetupScreen(profile: me, phone: phone, onSaved: check);
    }
    return const HomeScreen(); // opens on the Requests tab
  }
}

// ---------------- "Set up your profile" (cannot be skipped) ----------------

class ProfileSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String? phone;
  // Called after a successful save; the gate then checks again.
  final Future<void> Function() onSaved;
  const ProfileSetupScreen(
      {super.key, required this.profile, this.phone, required this.onSaved});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  Uint8List? newPhotoBytes;
  String? wilaya;
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  final nameController = TextEditingController(); // only when the name is missing
  bool nameSaved = false; // set_my_name worked (a retry must not call it again)
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    wilaya = validWilaya(widget.profile?['wilaya']);
    locationController.text = (widget.profile?['location'] ?? '').toString();
    phoneController.text = widget.phone ?? '';
  }

  @override
  void dispose() {
    locationController.dispose();
    phoneController.dispose();
    nameController.dispose();
    super.dispose();
  }

  bool get hasPhoto => newPhotoBytes != null || hasProfilePhoto(widget.profile);
  bool get nameMissing => !hasName(widget.profile);
  bool get canSave =>
      hasPhoto &&
      wilaya != null &&
      isNewPhoneFormat(phoneController.text) &&
      (!nameMissing || isValidName(nameController.text)) &&
      !saving;

  Future<void> pickPhoto() async {
    final bytes = await pickProfilePhotoBytes(context);
    if (bytes != null && mounted) setState(() => newPhotoBytes = bytes);
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      final myId = supabase.auth.currentUser!.id;
      // The name can be set only once, and only when it is empty (database
      // function set_my_name, sql/2026-11-19-03).
      if (nameMissing && !nameSaved) {
        await supabase.rpc('set_my_name',
            params: {'p_name': cleanName(nameController.text)});
        nameSaved = true;
      }
      final location = locationController.text.trim();
      final updates = <String, dynamic>{
        'wilaya': wilaya,
        'location': location.isEmpty ? null : location,
      };
      if (newPhotoBytes != null) {
        updates['profile_picture_url'] = await uploadProfilePhoto(newPhotoBytes!);
      }
      await supabase.from('profiles').update(updates).eq('id', myId);
      await saveMyPhone(phoneController.text);

      // Check that it was really saved (if the account has no profile row,
      // the update changes nothing and gives no error).
      final saved = await loadMyProfileStrict();
      if (!isProfileComplete(saved) || !hasName(saved)) {
        if (mounted) {
          setState(() => errorMessage = tr(
              'Your profile could not be saved. Please contact AZSA support.'));
        }
        return;
      }
      await widget.onSaved();
    } on PostgrestException catch (e) {
      // Messages written by the database (for example about the name).
      if (mounted) setState(() => errorMessage = tr(e.message));
    } catch (e) {
      debugPrint('Profile save failed: $e');
      if (mounted) {
        setState(() => errorMessage =
            tr('Could not save. Check your internet and try again.'));
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
              tr('Add a photo, your wilaya and your phone number.'),
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
            // The name cannot be changed in the app (database rules). Only a
            // missing name can be typed here, once.
            if (name.isNotEmpty)
              // Name from sign-up or Google: shown in the box, locked.
              TextFormField(
                initialValue: name,
                readOnly: true,
                enableInteractiveSelection: false,
                decoration: InputDecoration(
                  labelText: tr('Full name'),
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: const Icon(Icons.lock_outline, size: 18),
                  helperText: tr("Your name can't be changed."),
                  filled: true,
                ),
              )
            else
              TextField(
                controller: nameController,
                enabled: !saving && !nameSaved,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Full name (required)'),
                  helperText: tr(
                      'As on your passport. You cannot change it later.'),
                  helperMaxLines: 2,
                ),
              ),
            const SizedBox(height: 16),
            WilayaDropdown(
              value: wilaya,
              label: tr('Wilaya (required)'),
              onChanged: saving ? null : (v) => setState(() => wilaya = v),
            ),
            const SizedBox(height: 12),
            PhoneField(
              controller: phoneController,
              enabled: !saving,
              onChanged: (_) => setState(() {}),
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

// ---------------- Phone field (set-up page and My profile) ----------------

class PhoneField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? label;
  final String? helper;
  const PhoneField(
      {super.key,
      required this.controller,
      this.enabled = true,
      this.onChanged,
      this.label,
      this.helper});

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

// A country selector (+213 Algeria, +263 Zimbabwe) and a field for the digits only.
// The controller always holds the whole number (+213XXXXXXXXX), or '' when empty,
// so the code that reads the controller does not change. An existing number
// (set in the controller, also later) fills the selector and the digits.
class _PhoneFieldState extends State<PhoneField> {
  static const prefixes = ['+213', '+263'];
  final digits = TextEditingController();
  String prefix = '+213';

  @override
  void initState() {
    super.initState();
    readFromController();
    widget.controller.addListener(onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(onControllerChanged);
    digits.dispose();
    super.dispose();
  }

  String get composed => digits.text.isEmpty ? '' : prefix + digits.text;

  // The number was set from outside (for example loaded from the database).
  void onControllerChanged() {
    if (widget.controller.text.trim() != composed) {
      setState(readFromController);
    }
  }

  void readFromController() {
    final t = widget.controller.text.trim();
    var rest = t;
    for (final p in prefixes) {
      if (t.startsWith(p)) {
        prefix = p;
        rest = t.substring(p.length);
        break;
      }
    }
    digits.text = rest.replaceAll(RegExp(r'[^0-9]'), '');
  }

  void changed() {
    // The first 0 of a local number is not part of the 9 digits.
    if (digits.text.startsWith('0')) {
      final t = digits.text.replaceFirst(RegExp(r'^0+'), '');
      // Keep the cursor at the end (setting .text alone can move it).
      digits.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
    widget.controller.text = composed;
    widget.onChanged?.call(composed);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = digits.text.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: DropdownButtonFormField<String>(
            key: ValueKey(prefix),
            initialValue: prefix,
            isExpanded: true,
            decoration: const InputDecoration(),
            selectedItemBuilder: (_) => [for (final p in prefixes) Text(p)],
            items: [
              DropdownMenuItem(
                  value: '+213', child: Text('+213 ${tr('Algeria')}')),
              DropdownMenuItem(
                  value: '+263', child: Text('+263 ${tr('Zimbabwe')}')),
            ],
            onChanged: widget.enabled
                ? (v) {
                    prefix = v ?? prefix;
                    changed();
                  }
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: digits,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => changed(),
            decoration: InputDecoration(
              labelText: widget.label ?? tr('Phone number (required)'),
              helperText: widget.helper ??
                  tr('9 digits, without the first 0. Only you, the Educational Attaché and your Governor can see it.'),
              helperMaxLines: 3,
              errorText: n == 0 || n == 9
                  ? null
                  : tr('Enter the 9 digits after the code.'),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'app_theme.dart';
import 'push.dart';
import 'verification.dart';
import 'auth.dart';
import 'legal.dart';
import 'roles.dart';
import 'staff.dart';
import 'wilayas.dart';
import 'profile_setup.dart';
import 'l10n.dart';

// ---------------- Public profile helpers ----------------

int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
double? asDouble(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

String publicDisplayName(Map<String, dynamic> p) {
  final name = (p['full_name'] ?? '').toString().trim();
  return name.isEmpty ? tr('UniBridge user') : name;
}

String profilePlace(Map<String, dynamic> p) {
  final wilaya = (p['wilaya'] ?? '').toString().trim();
  final location = (p['location'] ?? '').toString().trim();
  return [
    if (wilaya.isNotEmpty && wilaya != 'OTHER') wilaya,
    if (location.isNotEmpty) location,
  ].join(' • ');
}

String? otherPartyId(Map<String, dynamic> r, String myId) {
  final creator = r['creator_id']?.toString();
  final matched = r['matched_with_id']?.toString();
  return creator == myId ? matched : creator;
}

String _memberSince(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '');
  if (d == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final local = d.toLocal();
  return '${months[local.month - 1]} ${local.year}';
}

Future<Map<String, Map<String, dynamic>>> fetchPublicProfiles(
    Iterable<String?> ids) async {
  final uniqueIds =
      ids.whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
  if (uniqueIds.isEmpty) return {};
  try {
    final data = await supabase
        .rpc('get_public_profiles', params: {'p_ids': uniqueIds});
    final rows = List<Map<String, dynamic>>.from(data as List);
    return {for (final p in rows) p['id'].toString(): p};
  } catch (e) {
    debugPrint('Could not load profiles: $e');
    return {};
  }
}

// Everyone I blocked + everyone who blocked me. Their requests and
// listings are hidden. If this fails, nothing is hidden (app still works).
Future<Set<String>> fetchHiddenUserIds() async {
  try {
    final data = await supabase.rpc('get_hidden_user_ids');
    return (data as List)
        .map((v) => v is Map ? v.values.first.toString() : v.toString())
        .toSet();
  } catch (e) {
    debugPrint('Could not load blocked users: $e');
    return {};
  }
}

Widget avatar(Map<String, dynamic>? p, {double radius = 20}) {
  final url = (p?['profile_picture_url'] ?? '').toString();
  final name = p == null ? '?' : publicDisplayName(p);
  return CircleAvatar(
    radius: radius,
    backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
    child: url.isEmpty
        ? Text(
            String.fromCharCode(name.runes.first).toUpperCase(),
            style: TextStyle(fontSize: radius * 0.8),
          )
        : null,
  );
}

Widget _statRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

// Small card showing who someone is: name, badge, place, rating, history.
class ProfileSummary extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final bool tappable;
  const ProfileSummary({super.key, required this.profile, this.tappable = true});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) {
      return Text(
        tr('Profile unavailable'),
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }

    final displayName = publicDisplayName(p);
    final place = profilePlace(p);
    final verified = p['is_verified'] == true;
    final ratingCount = _asInt(p['rating_count']);
    final avg = asDouble(p['avg_rating']);
    final completed = _asInt(p['completed_count']);

    final stats = <String>[
      if (ratingCount > 0 && avg != null)
        '★ ${avg.toStringAsFixed(1)} ($ratingCount)'
      else
        tr('No ratings yet'),
      if (completed > 0) tr('{count} completed', {'count': completed}) else tr('New member'),
    ];

    final content = Row(
      children: [
        avatar(p),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 16, color: AppColors.verified),
                  ],
                ],
              ),
              if (place.isNotEmpty)
                Text(place,
                    style: const TextStyle(fontSize: 12, color: kMutedText)),
              Text(stats.join(' • '),
                  style: const TextStyle(fontSize: 12, color: kMutedText)),
            ],
          ),
        ),
        if (tappable) const Icon(Icons.chevron_right, color: Colors.grey),
      ],
    );

    if (!tappable) return content;
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: p['id'].toString()),
          ),
        );
      },
      child: content,
    );
  }
}

// ---------------- Full profile of another user ----------------

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> reviews = [];
  bool loading = true;
  bool iBlocked = false;

  @override
  void initState() {
    super.initState();
    load();
    loadBlocked();
  }

  Future<void> loadBlocked() async {
    try {
      final rows = await supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', supabase.auth.currentUser!.id)
          .eq('blocked_id', widget.userId);
      if (mounted) setState(() => iBlocked = (rows as List).isNotEmpty);
    } catch (e) {
      debugPrint('Could not load block status: $e');
    }
  }

  Future<void> toggleBlock() async {
    final name = profile == null ? tr('this user') : publicDisplayName(profile!);
    if (!iBlocked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Block {name}?', {'name': name})),
          content: Text(tr(
              "You won't see each other's requests or listings, and you "
              "can't message each other. Open transactions can still be "
              'confirmed or disputed. You can unblock later in your profile.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Block')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      if (iBlocked) {
        await supabase
            .from('user_blocks')
            .delete()
            .eq('blocker_id', supabase.auth.currentUser!.id)
            .eq('blocked_id', widget.userId);
      } else {
        await supabase
            .from('user_blocks')
            .insert({'blocked_id': widget.userId});
      }
      if (!mounted) return;
      setState(() => iBlocked = !iBlocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(iBlocked
            ? tr('{name} blocked.', {'name': name})
            : tr('{name} unblocked.', {'name': name}))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
        );
      }
    }
  }

  Future<void> load() async {
    final profiles = await fetchPublicProfiles([widget.userId]);
    List<Map<String, dynamic>> loadedReviews = [];
    try {
      final data = await supabase
          .from('ratings')
          .select('score, comment, created_at')
          .eq('rated_user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(30);
      loadedReviews = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Could not load reviews: $e');
    }
    if (!mounted) return;
    setState(() {
      profile = profiles[widget.userId];
      reviews = loadedReviews;
      loading = false;
    });
  }

  // Lets the user report this person. The report is saved in user_reports
  // and the owner reviews it in Supabase.
  Future<void> reportUser() async {
    final reasons = {
      'SCAM': tr('Scam or fraud'),
      'HARASSMENT': tr('Harassment'),
      'FAKE_PROFILE': tr('Fake profile'),
      'INAPPROPRIATE': tr('Inappropriate content'),
      'OTHER': tr('Other'),
    };
    String? selected;
    final detailsController = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('Report user')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in reasons.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(selected == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(entry.value),
                    onTap: () => setDialogState(() => selected = entry.key),
                  ),
                TextField(
                  controller: detailsController,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: tr('Details (optional)'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: Text(tr('Send report')),
            ),
          ],
        ),
      ),
    );
    if (send != true || selected == null) return;

    final details = detailsController.text.trim();
    try {
      await supabase.from('user_reports').insert({
        'reported_id': widget.userId,
        'reason': selected,
        'details': details.isEmpty ? null : details,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr("Thanks, we'll review this report."))),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // 23505 = the unique rule: an open report about this user already exists.
      final text = e.code == '23505'
          ? tr('You already reported this user. We are reviewing it.')
          : tr('Could not send report: {error}', {'error': e.message});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not send report: {error}', {'error': e}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final isMe = widget.userId == supabase.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Profile')),
        actions: [
          if (!isMe && p != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') reportUser();
                if (value == 'block') toggleBlock();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'report', child: Text(tr('Report user'))),
                PopupMenuItem(
                  value: 'block',
                  child: Text(iBlocked ? tr('Unblock user') : tr('Block user')),
                ),
              ],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Text(tr('Profile unavailable')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(child: avatar(p, radius: 40)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            publicDisplayName(p),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (p['is_verified'] == true) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, color: AppColors.verified),
                        ],
                      ],
                    ),
                    if (profilePlace(p).isNotEmpty)
                      Center(
                        child: Text(
                          profilePlace(p),
                          style: const TextStyle(color: kMutedText),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _statRow(
                              tr('Rating'),
                              _asInt(p['rating_count']) > 0
                                  ? tr('★ {avg} ({count} reviews)', {'avg': asDouble(p['avg_rating'])?.toStringAsFixed(1), 'count': _asInt(p['rating_count'])})
                                  : tr('No ratings yet'),
                            ),
                            _statRow(tr('Completed transactions'),
                                '${_asInt(p['completed_count'])}'),
                            _statRow(tr('Trust score'), '${_asInt(p['trust_score'])}'),
                            _statRow(tr('Member since'), _memberSince(p['joined'])),
                            _statRow(tr('Verified'),
                                p['is_verified'] == true ? tr('Yes') : tr('Not yet')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('Reviews'),
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    if (reviews.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(tr('No reviews yet.'),
                            style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...reviews.map((rev) {
                        var score = _asInt(rev['score']);
                        if (score < 0) score = 0;
                        if (score > 5) score = 5;
                        final comment =
                            (rev['comment'] ?? '').toString().trim();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '★' * score + '☆' * (5 - score),
                            style: const TextStyle(color: Colors.amber),
                          ),
                          subtitle: comment.isEmpty ? null : Text(comment),
                        );
                      }),
                  ],
                ),
    );
  }
}

// ---------------- Edit my own profile ----------------

class EditMyProfileScreen extends StatefulWidget {
  const EditMyProfileScreen({super.key});

  @override
  State<EditMyProfileScreen> createState() => _EditMyProfileScreenState();
}

class _EditMyProfileScreenState extends State<EditMyProfileScreen> {
  String? wilaya; // one of the 58, or null = not chosen
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  Map<String, dynamic>? me;
  MyRole role = MyRole.student;
  Uint8List? newPhotoBytes;
  bool loading = true;
  bool saving = false;
  bool deleting = false;
  String? errorMessage;

  void showDeleteError(String text) {
    if (!mounted) return;
    setState(() => deleting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 6)),
    );
  }

  // Asks the user to type DELETE, then calls the delete-account Edge
  // Function (it refuses while a transaction is in progress).
  Future<void> deleteAccount() async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('Delete my account')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(
                  'This cannot be undone.\n\n'
                  'Deleted: your profile, phone number, all your photos and '
                  'files (also the photos you sent in chats, your results, '
                  'passport and attestations), your student record, bank '
                  'account and passport numbers, appointments, listings, open '
                  'requests, notifications and blocks.\n\n'
                  'Kept for the other person: finished transactions, chat '
                  'text messages and ratings (you will show as "UniBridge '
                  'user").\n\n'
                  'Type DELETE to confirm.',
                )),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'DELETE'),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: confirmController.text.trim() == 'DELETE'
                  ? () => Navigator.of(context).pop(true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
              child: Text(tr('Delete forever')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => deleting = true);
    try {
      await supabase.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      final details = e.details;
      final text = e.status == 409
          ? tr('Finish or resolve your open transactions first.')
          : e.status == 403
              ? tr('Staff accounts are removed by the app owner.')
              : tr('Could not delete account: {error}',
                  {'error': details is Map ? details['error'] : details});
      showDeleteError(text);
      return;
    } catch (e) {
      showDeleteError(tr('Could not delete account: {error}', {'error': e}));
      return;
    }

    // The account is gone: sign out on this phone and go to the login screen.
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out after delete: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Your account has been deleted.'))),
    );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final myId = supabase.auth.currentUser!.id;
    final profiles = await fetchPublicProfiles([myId]);
    final p = profiles[myId];
    final loadedRole = await loadMyRole();
    String? phone;
    try {
      phone = await loadMyPhone();
    } catch (e) {
      debugPrint('Could not load phone: $e');
    }
    if (!mounted) return;
    setState(() {
      me = p;
      role = loadedRole;
      phoneController.text = phone ?? '';
      wilaya = validWilaya(p?['wilaya']);
      locationController.text = (p?['location'] ?? '').toString();
      loading = false;
    });
  }

  // Shared with the "Set up your profile" page (profile_setup.dart).
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
      if (!isNewPhoneFormat(phoneController.text)) {
        setState(() => errorMessage =
            tr('Choose +213 or +263 and enter the 9 digits.'));
        return;
      }
      final updates = <String, dynamic>{
        'wilaya': wilaya ?? 'OTHER',
        'location': locationController.text.trim().isEmpty
            ? null
            : locationController.text.trim(),
      };

      if (newPhotoBytes != null) {
        updates['profile_picture_url'] =
            await uploadProfilePhoto(newPhotoBytes!);
      }

      await supabase.from('profiles').update(updates).eq('id', myId);
      await saveMyPhone(phoneController.text);
      // This screen is a tab now, so stay here and show the new card.
      newPhotoBytes = null;
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Profile saved.'))),
        );
      }
    } catch (e) {
      setState(() => errorMessage = tr('Could not save: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('My profile'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: saving ? null : pickPhoto,
                    child: newPhotoBytes != null
                        ? CircleAvatar(
                            radius: 48,
                            backgroundImage: MemoryImage(newPhotoBytes!),
                          )
                        : avatar(me, radius: 48),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(tr('Tap the picture to change it'),
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 20),
                Text(tr('This is how others see you:'),
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ProfileSummary(profile: me, tappable: false),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Your name comes from sign-up and can\'t be changed here.'),
                  style: TextStyle(fontSize: 12, color: kMutedText),
                ),
                const SizedBox(height: 20),
                WilayaDropdown(
                  value: wilaya,
                  onChanged: saving ? null : (v) => setState(() => wilaya = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: InputDecoration(
                    labelText: tr('Location (city / area)'),
                  ),
                ),
                const SizedBox(height: 12),
                PhoneField(
                  controller: phoneController,
                  enabled: !saving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(errorMessage!,
                        style: const TextStyle(color: AppColors.cancelled)),
                  ),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const VerificationScreen()),
                          );
                        },
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(tr('Get verified')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const BlockedUsersScreen()),
                          );
                        },
                  icon: const Icon(Icons.block),
                  label: Text(tr('Blocked users')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LegalScreen()),
                    );
                  },
                  icon: const Icon(Icons.description_outlined),
                  label: Text(tr('Terms and privacy')),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? tr('Saving...') : tr('Save')),
                ),
                if (role.canSeeStudents) ...[
                  const SizedBox(height: 24),
                  StaffSection(role: role),
                ],
                const SizedBox(height: 24),
                const SettingsSection(),
                const SizedBox(height: 12),
                const NewRequestNotificationsTile(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: (saving || deleting)
                      ? null
                      : () => confirmAndLogOut(context),
                  icon: const Icon(Icons.logout),
                  label: Text(tr('Log out')),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: (saving || deleting) ? null : deleteAccount,
                  style: TextButton.styleFrom(foregroundColor: AppColors.cancelled),
                  icon: const Icon(Icons.delete_forever),
                  label: Text(deleting ? tr('Deleting...') : tr('Delete my account')),
                ),
              ],
            ),
    );
  }
}

// ---------------- Blocked users (unblock here) ----------------

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<String> blockedIds = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', supabase.auth.currentUser!.id)
          .order('created_at', ascending: false);
      final ids = (rows as List).map((r) => r['blocked_id'].toString()).toList();
      final loadedProfiles = await fetchPublicProfiles(ids);
      if (!mounted) return;
      setState(() {
        blockedIds = ids;
        profiles = loadedProfiles;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not load blocked users: {error}', {'error': e}))),
      );
    }
  }

  Future<void> unblock(String id) async {
    try {
      await supabase
          .from('user_blocks')
          .delete()
          .eq('blocker_id', supabase.auth.currentUser!.id)
          .eq('blocked_id', id);
      if (mounted) setState(() => blockedIds.remove(id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Error: {error}', {'error': e}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Blocked users'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : blockedIds.isEmpty
              ? Center(child: Text(tr('You have not blocked anyone.')))
              : ListView.builder(
                  itemCount: blockedIds.length,
                  itemBuilder: (context, index) {
                    final id = blockedIds[index];
                    final p = profiles[id];
                    return ListTile(
                      leading: avatar(p),
                      title: Text(p == null ? tr('UniBridge user') : publicDisplayName(p)),
                      trailing: TextButton(
                        onPressed: () => unblock(id),
                        child: Text(tr('Unblock')),
                      ),
                    );
                  },
                ),
    );
  }
}

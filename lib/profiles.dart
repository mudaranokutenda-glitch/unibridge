import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'verification.dart';

// ---------------- Public profile helpers ----------------

int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
double? asDouble(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

String publicDisplayName(Map<String, dynamic> p) {
  final name = (p['full_name'] ?? '').toString().trim();
  return name.isEmpty ? 'UniBridge user' : name;
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
      return const Text(
        'Profile unavailable',
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
        'No ratings yet',
      if (completed > 0) '$completed completed' else 'New member',
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
                    const Icon(Icons.verified, size: 16, color: Colors.blue),
                  ],
                ],
              ),
              if (place.isNotEmpty)
                Text(place,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(stats.join(' • '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
    final name = profile == null ? 'this user' : publicDisplayName(profile!);
    if (!iBlocked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Block $name?'),
          content: const Text(
              "You won't see each other's requests or listings, and you "
              "can't message each other. Open transactions can still be "
              'confirmed or disputed. You can unblock later in your profile.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Block'),
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
        SnackBar(content: Text(iBlocked ? '$name blocked.' : '$name unblocked.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
    const reasons = {
      'SCAM': 'Scam or fraud',
      'HARASSMENT': 'Harassment',
      'FAKE_PROFILE': 'Fake profile',
      'INAPPROPRIATE': 'Inappropriate content',
      'OTHER': 'Other',
    };
    String? selected;
    final detailsController = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report user'),
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
                  decoration: const InputDecoration(
                    hintText: 'Details (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Send report'),
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
          const SnackBar(content: Text("Thanks, we'll review this report.")),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // 23505 = the unique rule: an open report about this user already exists.
      final text = e.code == '23505'
          ? 'You already reported this user. We are reviewing it.'
          : 'Could not send report: ${e.message}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send report: $e')),
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
        title: const Text('Profile'),
        actions: [
          if (!isMe && p != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') reportUser();
                if (value == 'block') toggleBlock();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'report', child: Text('Report user')),
                PopupMenuItem(
                  value: 'block',
                  child: Text(iBlocked ? 'Unblock user' : 'Block user'),
                ),
              ],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const Center(child: Text('Profile unavailable'))
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
                          const Icon(Icons.verified, color: Colors.blue),
                        ],
                      ],
                    ),
                    if (profilePlace(p).isNotEmpty)
                      Center(
                        child: Text(
                          profilePlace(p),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _statRow(
                              'Rating',
                              _asInt(p['rating_count']) > 0
                                  ? '★ ${asDouble(p['avg_rating'])?.toStringAsFixed(1)} (${_asInt(p['rating_count'])} reviews)'
                                  : 'No ratings yet',
                            ),
                            _statRow('Completed transactions',
                                '${_asInt(p['completed_count'])}'),
                            _statRow('Trust score', '${_asInt(p['trust_score'])}'),
                            _statRow('Member since', _memberSince(p['joined'])),
                            _statRow('Verified',
                                p['is_verified'] == true ? 'Yes' : 'Not yet'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Reviews',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    if (reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No reviews yet.',
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
  final wilayaController = TextEditingController();
  final locationController = TextEditingController();
  Map<String, dynamic>? me;
  Uint8List? newPhotoBytes;
  bool loading = true;
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final myId = supabase.auth.currentUser!.id;
    final profiles = await fetchPublicProfiles([myId]);
    final p = profiles[myId];
    if (!mounted) return;
    setState(() {
      me = p;
      final wilaya = (p?['wilaya'] ?? '').toString();
      wilayaController.text = wilaya == 'OTHER' ? '' : wilaya;
      locationController.text = (p?['location'] ?? '').toString();
      loading = false;
    });
  }

  Future<void> pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => newPhotoBytes = bytes);
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      errorMessage = null;
    });
    try {
      final myId = supabase.auth.currentUser!.id;
      final updates = <String, dynamic>{
        'wilaya': wilayaController.text.trim().isEmpty
            ? 'OTHER'
            : wilayaController.text.trim(),
        'location': locationController.text.trim().isEmpty
            ? null
            : locationController.text.trim(),
      };

      if (newPhotoBytes != null) {
        final fileName =
            'avatars/${myId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('listings').uploadBinary(
              fileName,
              newPhotoBytes!,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        updates['profile_picture_url'] =
            supabase.storage.from('listings').getPublicUrl(fileName);
      }

      await supabase.from('profiles').update(updates).eq('id', myId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
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
                const Center(
                  child: Text('Tap the picture to change it',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 20),
                const Text('This is how others see you:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ProfileSummary(profile: me, tappable: false),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your name and student ID come from sign-up and can\'t be changed here. Your student ID is never shown to other users.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: wilayaController,
                  decoration: const InputDecoration(
                    labelText: 'Wilaya',
                    hintText: 'e.g. Annaba',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location (city / area)',
                  ),
                ),
                const SizedBox(height: 20),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(errorMessage!,
                        style: const TextStyle(color: Colors.red)),
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
                  label: const Text('Get verified'),
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
                  label: const Text('Blocked users'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving...' : 'Save'),
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
        SnackBar(content: Text('Could not load blocked users: $e')),
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
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : blockedIds.isEmpty
              ? const Center(child: Text('You have not blocked anyone.'))
              : ListView.builder(
                  itemCount: blockedIds.length,
                  itemBuilder: (context, index) {
                    final id = blockedIds[index];
                    final p = profiles[id];
                    return ListTile(
                      leading: avatar(p),
                      title: Text(p == null ? 'UniBridge user' : publicDisplayName(p)),
                      trailing: TextButton(
                        onPressed: () => unblock(id),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                ),
    );
  }
}

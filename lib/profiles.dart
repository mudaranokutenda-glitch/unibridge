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
import 'errors.dart';
import 'notifications.dart';
import 'rates.dart';

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

// ---------------- Profile header (my profile + other people) ----------------

// Trust level shown as a word (the raw number means nothing to students).
// No completed exchange yet = "New".
(String, Color) trustLevel(Map<String, dynamic> p) {
  final completed = _asInt(p['completed_count']);
  final score = _asInt(p['trust_score']);
  if (completed == 0) return (tr('New'), Colors.white);
  if (score >= 70) return (tr('Trusted'), const Color(0xFF7CF2A9));
  if (score >= 50) return (tr('Good'), Colors.white);
  return (tr('Low'), const Color(0xFFFFC46B));
}

class ProfileHero extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final Uint8List? newPhoto; // a photo picked but not saved yet
  final VoidCallback? onTapPhoto; // null = the photo cannot be changed here
  const ProfileHero(
      {super.key, required this.profile, this.newPhoto, this.onTapPhoto});

  Widget _stat(String value, String label, {Color color = Colors.white}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = profile ?? const <String, dynamic>{};
    final verified = p['is_verified'] == true;
    final place = profile == null ? '' : profilePlace(p);
    final ratingCount = _asInt(p['rating_count']);
    final avg = asDouble(p['avg_rating']);
    final (trustText, trustColor) = trustLevel(p);
    final joined = _memberSince(p['joined']);

    final photo = newPhoto != null
        ? CircleAvatar(radius: 46, backgroundImage: MemoryImage(newPhoto!))
        : avatar(profile, radius: 46);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6BB0FF), AppColors.sky, AppColors.skyDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            GestureDetector(
              onTap: onTapPhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: verified ? AppColors.verified : Colors.white,
                    ),
                    child: photo,
                  ),
                  if (onTapPhoto != null)
                    PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.sky, width: 2),
                        ),
                        child: const Icon(Icons.photo_camera,
                            size: 16, color: AppColors.sky),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    profile == null ? '' : publicDisplayName(p),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                if (verified) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, color: AppColors.verified, size: 22),
                ],
              ],
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.place_outlined, size: 15, color: Colors.white),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(place,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92))),
                  ),
                ],
              ),
            ],
            if (joined != '—') ...[
              const SizedBox(height: 2),
              Text(tr('Member since {date}', {'date': joined}),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _stat(
                    ratingCount > 0 && avg != null
                        ? '★ ${avg.toStringAsFixed(1)}'
                        : '—',
                    ratingCount > 0
                        ? tr('{count} reviews', {'count': ratingCount})
                        : tr('No ratings yet')),
                const SizedBox(width: 8),
                _stat('${_asInt(p['completed_count'])}', tr('completed')),
                const SizedBox(width: 8),
                _stat(trustText, tr('trust level'), color: trustColor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Small grey title above a group of settings.
Widget profileSectionTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );

// A rounded card holding rows (ListTiles) with thin lines between them.
Widget profileGroup(List<Widget> rows) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            rows[i],
          ],
        ],
      ),
    );

Widget profileChip(String text, Color color, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );

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
          SnackBar(content: Text(friendlyError(e))),
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
          SnackBar(content: Text(tr('Could not send report: {error}', {'error': friendlyError(e, short: true)}))),
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
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    ProfileHero(profile: p),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (p['is_verified'] == true)
                          profileChip(tr('Verified student'), AppColors.verified,
                              icon: Icons.verified)
                        else
                          profileChip(tr('Not verified yet'), AppColors.expired),
                        if (_asInt(p['completed_count']) > 0)
                          profileChip(
                              tr('{count} exchanges done',
                                  {'count': _asInt(p['completed_count'])}),
                              AppColors.success,
                              icon: Icons.check_circle_outline),
                      ],
                    ),
                    profileSectionTitle(context, tr('Reviews')),
                    if (reviews.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(tr('No reviews yet.'),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      )
                    else
                      for (final rev in reviews) reviewCard(context, rev),
                    if (!isMe) ...[
                      profileSectionTitle(context, tr('Safety')),
                      profileGroup([
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(tr('Report user')),
                          onTap: reportUser,
                        ),
                        ListTile(
                          leading: Icon(iBlocked
                              ? Icons.lock_open_outlined
                              : Icons.block),
                          title: Text(
                              iBlocked ? tr('Unblock user') : tr('Block user')),
                          onTap: toggleBlock,
                        ),
                      ]),
                    ],
                  ],
                ),
    );
  }

  Widget reviewCard(BuildContext context, Map<String, dynamic> rev) {
    var score = _asInt(rev['score']);
    if (score < 0) score = 0;
    if (score > 5) score = 5;
    final comment = (rev['comment'] ?? '').toString().trim();
    final when = DateTime.tryParse('${rev['created_at']}');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('★' * score + '☆' * (5 - score),
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 16, letterSpacing: 1)),
                const Spacer(),
                if (when != null)
                  Text(updatedAgo(when),
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment),
            ],
          ],
        ),
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

// The Profile tab: header + "Edit profile" (bottom sheet) + verification.
// Everything else (language, theme, blocked users, log out...) is on the
// Settings page (gear at the top).
class _EditMyProfileScreenState extends State<EditMyProfileScreen> {
  Map<String, dynamic>? me;
  String? phone;
  MyRole role = MyRole.student;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final myId = supabase.auth.currentUser!.id;
    final profiles = await fetchPublicProfiles([myId]);
    final loadedRole = await loadMyRole();
    String? loadedPhone;
    try {
      loadedPhone = await loadMyPhone();
    } catch (e) {
      debugPrint('Could not load phone: $e');
    }
    if (!mounted) return;
    setState(() {
      me = profiles[myId];
      role = loadedRole;
      phone = loadedPhone;
      loading = false;
    });
  }

  Future<void> openEditSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditProfileSheet(profile: me, phone: phone),
    );
    if (saved == true) {
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Profile saved.'))),
        );
      }
    }
  }

  void openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser!.id;
    final verified = me?['is_verified'] == true;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('My profile')),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: tr('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: openSettings,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ProfileHero(profile: me, onTapPhoto: openEditSheet),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: openEditSheet,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(tr('Edit profile')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        UserProfileScreen(userId: myId))),
                            icon: const Icon(Icons.visibility_outlined),
                            label: Text(tr('Public view')),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // One card only: verification (the most useful next step).
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: (verified
                                ? AppColors.verified
                                : AppColors.sky)
                            .withValues(alpha: 0.15),
                        child: Icon(Icons.verified,
                            color: verified
                                ? AppColors.verified
                                : AppColors.sky),
                      ),
                      title: Text(verified
                          ? tr('You are verified')
                          : tr('Get the gold tick')),
                      subtitle: Text(verified
                          ? tr('Other students see the gold tick on your profile.')
                          : tr('Verified students are trusted more and match faster.')),
                      trailing: verified
                          ? null
                          : Icon(Icons.chevron_right, color: scheme.primary),
                      onTap: verified
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const VerificationScreen())),
                    ),
                  ),
                  if (role.canSeeStudents) ...[
                    profileSectionTitle(context, tr('Staff')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StaffSection(role: role),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ---------------- Edit profile (bottom sheet) ----------------
// Photo, wilaya, city and phone. The name is shown but cannot be changed.
// Returns true (Navigator.pop) after a successful save.

class EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String? phone;
  const EditProfileSheet({super.key, required this.profile, this.phone});

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  String? wilaya;
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  late final TextEditingController nameController;
  Uint8List? newPhotoBytes;
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    wilaya = validWilaya(p?['wilaya']);
    locationController.text = (p?['location'] ?? '').toString();
    phoneController.text = widget.phone ?? '';
    nameController = TextEditingController(
        text: p == null ? '' : publicDisplayName(p));
  }

  @override
  void dispose() {
    locationController.dispose();
    phoneController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final bytes = await pickProfilePhotoBytes();
    if (bytes != null && mounted) setState(() => newPhotoBytes = bytes);
  }

  Future<void> save() async {
    if (wilaya == null) {
      setState(() => errorMessage = tr('Choose your wilaya.'));
      return;
    }
    if (!isNewPhoneFormat(phoneController.text)) {
      setState(() =>
          errorMessage = tr('Choose +213 or +263 and enter the 9 digits.'));
      return;
    }
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
      await saveMyPhone(phoneController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = tr('Could not save: {error}',
            {'error': friendlyError(e, short: true)}));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Moves up with the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Edit profile'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: saving ? null : pickPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    newPhotoBytes != null
                        ? CircleAvatar(
                            radius: 44,
                            backgroundImage: MemoryImage(newPhotoBytes!))
                        : avatar(widget.profile, radius: 44),
                    PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: AppColors.sky,
                        child: const Icon(Icons.photo_camera,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(tr('Tap the picture to change it'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            // The name is shown but can't be changed (database rule).
            TextField(
              controller: nameController,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: InputDecoration(
                labelText: tr('Full name'),
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: const Icon(Icons.lock_outline, size: 18),
                helperText: tr("Your name can't be changed."),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            WilayaDropdown(
              value: wilaya,
              onChanged: saving ? null : (v) => setState(() => wilaya = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              enabled: !saving,
              decoration: InputDecoration(
                labelText: tr('City or area (optional)'),
                prefixIcon: const Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            PhoneField(
              controller: phoneController,
              enabled: !saving,
              onChanged: (_) => setState(() {}),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!,
                  style: const TextStyle(color: AppColors.cancelled)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(saving ? tr('Saving...') : tr('Save changes')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Settings (gear on the Profile tab) ----------------

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool deleting = false;

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
      showDeleteError(tr('Could not delete account: {error}', {'error': friendlyError(e, short: true)}));
      return;
    }

    // The account is gone: sign out on this phone and go to the login screen.
    NotificationCenter.stop();
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          profileSectionTitle(context, tr('App')),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SettingsSection(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: NewRequestNotificationsTile(),
          ),
          profileSectionTitle(context, tr('Privacy')),
          profileGroup([
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(tr('Blocked users')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BlockedUsersScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(tr('Terms and privacy')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LegalScreen())),
            ),
          ]),
          profileSectionTitle(context, tr('Account')),
          profileGroup([
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(tr('Log out')),
              onTap: deleting ? null : () => confirmAndLogOut(context),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_forever, color: AppColors.cancelled),
              title: Text(
                deleting ? tr('Deleting...') : tr('Delete my account'),
                style: const TextStyle(color: AppColors.cancelled),
              ),
              onTap: deleting ? null : deleteAccount,
            ),
          ]),
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
        SnackBar(content: Text(tr('Could not load blocked users: {error}', {'error': friendlyError(e, short: true)}))),
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
          SnackBar(content: Text(friendlyError(e))),
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

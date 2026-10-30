import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

StreamSubscription<RemoteMessage>? _foregroundSub;

void listenForForegroundNotifications(BuildContext context) {
  _foregroundSub?.cancel();
  _foregroundSub =
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final title = message.notification?.title ?? 'UniBridge';
    final body = message.notification?.body ?? '';

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $body'),
        duration: const Duration(seconds: 4),
      ),
    );
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  await Supabase.initialize(
    url: 'https://lhdkzcsaqlhswyytirxb.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxoZGt6Y3NhcWxoc3d5eXRpcnhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMjE2OTEsImV4cCI6MjEwMzU5NzY5MX0._ITsT0ZoXeWfZRJX-OdRBlktvKVsozAHhd6IsnCLTtw',
  );

  runApp(const UniBridgeApp());
}

final supabase = Supabase.instance.client;

const String googleWebClientId =
    '446026136458-6b9o3prsfjcgttf58am8cdkch2b4ghri.apps.googleusercontent.com';

bool _googleSignInInitialized = false;

class UniBridgeApp extends StatelessWidget {
  const UniBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniBridge',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: supabase.auth.currentSession == null
          ? const AuthScreen()
          : const HomeScreen(),
    );
  }
}

// ---------------- Push notification helpers ----------------

StreamSubscription<String>? _tokenRefreshSub;

Future<void> setupPushNotifications() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  debugPrint('Notification permission: ${settings.authorizationStatus}');

  final token = await messaging.getToken();
  debugPrint('FCM TOKEN: $token');

  if (token != null && token.isNotEmpty) {
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('Could not save FCM token: $e');
    }
  }

  // Only one refresh listener at a time, always for the current user.
  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
    debugPrint('New FCM TOKEN: $newToken');
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': newToken})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('Could not update FCM token: $e');
    }
  });
}

// Call this just before signing out, so a logged-out account stops
// receiving notifications on this phone.
Future<void> clearPushToken() async {
  final user = supabase.auth.currentUser;
  await _tokenRefreshSub?.cancel();
  _tokenRefreshSub = null;
  await _foregroundSub?.cancel();
  _foregroundSub = null;
  if (user == null) return;

  try {
    await supabase
        .from('profiles')
        .update({'fcm_token': null})
        .eq('id', user.id);
    await FirebaseMessaging.instance.deleteToken();
  } catch (e) {
    debugPrint('Could not clear FCM token: $e');
  }
}

// ---------------- Public profile helpers ----------------

int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
double? _asDouble(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

String _displayName(Map<String, dynamic> p) {
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

Widget _avatar(Map<String, dynamic>? p, {double radius = 20}) {
  final url = (p?['profile_picture_url'] ?? '').toString();
  final name = p == null ? '?' : _displayName(p);
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

    final displayName = _displayName(p);
    final place = profilePlace(p);
    final verified = p['is_verified'] == true;
    final ratingCount = _asInt(p['rating_count']);
    final avg = _asDouble(p['avg_rating']);
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
        _avatar(p),
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

  @override
  void initState() {
    super.initState();
    load();
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

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const Center(child: Text('Profile unavailable'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(child: _avatar(p, radius: 40)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _displayName(p),
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
                                  ? '★ ${_asDouble(p['avg_rating'])?.toStringAsFixed(1)} (${_asInt(p['rating_count'])} reviews)'
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
                        : _avatar(me, radius: 48),
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
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
    );
  }
}

// ---------------- Sign up / Log in screen ----------------

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignUp = false;
  bool loading = false;
  String? errorMessage;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final fullNameController = TextEditingController();
  final inscriptionController = TextEditingController();

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      if (isSignUp) {
        await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          data: {
            'full_name': fullNameController.text.trim(),
            'inscription_number': inscriptionController.text.trim(),
          },
        );
      } else {
        await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      }
      if (mounted) {
        await setupPushNotifications();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => errorMessage = e.message);
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final googleSignIn = GoogleSignIn.instance;

      if (!_googleSignInInitialized) {
        await googleSignIn.initialize(serverClientId: googleWebClientId);
        _googleSignInInitialized = true;
      }

      final googleUser = await googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        throw 'No ID token received from Google';
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      if (mounted) {
        await setupPushNotifications();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      setState(() => errorMessage = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isSignUp ? 'Create account' : 'Log in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            if (isSignUp) ...[
              TextField(
                controller: fullNameController,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inscriptionController,
                decoration:
                    const InputDecoration(labelText: 'Inscription number'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: Text(loading
                  ? 'Please wait...'
                  : (isSignUp ? 'Sign up' : 'Log in')),
            ),
            TextButton(
              onPressed: () => setState(() => isSignUp = !isSignUp),
              child: Text(isSignUp
                  ? 'Already have an account? Log in'
                  : 'New here? Create an account'),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('OR'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: loading ? null : signInWithGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Continue with Google'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Home screen: browse + create requests ----------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> requests = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadRequests();
    // Covers the case where the app was already signed in from a previous
    // session (so AuthScreen's submit() never ran this time).
    setupPushNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) listenForForegroundNotifications(context);
    });
  }

  Future<void> loadRequests() async {
    setState(() => loading = true);
    final myId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('transaction_requests')
        .select()
        .eq('status', 'OPEN')
        .neq('creator_id', myId)
        .order('created_at', ascending: false);
    final loaded = List<Map<String, dynamic>>.from(data);
    final loadedProfiles = await fetchPublicProfiles(
      loaded.map((r) => r['creator_id'] as String?),
    );
    if (!mounted) return;
    setState(() {
      requests = loaded;
      profiles = loadedProfiles;
      loading = false;
    });
  }

  Future<void> matchWithRequest(String requestId) async {
    try {
      await supabase.rpc('match_request', params: {'p_request_id': requestId});
      loadRequests();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(requestId: requestId)),
        );
      }
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
      appBar: AppBar(
        title: const Text('UniBridge'),
        actions: [
                    const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditMyProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.currency_exchange),
            tooltip: 'Exchange rates',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExchangeRatesScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Marketplace',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'My requests',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;

              await clearPushToken();
              await supabase.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadRequests,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : requests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No open requests right now.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final r = requests[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['type']} • ${r['amount']} ${r['currency']}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        matchWithRequest(r['id']),
                                    child: const Text('Match'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ProfileSummary(
                                profile: profiles[r['creator_id']],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CreateRequestScreen()),
          );
          loadRequests();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
// ---------------- My requests (mine + matched) ----------------

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  String type = 'SEND';
  final amountController = TextEditingController();
  String currency = 'USD';
  bool loading = false;
  String? errorMessage;

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final amount = double.tryParse(amountController.text.trim());
      if (amount == null || amount <= 0) {
        setState(() {
          errorMessage = 'Enter a valid amount';
          loading = false;
        });
        return;
      }
      await supabase.from('transaction_requests').insert({
        'type': type,
        'amount': amount,
        'currency': currency,
        'creator_id': supabase.auth.currentUser!.id,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const Text('What do you want to do?'),
            RadioListTile<String>(
              title: const Text('I want to SEND money'),
              value: 'SEND',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            RadioListTile<String>(
              title: const Text('I want to RECEIVE money'),
              value: 'RECEIVE',
              groupValue: type,
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: ['USD', 'EUR'].map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (v) => setState(() => currency = v!),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: Text(loading ? 'Please wait...' : 'Post request'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- My requests (mine + matched) ----------------

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}
class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<Map<String, dynamic>> myRequests = [];
  Map<String, Map<String, dynamic>> profiles = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final myId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('transaction_requests')
        .select()
        .or('creator_id.eq.$myId,matched_with_id.eq.$myId')
        .order('updated_at', ascending: false);
    final loaded = List<Map<String, dynamic>>.from(data);
    final loadedProfiles = await fetchPublicProfiles(
      loaded.map((r) => otherPartyId(r, myId)),
    );
    if (!mounted) return;
    setState(() {
      myRequests = loaded;
      profiles = loadedProfiles;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('My requests')),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : myRequests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('You have no requests yet.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: myRequests.length,
                    itemBuilder: (context, index) {
                      final r = myRequests[index];
                      final status = r['status'];
                      final otherId = otherPartyId(r, myId);
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                              '${r['type']} • ${r['amount']} ${r['currency']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Status: $status'),
                              const SizedBox(height: 6),
                              if (otherId != null)
                                ProfileSummary(
                                  profile: profiles[otherId],
                                  tappable: false,
                                )
                              else if (status == 'CANCELLED')
                                const Text(
                                  'Cancelled',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                )
                              else
                                const Text(
                                  'Waiting for someone to match',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                ),
                            ],
                          ),
                          trailing: status == 'OPEN'
                              ? IconButton(
                                  icon: const Icon(Icons.cancel_outlined),
                                  tooltip: 'Cancel request',
                                  onPressed: () async {
                                    await cancelMyRequest(context, r['id']);
                                    load();
                                  },
                                )
                              : status == 'CANCELLED'
                                  ? const Icon(Icons.block, color: Colors.grey)
                                  : const Icon(Icons.chat_bubble_outline),
                          onTap: (status == 'OPEN' || status == 'CANCELLED')
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChatScreen(requestId: r['id']),
                                    ),
                                  );
                                },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
// ---------------- Marketplace ----------------

const List<String> kListingCategories = [
  'Electronics & gadgets',
  'Clothes & apparel',
  'Books & study materials',
  'Furniture & home',
  'Food & drinks',
  'Beauty & personal care',
  'Sports & fitness',
  'Services',
  'Other',
];

const String _filterAll = 'ALL';
const String _filterMine = 'MINE';

String? _nullIfBlank(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

// Turns what a seller typed (a phone number, "instagram.com/me", or a full
// link) into a link the phone can open. Returns null when it is empty.
String? normalizeContactLink(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) return s;

  final digitsOnly = s.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
  if (RegExp(r'^\d{8,15}$').hasMatch(digitsOnly)) {
    var number = digitsOnly;
    if (number.startsWith('00')) {
      number = number.substring(2);
    } else if (number.startsWith('0')) {
      number = '213${number.substring(1)}';
    }
    return 'https://wa.me/$number';
  }
  return 'https://$s';
}

String _priceText(dynamic value) {
  final p = _asDouble(value);
  if (p == null) return '';
  final text = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
  return '$text DA';
}

// All photos of a listing (falls back to the old single photo column).
List<String> listingImages(Map<String, dynamic> l) {
  final urls = <String>[];
  final raw = l['image_urls'];
  if (raw is List) {
    for (final u in raw) {
      final s = u.toString().trim();
      if (s.isNotEmpty) urls.add(s);
    }
  }
  if (urls.isEmpty) {
    final single = (l['image_url'] ?? '').toString().trim();
    if (single.isNotEmpty) urls.add(single);
  }
  return urls;
}

// Swipeable photos with dots. Tapping opens the full-screen viewer.
class ListingPhotoSlider extends StatefulWidget {
  final List<String> urls;
  final double height;
  const ListingPhotoSlider({super.key, required this.urls, this.height = 200});

  @override
  State<ListingPhotoSlider> createState() => _ListingPhotoSliderState();
}

class _ListingPhotoSliderState extends State<ListingPhotoSlider> {
  final PageController controller = PageController();
  int page = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PhotoViewerScreen(urls: urls, initialIndex: i),
                  ),
                );
              },
              child: Image.network(
                urls[i],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.image_not_supported)),
                ),
              ),
            ),
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == page ? Colors.white : Colors.white54,
                      border: Border.all(color: Colors.black26, width: 0.5),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// Full-screen viewer: swipe between photos, pinch to zoom.
class PhotoViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const PhotoViewerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController controller =
      PageController(initialPage: widget.initialIndex);
  late int page = widget.initialIndex;
  bool zoomed = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${page + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: controller,
        physics: zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => page = i),
        itemBuilder: (context, i) => _ZoomableImage(
          url: widget.urls[i],
          onZoomChanged: (z) {
            if (zoomed != z) setState(() => zoomed = z);
          },
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomableImage({required this.url, required this.onZoomChanged});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController controller = TransformationController();
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      final isZoomed = controller.value.getMaxScaleOnAxis() > 1.01;
      if (isZoomed != zoomed) {
        zoomed = isZoomed;
        widget.onZoomChanged(isZoomed);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: controller,
      minScale: 1,
      maxScale: 4,
      panEnabled: zoomed,
      child: Center(
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.image_not_supported,
            color: Colors.white54,
            size: 48,
          ),
        ),
      ),
    );
  }
}

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  List<Map<String, dynamic>> listings = [];
  Map<String, Map<String, dynamic>> sellers = {};
  bool loading = true;
  String? errorMessage;

  final searchController = TextEditingController();
  String searchText = '';
  String selectedFilter = _filterAll;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await supabase
          .from('marketplace_listings')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);
      final loaded = List<Map<String, dynamic>>.from(data);
      final loadedSellers = await fetchPublicProfiles(
        loaded.map((l) => l['seller_id'] as String?),
      );
      if (!mounted) return;
      setState(() {
        listings = loaded;
        sellers = loadedSellers;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Could not load listings: $e';
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get visibleListings {
    final myId = supabase.auth.currentUser!.id;
    final q = searchText.trim().toLowerCase();
    return listings.where((l) {
      final isMine = l['seller_id'] == myId;
      final isSold = l['is_sold'] == true;

      if (selectedFilter == _filterMine) {
        if (!isMine) return false;
      } else {
        if (isSold) return false; // sold items only show under "My listings"
        if (selectedFilter != _filterAll &&
            (l['category'] ?? '').toString().trim() != selectedFilter) {
          return false;
        }
      }

      if (q.isNotEmpty) {
        final haystack =
            '${l['title'] ?? ''} ${l['description'] ?? ''} ${l['category'] ?? ''} ${l['location'] ?? ''}'
                .toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> openContactLink(String? raw) async {
    final link = normalizeContactLink(raw ?? '');
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _snack("Couldn't open that link");
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack("Couldn't open that link");
    } catch (e) {
      _snack("Couldn't open that link");
    }
  }

  Future<void> editListing(Map<String, dynamic> l) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateListingScreen(existing: l)),
    );
    load();
  }

  Future<void> setSold(Map<String, dynamic> l, bool sold) async {
    try {
      await supabase
          .from('marketplace_listings')
          .update({'is_sold': sold}).eq('id', l['id']);
      _snack(sold
          ? 'Marked as sold. Other students can no longer see it.'
          : 'Your listing is available again.');
      load();
    } catch (e) {
      _snack('Could not update: $e');
    }
  }

  Future<void> deleteListing(Map<String, dynamic> l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await supabase.from('marketplace_listings').delete().eq('id', l['id']);
      _snack('Listing deleted.');
      load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  Widget _listingCard(Map<String, dynamic> l) {
    final myId = supabase.auth.currentUser!.id;
    final isMine = l['seller_id'] == myId;
    final isSold = l['is_sold'] == true;
    final images = listingImages(l);
    final description = (l['description'] ?? '').toString().trim();
    final contact = (l['contact_link'] ?? '').toString().trim();
    final details = [
      _priceText(l['price']),
      (l['category'] ?? '').toString().trim(),
      (l['location'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' • ');

    return Opacity(
      opacity: isSold ? 0.65 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty) ListingPhotoSlider(urls: images, height: 200),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (l['title'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isSold)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SOLD',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (isMine)
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              editListing(l);
                            } else if (value == 'sold') {
                              setSold(l, !isSold);
                            } else {
                              deleteListing(l);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'sold',
                              child: Text(isSold
                                  ? 'Mark as available'
                                  : 'Mark as sold'),
                            ),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                    ],
                  ),
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(details,
                          style: const TextStyle(color: Colors.black54)),
                    ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(description,
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: 10),
                  ProfileSummary(profile: sellers[l['seller_id']]),
                  if (contact.isNotEmpty && !isMine) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => openContactLink(contact),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Contact seller'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = visibleListings;
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search listings',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchText.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() => searchText = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in [_filterAll, ...kListingCategories, _filterMine])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f == _filterAll
                          ? 'All'
                          : f == _filterMine
                              ? 'My listings'
                              : f),
                      selected: selectedFilter == f,
                      onSelected: (_) => setState(() => selectedFilter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                          ],
                        )
                      : items.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 100),
                                Center(
                                  child: Text(
                                    selectedFilter == _filterMine
                                        ? 'You have no listings yet.'
                                        : listings.isEmpty
                                            ? 'No listings yet. Be the first!'
                                            : 'No listings match your search.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  _listingCard(items[index]),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateListingScreen()),
          );
          load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateListingScreen extends StatefulWidget {
  // When "existing" is given, the screen edits that listing.
  final Map<String, dynamic>? existing;
  const CreateListingScreen({super.key, this.existing});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final priceController = TextEditingController();
  final contactLinkController = TextEditingController();
  final locationController = TextEditingController();
  String? category;
  bool loading = false;
  bool uploadingImage = false;
  String? errorMessage;

  // Photos already saved on this listing, and newly picked ones.
  List<String> keptUrls = [];
  final List<Uint8List> newPhotos = [];

  bool get isEditing => widget.existing != null;
  int get photoCount => keptUrls.length + newPhotos.length;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      titleController.text = (e['title'] ?? '').toString();
      descriptionController.text = (e['description'] ?? '').toString();
      final price = _asDouble(e['price']);
      priceController.text = price == null
          ? ''
          : (price == price.roundToDouble()
              ? price.toStringAsFixed(0)
              : price.toString());
      locationController.text = (e['location'] ?? '').toString();
      contactLinkController.text = (e['contact_link'] ?? '').toString();
      final c = (e['category'] ?? '').toString().trim();
      category = kListingCategories.contains(c) ? c : null;
      keptUrls = listingImages(e);
    }
  }

  Future<void> addPhoto() async {
    if (photoCount >= 3) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1000,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => newPhotos.add(bytes));
  }

  Future<List<String>> uploadNewPhotos() async {
    final urls = <String>[];
    if (newPhotos.isEmpty) return urls;
    setState(() => uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      for (var i = 0; i < newPhotos.length; i++) {
        final fileName =
            '${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await supabase.storage.from('listings').uploadBinary(
              fileName,
              newPhotos[i],
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        urls.add(supabase.storage.from('listings').getPublicUrl(fileName));
      }
    } finally {
      if (mounted) setState(() => uploadingImage = false);
    }
    return urls;
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      if (titleController.text.trim().isEmpty) {
        setState(() {
          errorMessage = 'Title is required';
          loading = false;
        });
        return;
      }
      if (category == null) {
        setState(() {
          errorMessage = 'Please choose a category';
          loading = false;
        });
        return;
      }

      final priceText = priceController.text.trim().replaceAll(',', '.');
      double? price;
      if (priceText.isNotEmpty) {
        price = double.tryParse(priceText);
        if (price == null || price < 0) {
          setState(() {
            errorMessage = 'Price must be a number';
            loading = false;
          });
          return;
        }
      }

      final uploaded = await uploadNewPhotos();
      final allUrls = [...keptUrls, ...uploaded];

      final values = <String, dynamic>{
        'title': titleController.text.trim(),
        'description': _nullIfBlank(descriptionController.text),
        'price': price,
        'contact_link': normalizeContactLink(contactLinkController.text),
        'location': _nullIfBlank(locationController.text),
        'category': category,
        'image_urls': allUrls,
        'image_url': allUrls.isEmpty ? null : allUrls.first,
      };

      if (isEditing) {
        await supabase
            .from('marketplace_listings')
            .update(values)
            .eq('id', widget.existing!['id']);
      } else {
        await supabase.from('marketplace_listings').insert({
          ...values,
          'seller_id': supabase.auth.currentUser!.id,
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _photoThumb(Widget image, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 100, height: 100, child: image),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit listing' : 'New listing')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Photos ($photoCount/3)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < keptUrls.length; i++)
                    _photoThumb(
                      Image.network(keptUrls[i], fit: BoxFit.cover),
                      () => setState(() => keptUrls.removeAt(i)),
                    ),
                  for (var i = 0; i < newPhotos.length; i++)
                    _photoThumb(
                      Image.memory(newPhotos[i], fit: BoxFit.cover),
                      () => setState(() => newPhotos.removeAt(i)),
                    ),
                  if (photoCount < 3)
                    GestureDetector(
                      onTap: uploadingImage ? null : addPhoto,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 28),
                              SizedBox(height: 4),
                              Text('Add photo',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: kListingCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => category = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              decoration:
                  const InputDecoration(labelText: 'Price in DA (optional)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contactLinkController,
              decoration: const InputDecoration(
                labelText: 'WhatsApp number or contact link',
                hintText: '0555 12 34 56 or instagram.com/yourname',
                helperText:
                    'Numbers starting with 0 become WhatsApp links for Algeria (+213).',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: (loading || uploadingImage) ? null : submit,
              child: Text(loading
                  ? 'Please wait...'
                  : uploadingImage
                      ? 'Uploading photos...'
                      : (isEditing ? 'Save changes' : 'Post listing')),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------- Chat screen (with confirm / dispute / rating) ----------------

class ChatScreen extends StatefulWidget {
  final String requestId;
  const ChatScreen({super.key, required this.requestId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> messagesStream;
  Map<String, dynamic>? request;
  Map<String, dynamic>? otherProfile;
  bool actionLoading = false;

  bool hasRated = false;
  int selectedStars = 5;
  final ratingCommentController = TextEditingController();
  bool ratingLoading = false;

  @override
  void initState() {
    super.initState();
    messagesStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('request_id', widget.requestId)
        .order('created_at');
    loadRequest();
  }

  Future<void> loadRequest() async {
    final data = await supabase
        .from('transaction_requests')
        .select()
        .eq('id', widget.requestId)
        .single();
    if (!mounted) return;
    setState(() => request = data);

    if (otherProfile == null) {
      final myId = supabase.auth.currentUser!.id;
      final otherId = otherPartyId(data, myId);
      if (otherId != null) {
        final profiles = await fetchPublicProfiles([otherId]);
        if (mounted) setState(() => otherProfile = profiles[otherId]);
      }
    }

    if (data['status'] == 'COMPLETED') {
      checkIfRated();
    }
  }

  Future<void> checkIfRated() async {
    final myId = supabase.auth.currentUser!.id;
    final existing = await supabase
        .from('ratings')
        .select()
        .eq('request_id', widget.requestId)
        .eq('rater_id', myId);
    if (mounted) {
      setState(() => hasRated = (existing as List).isNotEmpty);
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    messageController.clear();

    await supabase.from('messages').insert({
      'request_id': widget.requestId,
      'sender_id': supabase.auth.currentUser!.id,
      'type': 'TEXT',
      'content': text,
    });

    // The server finds the other person and sends the notification.
    // If this fails, the chat itself still works.
    try {
      await supabase.functions.invoke('notify-chat-message', body: {
        'request_id': widget.requestId,
        'message': text,
      });
    } catch (e) {
      debugPrint('Push notification error: $e');
    }
  }

  Future<void> confirm(String role) async {
    setState(() => actionLoading = true);
    try {
      await supabase.rpc('confirm_transaction', params: {
        'p_request_id': widget.requestId,
        'p_role': role,
      });
      await loadRequest();
      if (mounted && request?['status'] == 'COMPLETED') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Transaction complete! You can now rate each other.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => actionLoading = false);
    }
  }

  Future<void> openDispute() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report a problem'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: 'Describe what went wrong...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(reasonController.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => actionLoading = true);
    try {
      await supabase.rpc('open_dispute', params: {
        'p_request_id': widget.requestId,
        'p_reason': reason.trim(),
      });
      await loadRequest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispute submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => actionLoading = false);
    }
  }

  Future<void> submitRating() async {
    setState(() => ratingLoading = true);
    try {
      await supabase.rpc('rate_transaction', params: {
        'p_request_id': widget.requestId,
        'p_score': selectedStars,
        'p_comment': ratingCommentController.text.trim().isEmpty
            ? null
            : ratingCommentController.text.trim(),
      });
      if (mounted) {
        setState(() => hasRated = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for rating!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => ratingLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser!.id;
    final r = request;
    final status = r?['status'];
    final iAmCreator = r != null && r['creator_id'] == myId;
    final myRole = (r != null && ((iAmCreator && r['type'] == 'SEND') ||
            (!iAmCreator && r['type'] == 'RECEIVE')))
        ? 'SENDER'
        : 'RECEIVER';
    final iHaveConfirmed = r != null &&
        ((myRole == 'SENDER' && r['sender_confirmed'] == true) ||
            (myRole == 'RECEIVER' && r['receiver_confirmed'] == true));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (status != null && status != 'COMPLETED' && status != 'DISPUTED')
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Report a problem',
              onPressed: actionLoading ? null : openDispute,
            ),
        ],
      ),
      body: Column(
        children: [
          if (otherProfile != null) ...[
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: ProfileSummary(profile: otherProfile),
            ),
            const Divider(height: 1),
          ],
          if (status == 'COMPLETED')
            Container(
              width: double.infinity,
              color: Colors.green.shade100,
              padding: const EdgeInsets.all(12),
              child: hasRated
                  ? const Text('✅ Transaction completed — thanks for rating!',
                      textAlign: TextAlign.center)
                  : Column(
                      children: [
                        const Text('✅ Transaction completed',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        const Text('Rate the other person:'),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) {
                            final starValue = i + 1;
                            return IconButton(
                              icon: Icon(
                                starValue <= selectedStars
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                              ),
                              onPressed: () =>
                                  setState(() => selectedStars = starValue),
                            );
                          }),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          child: TextField(
                            controller: ratingCommentController,
                            decoration: const InputDecoration(
                              hintText: 'Optional comment...',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: ratingLoading ? null : submitRating,
                          child: Text(
                              ratingLoading ? 'Submitting...' : 'Submit rating'),
                        ),
                      ],
                    ),
            )
          else if (status == 'DISPUTED')
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text('⚠️ Dispute opened on this transaction',
                  textAlign: TextAlign.center),
            )
          else if (status != null)
            Container(
              width: double.infinity,
              color: Colors.teal.shade50,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    iHaveConfirmed
                        ? 'You confirmed. Waiting for the other side...'
                        : 'Once the exchange is done outside the app, confirm here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: (actionLoading || iHaveConfirmed)
                        ? null
                        : () => confirm(myRole),
                    child: Text(myRole == 'SENDER'
                        ? "I sent the money"
                        : "I received the money"),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi!'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isSystem = m['type'] == 'SYSTEM';
                    final isMine = m['sender_id'] == myId;
                    if (isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Text(
                            m['content'] ?? '',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      );
                    }
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.teal.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m['content'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (status != 'COMPLETED' && status != 'DISPUTED')
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: sendMessage,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// ---------------- Exchange rates ----------------

String _fmtRate(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

double? _rateMid(Map<String, dynamic> row) {
  final buy = _asDouble(row['buy_rate']);
  final sell = _asDouble(row['sell_rate']);
  if (buy == null || sell == null) return null;
  return (buy + sell) / 2;
}

String _updatedAgo(DateTime? d) {
  if (d == null) return 'unknown';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} days ago';
}

class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key});

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  // pair -> source -> newest row
  Map<String, Map<String, Map<String, dynamic>>> rates = {};
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await supabase
          .from('exchange_rates')
          .select()
          .order('updated_at', ascending: false);
      final rows = List<Map<String, dynamic>>.from(data);

      final grouped = <String, Map<String, Map<String, dynamic>>>{};
      for (final row in rows) {
        final pair = row['pair'].toString();
        final source = row['source'].toString();
        grouped.putIfAbsent(pair, () => {});
        // rows arrive newest-first, so keep the first one per source
        grouped[pair]!.putIfAbsent(source, () => row);
      }

      if (!mounted) return;
      setState(() {
        rates = grouped;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Could not load rates: $e';
        loading = false;
      });
    }
  }

  Widget _rateRow(String label, Map<String, dynamic>? row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label)),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? '—' : _fmtRate(_asDouble(row['buy_rate'])),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? '—' : _fmtRate(_asDouble(row['sell_rate'])),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairCard(String pair, Map<String, Map<String, dynamic>> bySource) {
    final bank = bySource['bank'];
    final market = bySource['black_market'];

    String? gapText;
    if (bank != null && market != null) {
      final bankMid = _rateMid(bank);
      final marketMid = _rateMid(market);
      if (bankMid != null && marketMid != null && bankMid > 0) {
        final gap = (marketMid - bankMid) / bankMid * 100;
        gapText =
            'Parallel market is ${gap.abs().toStringAsFixed(0)}% ${gap >= 0 ? 'higher' : 'lower'} than the bank';
      }
    }

    DateTime? newest;
    for (final row in [bank, market]) {
      final d = DateTime.tryParse(row?['updated_at']?.toString() ?? '');
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pair.replaceAll('/', ' → '),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(flex: 3, child: Text('')),
                Expanded(
                  flex: 2,
                  child: Text('Buy',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.black54, fontSize: 12)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Sell',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.black54, fontSize: 12)),
                ),
              ],
            ),
            _rateRow('Bank', bank),
            _rateRow('Parallel market', market),
            if (gapText != null) ...[
              const SizedBox(height: 8),
              Text(gapText, style: const TextStyle(color: Colors.deepOrange)),
            ],
            const SizedBox(height: 8),
            Text(
              'Updated ${_updatedAgo(newest)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairs = rates.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Exchange rates')),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  )
                : pairs.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 100),
                          Center(child: Text('No rates available yet.')),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final pair in pairs)
                            _pairCard(pair, rates[pair]!),
                          const Text(
                            'Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. These rates are indicative and updated by hand, so always agree the exact rate with the other person before exchanging anything.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
      ),
    );
  }
}
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
        errorMessage = 'Could not load: $e';
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
      setState(() => errorMessage = 'Choose a photo of your student card first');
      return;
    }
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
      setState(() => errorMessage = 'Could not send: $e');
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
            children: const [
              Icon(Icons.verified, size: 64, color: Colors.blue),
              SizedBox(height: 12),
              Text('You are verified',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                'Other users can see the blue tick next to your name.',
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
              const Icon(Icons.hourglass_top, size: 64, color: Colors.orange),
              const SizedBox(height: 12),
              const Text('Under review',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'We received your student card and will check it soon. You will see a blue tick here once it is approved.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: load, child: const Text('Check again')),
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
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  note.isEmpty
                      ? 'Your last request was not approved. You can send a new photo.'
                      : 'Your last request was not approved: $note',
                ),
              ),
            ),
          const Text(
            'A blue tick tells other students that we checked your student card.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Send a clear photo of your student card. Your name and student number must be readable and must match your account. Only the UniBridge team can view this photo. It is used for this check and is never shown to other users.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: submitting ? null : pickCard,
            child: Container(
              height: 190,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: cardBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(cardBytes!, fit: BoxFit.cover),
                    )
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined, size: 40),
                          SizedBox(height: 6),
                          Text('Tap to choose a photo of your student card'),
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
                  style: const TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: submitting ? null : submit,
            child: Text(submitting ? 'Sending...' : 'Send for review'),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Get verified')),
      body: body,
    );
  }
}
// ---------------- Cancel my request ----------------

Future<void> cancelMyRequest(BuildContext context, String requestId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel this request?'),
      content: const Text('It will no longer be visible to other users.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Cancel request'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await supabase.rpc('cancel_request', params: {'p_request_id': requestId});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e')),
      );
    }
  }
}

// ---------------- Notifications (bell + inbox) ----------------

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unread = 0;
  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    loadCount();
    // Refresh the number when a push arrives while the app is open.
    _sub = FirebaseMessaging.onMessage.listen((_) => loadCount());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> loadCount() async {
    try {
      final data = await supabase
          .from('notifications')
          .select('id')
          .eq('is_read', false);
      if (!mounted) return;
      setState(() => unread = (data as List).length);
    } catch (e) {
      debugPrint('Could not load notification count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        label: Text(unread > 9 ? '9+' : '$unread'),
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        loadCount();
      },
    );
  }
}

IconData _notificationIcon(String type) {
  switch (type) {
    case 'MATCH_FOUND':
      return Icons.people_outline;
    case 'CONFIRMATION_NEEDED':
      return Icons.pending_actions;
    case 'TRANSACTION_COMPLETED':
      return Icons.check_circle_outline;
    case 'DISPUTE_OPENED':
      return Icons.report_problem_outlined;
    case 'VERIFIED_BADGE_AWARDED':
      return Icons.verified_outlined;
    default:
      return Icons.notifications_none;
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      final loaded = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      setState(() {
        items = loaded;
        loading = false;
      });

      // The unread dots stay visible on this screen, and everything is
      // marked as read once the person has seen the list.
      if (loaded.any((n) => n['is_read'] != true)) {
        await supabase
            .from('notifications')
            .update({'is_read': true}).eq('is_read', false);
      }
    } catch (e) {
      debugPrint('Could not load notifications: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No notifications yet.')),
                    ],
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = items[index];
                      final isUnread = n['is_read'] != true;
                      return ListTile(
                        leading: Icon(_notificationIcon('${n['type']}')),
                        title: Text(
                          '${n['content']}',
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(_updatedAgo(
                            DateTime.tryParse('${n['created_at']}'))),
                        trailing: isUnread
                            ? const Icon(Icons.circle,
                                size: 10, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const MyRequestsScreen()),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}


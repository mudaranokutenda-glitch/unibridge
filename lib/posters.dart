import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'app_theme.dart';
import 'student_space.dart' show showSnack, shortDate;
import 'l10n.dart';
import 'errors.dart';

// WhatsApp link with a ready message, or null when the poster has no number.
Uri? posterWhatsAppUri(Map<String, dynamic> p) {
  final n = (p['contact_whatsapp'] ?? '').toString();
  if (!RegExp(r'^[0-9]{8,15}$').hasMatch(n)) return null;
  return Uri.parse('https://wa.me/$n').replace(queryParameters: {
    'text': tr('Hello, I saw your poster "{title}" on AZSA.', {'title': '${p['title']}'}),
  });
}

// The business's website (or other link), or null.
Uri? posterLinkUri(Map<String, dynamic> p) {
  final l = (p['link_url'] ?? '').toString();
  if (!RegExp(r'^https?://').hasMatch(l)) return null;
  return Uri.tryParse(l);
}

// ---------------- E2. Sliding posters at the top of the Requests tab ----------------
// The database only returns posters that are active and between their start
// and end dates (sql/2026-11-05-07-posters.sql). Hidden when there are none.

class PosterCarousel extends StatefulWidget {
  // Time between two automatic slides.
  final Duration interval;
  const PosterCarousel({super.key, this.interval = const Duration(seconds: 3)});

  @override
  State<PosterCarousel> createState() => _PosterCarouselState();
}

class _PosterCarouselState extends State<PosterCarousel> {
  // With 2+ posters the PageView has very many pages that repeat the
  // posters, so "next" after the last poster slides forward to the first.
  static const int _loopPages = 10000;

  PageController? controller;
  List<Map<String, dynamic>> posters = [];
  int page = 0; // index of the poster shown (0 .. posters.length - 1)
  Timer? slideTimer;
  Timer? resumeTimer;
  bool touching = false;

  bool get loops => posters.length > 1;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    slideTimer?.cancel();
    resumeTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final data = await supabase
          .from('posters')
          .select()
          .eq('active', true)
          .lte('starts_on', today)
          .gte('ends_on', today)
          .order('position');
      if (!mounted) return;
      final loaded = List<Map<String, dynamic>>.from(data);
      controller?.dispose();
      setState(() {
        posters = loaded;
        page = 0;
        // Start in the middle so the user can also swipe backwards.
        controller = PageController(
            initialPage: loops ? (_loopPages ~/ 2) * posters.length : 0);
      });
      startAutoSlide();
    } catch (e) {
      // Before the posters SQL is run there is simply no carousel.
      debugPrint('Could not load posters: $e');
    }
  }

  void startAutoSlide() {
    slideTimer?.cancel();
    if (!loops || touching) return;
    slideTimer = Timer.periodic(widget.interval, (_) {
      final c = controller;
      if (c == null || !c.hasClients || touching) return;
      c.nextPage(
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  // Finger down: stop sliding. Finger up: start again after one interval.
  void onTouchStart() {
    touching = true;
    slideTimer?.cancel();
    resumeTimer?.cancel();
  }

  void onTouchEnd() {
    touching = false;
    resumeTimer?.cancel();
    resumeTimer = Timer(widget.interval, () {
      if (mounted) startAutoSlide();
    });
  }

  // Opens WhatsApp (with a ready message) or the business's website.
  Future<void> openContact(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, tr('Could not open the link.'));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not open the link.'));
    }
  }

  // The bar at the bottom of a poster: title + Contact button(s).
  Widget contactBar(Map<String, dynamic> p) {
    final whatsapp = posterWhatsAppUri(p);
    final link = posterLinkUri(p);
    if (whatsapp == null && link == null) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final both = whatsapp != null && link != null;
    Widget button(
        {required IconData icon,
        required String label,
        required Color bg,
        required Color fg,
        required Uri uri}) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: Material(
          color: bg,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => openContact(uri),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 18, 8, 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${p['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            if (whatsapp != null)
              button(
                  icon: Icons.chat,
                  label: both ? 'WhatsApp' : tr('Contact'),
                  bg: const Color(0xFF25D366),
                  fg: Colors.white,
                  uri: whatsapp),
            if (link != null)
              button(
                  icon: Icons.open_in_new,
                  label: both ? tr('Website') : tr('Contact'),
                  bg: Colors.white,
                  fg: AppColors.text,
                  uri: link),
          ],
        ),
      ),
    );
  }

  Future<void> openPoster(Map<String, dynamic> p) async {
    final link = (p['link_url'] ?? '').toString();
    if (link.isNotEmpty) {
      final ok = await launchUrl(Uri.parse(link),
          mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${p['title']}')),
        body: Center(
          child: InteractiveViewer(child: Image.network('${p['image_url']}')),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (posters.isEmpty || c == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              // Listener only watches the finger; taps and swipes still work.
              child: Listener(
                onPointerDown: (_) => onTouchStart(),
                onPointerUp: (_) => onTouchEnd(),
                onPointerCancel: (_) => onTouchEnd(),
                child: PageView.builder(
                  controller: c,
                  itemCount: loops ? _loopPages * posters.length : 1,
                  onPageChanged: (i) =>
                      setState(() => page = i % posters.length),
                  itemBuilder: (context, i) {
                    final p = posters[i % posters.length];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: () => openPoster(p),
                          child: Image.network(
                            '${p['image_url']}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: kPlaceholderBg,
                              alignment: Alignment.center,
                              child: Text('${p['title']}'),
                            ),
                          ),
                        ),
                        if (p['is_ad'] == true)
                          PositionedDirectional(
                            top: 8,
                            start: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(tr('Ad'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        contactBar(p),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (loops)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < posters.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == page ? 16 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == page
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- E3. Add, order and remove posters (attache, admin) ----------------

class ManagePostersScreen extends StatefulWidget {
  const ManagePostersScreen({super.key});

  @override
  State<ManagePostersScreen> createState() => _ManagePostersScreenState();
}

class _ManagePostersScreenState extends State<ManagePostersScreen> {
  List<Map<String, dynamic>> posters = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await supabase
          .from('posters')
          .select()
          .order('active', ascending: false)
          .order('position');
      if (!mounted) return;
      setState(() {
        posters = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showSnack(context, tr('Could not load: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  Future<void> edit([Map<String, dynamic>? poster]) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditPosterScreen(poster: poster),
    ));
    load();
  }

  Future<void> delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this poster?')),
        content: Text('${p['title']}'),
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
      await supabase.from('posters').delete().eq('id', p['id']);
      await supabase.storage.from('posters').remove([p['image_path']]);
      await load();
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': friendlyError(e, short: true)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = posters.where((p) => p['active'] == true).length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Posters'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        tooltip: tr('Add poster'),
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr(
                      '{count} of 4 active. Each active poster has its own position (1 is shown first). Images should be 16:9.',
                      {'count': activeCount})),
                ),
                for (final p in posters)
                  ListTile(
                    leading: SizedBox(
                      width: 80,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network('${p['image_url']}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: kPlaceholderBg)),
                      ),
                    ),
                    title: Text('${p['title']}'),
                    subtitle: Text(
                        '${p['active'] == true ? tr('Active, position {n}', {'n': p['position']}) : tr('Not active')}'
                        ' · ${shortDate(p['starts_on'])} → ${shortDate(p['ends_on'])}'),
                    onTap: () => edit(p),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: tr('Delete'),
                      onPressed: () => delete(p),
                    ),
                  ),
              ],
            ),
    );
  }
}

class EditPosterScreen extends StatefulWidget {
  final Map<String, dynamic>? poster;
  const EditPosterScreen({super.key, this.poster});

  @override
  State<EditPosterScreen> createState() => _EditPosterScreenState();
}

class _EditPosterScreenState extends State<EditPosterScreen> {
  final title = TextEditingController();
  final link = TextEditingController();
  final whatsapp = TextEditingController();
  bool isAd = false;
  late DateTime startsOn;
  late DateTime endsOn;
  int position = 1;
  bool active = true;
  Uint8List? newImage;
  bool saving = false;

  Map<String, dynamic>? get p => widget.poster;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    title.text = '${p?['title'] ?? ''}';
    link.text = '${p?['link_url'] ?? ''}';
    whatsapp.text = '${p?['contact_whatsapp'] ?? ''}';
    isAd = p?['is_ad'] == true;
    startsOn = DateTime.tryParse('${p?['starts_on']}') ??
        DateTime(now.year, now.month, now.day);
    endsOn = DateTime.tryParse('${p?['ends_on']}') ??
        startsOn.add(const Duration(days: 30));
    position = (p?['position'] as int?) ?? 1;
    active = p?['active'] != false;
  }

  String day(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) showSnack(context, tr('This photo is too big (max 5 MB).'));
      return;
    }
    setState(() => newImage = bytes);
  }

  Future<void> pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? startsOn : endsOn,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        startsOn = picked;
        if (endsOn.isBefore(startsOn)) endsOn = startsOn;
      } else {
        endsOn = picked;
      }
    });
  }

  Future<void> save() async {
    final linkText = link.text.trim();
    if (title.text.trim().isEmpty) {
      showSnack(context, tr('Write a title.'));
      return;
    }
    if (p == null && newImage == null) {
      showSnack(context, tr('Choose an image.'));
      return;
    }
    if (linkText.isNotEmpty && !RegExp(r'^https?://').hasMatch(linkText)) {
      showSnack(context, tr('The link must start with https://'));
      return;
    }
    // WhatsApp number: digits only, with the country code (213..., 263...).
    var wa = whatsapp.text.replaceAll(RegExp(r'[\s\-().]'), '');
    if (wa.startsWith('+')) wa = wa.substring(1);
    if (wa.startsWith('00')) wa = wa.substring(2);
    if (wa.isNotEmpty) {
      if (wa.startsWith('0')) {
        showSnack(context,
            tr('Add the country code to the WhatsApp number, for example 213 for Algeria or 263 for Zimbabwe.'));
        return;
      }
      if (!RegExp(r'^[0-9]{8,15}$').hasMatch(wa)) {
        showSnack(context, tr('Check the WhatsApp number (8 to 15 digits).'));
        return;
      }
    }
    setState(() => saving = true);
    String? uploadedPath;
    try {
      final values = <String, dynamic>{
        'title': title.text.trim(),
        'link_url': linkText.isEmpty ? null : linkText,
        'contact_whatsapp': wa.isEmpty ? null : wa,
        'is_ad': isAd,
        'starts_on': day(startsOn),
        'ends_on': day(endsOn),
        'position': position,
        'active': active,
      };
      if (newImage != null) {
        uploadedPath = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('posters').uploadBinary(
              uploadedPath,
              newImage!,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        values['image_path'] = uploadedPath;
        values['image_url'] =
            supabase.storage.from('posters').getPublicUrl(uploadedPath);
      }
      if (p == null) {
        await supabase.from('posters').insert(values);
      } else {
        await supabase.from('posters').update(values).eq('id', p!['id']);
        // The old image is no longer used.
        if (uploadedPath != null) {
          await supabase.storage.from('posters').remove([p!['image_path']]);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (uploadedPath != null) {
        await supabase.storage.from('posters').remove([uploadedPath]);
      }
      if (!mounted) return;
      // 23505 = another active poster already has this position.
      showSnack(
          context,
          e.code == '23505'
              ? tr('Another active poster already uses position {n}. Choose another position or turn that poster off first.',
                  {'n': position})
              : tr('Could not save: {error}', {'error': e.message}));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not save: {error}', {'error': friendlyError(e, short: true)}));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? tr('Add poster') : tr('Edit poster'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: saving ? null : pickImage,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: newImage != null
                    ? Image.memory(newImage!, fit: BoxFit.cover)
                    : p != null
                        ? Image.network('${p!['image_url']}', fit: BoxFit.cover)
                        : Container(
                            color: kPlaceholderBg,
                            alignment: Alignment.center,
                            child: Text(tr('Tap to choose an image (16:9)')),
                          ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            maxLength: 120,
            decoration: InputDecoration(labelText: tr('Title')),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
                tr('Contact (optional): a "Contact" button appears on the poster.'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          TextField(
            controller: whatsapp,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: tr('WhatsApp number (optional)'),
              hintText: '213555123456',
              helperText: tr('With the country code, without + (213 Algeria, 263 Zimbabwe).'),
              prefixIcon: const Icon(Icons.chat_outlined),
            ),
          ),
          TextField(
            controller: link,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Website or other link (optional)'),
              hintText: 'https://',
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => pickDate(true),
                  child: Text(tr('Start: {d}', {'d': day(startsOn)})),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => pickDate(false),
                  child: Text(tr('End: {d}', {'d': day(endsOn)})),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: position,
            decoration: InputDecoration(labelText: tr('Position')),
            items: [
              for (var i = 1; i <= 4; i++)
                DropdownMenuItem(value: i, child: Text('$i')),
            ],
            onChanged: (v) => setState(() => position = v ?? position),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('This is an advert')),
            subtitle: Text(tr('Shows a small "Ad" label on the poster.')),
            value: isAd,
            onChanged: (v) => setState(() => isAd = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Active')),
            value: active,
            onChanged: (v) => setState(() => active = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: saving ? null : save,
            child: Text(saving ? tr('Saving...') : tr('Save')),
          ),
        ],
      ),
    );
  }
}

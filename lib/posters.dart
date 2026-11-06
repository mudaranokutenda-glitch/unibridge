import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'student_space.dart' show showSnack, shortDate;
import 'l10n.dart';

// ---------------- E2. Sliding posters at the top of the Requests tab ----------------
// The database only returns posters that are active and between their start
// and end dates (sql/2026-11-05-07-posters.sql). Hidden when there are none.

class PosterCarousel extends StatefulWidget {
  const PosterCarousel({super.key});

  @override
  State<PosterCarousel> createState() => _PosterCarouselState();
}

class _PosterCarouselState extends State<PosterCarousel> {
  final controller = PageController();
  List<Map<String, dynamic>> posters = [];
  int page = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
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
      setState(() => posters = List<Map<String, dynamic>>.from(data));
      startTimer();
    } catch (e) {
      // Before the posters SQL is run there is simply no carousel.
      debugPrint('Could not load posters: $e');
    }
  }

  // Slides by itself every 4 seconds. Restarts after the user swipes.
  void startTimer() {
    timer?.cancel();
    if (posters.length < 2) return;
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!controller.hasClients) return;
      final next = (page + 1) % posters.length;
      controller.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
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
    if (posters.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null) startTimer();
                  return false;
                },
                child: PageView.builder(
                  controller: controller,
                  itemCount: posters.length,
                  onPageChanged: (i) => setState(() => page = i),
                  itemBuilder: (context, i) {
                    final p = posters[i];
                    return GestureDetector(
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
                    );
                  },
                ),
              ),
            ),
          ),
          if (posters.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < posters.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
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
      showSnack(context, tr('Could not load: {error}', {'error': e}));
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
      if (mounted) showSnack(context, tr('Could not delete: {error}', {'error': e}));
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
    setState(() => saving = true);
    String? uploadedPath;
    try {
      final values = <String, dynamic>{
        'title': title.text.trim(),
        'link_url': linkText.isEmpty ? null : linkText,
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
      if (mounted) showSnack(context, tr('Could not save: {error}', {'error': e}));
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
          TextField(
            controller: link,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
                labelText: tr('Link (optional)'), hintText: 'https://'),
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

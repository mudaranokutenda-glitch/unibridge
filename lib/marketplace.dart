import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'app_theme.dart';
import 'profiles.dart';
import 'l10n.dart';
import 'errors.dart';
import 'notifications.dart';

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

String _filterLabel(String f) {
  if (f == _filterAll) return tr('All');
  if (f == _filterMine) return tr('My listings');
  return tr(f); // category names are saved in English, shown translated
}

IconData _filterIcon(String f) {
  if (f == _filterAll) return Icons.apps;
  if (f == _filterMine) return Icons.person_outline;
  return Icons.label_outline;
}

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
  final p = asDouble(value);
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

Future<void> openContactLinkFor(BuildContext context, String? raw) async {
  final link = normalizeContactLink(raw ?? '');
  if (link == null) return;
  final uri = Uri.tryParse(link);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr("Couldn't open that link"))),
    );
  }
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
                  color: kPlaceholderBg,
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

// ---------------- Marketplace list (2-column grid) ----------------

class MarketplaceScreen extends StatefulWidget {
  // The home screen bumps this each time the Marketplace tab is opened,
  // so new items appear without pulling down.
  final ValueListenable<int>? reloadSignal;
  const MarketplaceScreen({super.key, this.reloadSignal});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
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
    widget.reloadSignal?.addListener(reloadQuietly);
    load();
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(reloadQuietly);
    searchController.dispose();
    super.dispose();
  }

  void reloadQuietly() {
    if (mounted) load(quiet: true);
  }

  // quiet = keep the list on screen while loading (no spinner).
  Future<void> load({bool quiet = false}) async {
    setState(() {
      if (!quiet) loading = true;
      errorMessage = null;
    });
    try {
      final data = await supabase
          .from('marketplace_listings')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);
      // Hide listings from people I blocked or who blocked me.
      final hidden = await fetchHiddenUserIds();
      final loaded = List<Map<String, dynamic>>.from(data)
          .where((l) => !hidden.contains(l['seller_id']))
          .toList();
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
        errorMessage = tr('Could not load listings: {error}', {'error': friendlyError(e, short: true)});
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
        if (isSold) return false; // sold items only show under tr("My listings")
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

  Future<void> _openDetail(Map<String, dynamic> l) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(
          listing: l,
          seller: sellers[l['seller_id']],
        ),
      ),
    );
    load();
  }

  Widget _sellerLine(Map<String, dynamic>? p) {
    final name = p == null ? tr('Seller') : publicDisplayName(p);
    final verified = p?['is_verified'] == true;
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: kMutedText),
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 4),
          const Icon(Icons.verified, size: 14, color: AppColors.verified),
        ],
      ],
    );
  }

  Widget _gridCard(Map<String, dynamic> l) {
    final isSold = l['is_sold'] == true;
    final images = listingImages(l);
    final price = _priceText(l['price']);
    final seller = sellers[l['seller_id']];

    return Opacity(
      opacity: isSold ? 0.65 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDetail(l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (images.isEmpty)
                      Container(
                        color: kPlaceholderBg,
                        child: const Center(
                          child: Icon(Icons.shopping_bag_outlined,
                              size: 40, color: Colors.grey),
                        ),
                      )
                    else
                      Image.network(
                        images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                          color: kPlaceholderBg,
                          child: const Center(
                              child: Icon(Icons.image_not_supported)),
                        ),
                      ),
                    if (isSold)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tr('SOLD'),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ),
                      ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_outlined,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '${images.length}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (l['title'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price.isEmpty ? tr('Price on request') : price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    _sellerLine(seller),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(String f) {
    return ListTile(
      leading: Icon(_filterIcon(f)),
      title: Text(_filterLabel(f)),
      selected: selectedFilter == f,
      onTap: () {
        setState(() => selectedFilter = f);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = visibleListings;
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        title: Text(tr('Marketplace')),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: tr('Categories'),
            onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  tr('Categories'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              _drawerItem(_filterAll),
              const Divider(),
              for (final c in kListingCategories) _drawerItem(c),
              const Divider(),
              _drawerItem(_filterMine),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: tr('Search listings'),
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
          if (selectedFilter != _filterAll)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Showing: {filter}', {'filter': _filterLabel(selectedFilter)}),
                      style: const TextStyle(color: kMutedText),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => selectedFilter = _filterAll),
                    child: Text(tr('Show all')),
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
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(color: AppColors.cancelled),
                                ),
                              ),
                            ),
                          ],
                        )
                      : items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 100),
                                Center(
                                  child: Text(
                                    selectedFilter == _filterMine
                                        ? tr('You have no listings yet.')
                                        : listings.isEmpty
                                            ? tr('No listings yet. Be the first!')
                                            : tr('No listings match your search.'),
                                  ),
                                ),
                              ],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                mainAxisExtent: 250,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  _gridCard(items[index]),
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

// ---------------- One listing, full page ----------------

class ListingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> listing;
  final Map<String, dynamic>? seller;
  const ListingDetailScreen({super.key, required this.listing, this.seller});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  bool busy = false;

  Map<String, dynamic> get l => widget.listing;
  bool get isMine => l['seller_id'] == supabase.auth.currentUser!.id;
  bool get isSold => l['is_sold'] == true;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateListingScreen(existing: l)),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _toggleSold() async {
    setState(() => busy = true);
    try {
      await supabase
          .from('marketplace_listings')
          .update({'is_sold': !isSold}).eq('id', l['id']);
      _snack(isSold
          ? tr('Your listing is available again.')
          : tr('Marked as sold. Other students can no longer see it.'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack(tr('Could not update: {error}', {'error': friendlyError(e, short: true)}));
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Delete this listing?')),
        content: Text(tr('This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('Keep it')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => busy = true);
    try {
      await supabase.from('marketplace_listings').delete().eq('id', l['id']);
      _snack(tr('Listing deleted.'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack(tr('Could not delete: {error}', {'error': friendlyError(e, short: true)}));
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = listingImages(l);
    final price = _priceText(l['price']);
    final description = (l['description'] ?? '').toString().trim();
    final contact = (l['contact_link'] ?? '').toString().trim();
    final sellerId = l['seller_id']?.toString();
    final seller = widget.seller;
    final details = [
      tr((l['category'] ?? '').toString().trim()),
      (l['location'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' • ');

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Listing')),
        actions: [
          if (isMine)
            PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (value) {
                if (value == 'edit') {
                  _edit();
                } else if (value == 'sold') {
                  _toggleSold();
                } else {
                  _delete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                PopupMenuItem(
                  value: 'sold',
                  child: Text(isSold ? tr('Mark as available') : tr('Mark as sold')),
                ),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
        ],
      ),
      body: ListView(
        children: [
          if (images.isNotEmpty)
            ListingPhotoSlider(urls: images, height: 300)
          else
            Container(
              height: 160,
              color: kPlaceholderBg,
              child: const Center(
                child: Icon(Icons.shopping_bag_outlined,
                    size: 48, color: Colors.grey),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (l['title'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
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
                        child: Text(
                          tr('SOLD'),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  price.isEmpty ? tr('Price on request') : price,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(details,
                        style: const TextStyle(color: kMutedText)),
                  ),
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(description),
                  ),
                const Divider(height: 32),
                InkWell(
                  onTap: sellerId == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(userId: sellerId),
                            ),
                          );
                        },
                  child: Row(
                    children: [
                      avatar(seller, radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    seller == null
                                        ? tr('Seller')
                                        : publicDisplayName(seller),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (seller?['is_verified'] == true) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified,
                                      size: 16, color: AppColors.sky),
                                ],
                              ],
                            ),
                            if (seller != null &&
                                profilePlace(seller).isNotEmpty)
                              Text(
                                profilePlace(seller),
                                style: const TextStyle(
                                    fontSize: 12, color: kMutedText),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
                if (contact.isNotEmpty && !isMine) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => openContactLinkFor(context, contact),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(tr('Contact seller')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Create / edit a listing ----------------

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
      final price = asDouble(e['price']);
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

  // Lets the seller pick several photos in one go (up to the free slots).
  Future<void> addPhotos() async {
    final remaining = 3 - photoCount;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    List<XFile> picked;
    if (remaining == 1) {
      final one = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1000,
      );
      picked = one == null ? [] : [one];
    } else {
      picked = await picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1000,
        limit: remaining,
      );
    }
    if (picked.isEmpty) return;

    final chosen = picked.take(remaining).toList();
    final bytes = <Uint8List>[];
    for (final x in chosen) {
      bytes.add(await x.readAsBytes());
    }
    if (!mounted) return;
    setState(() => newPhotos.addAll(bytes));
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Only 3 photos are allowed per listing.'))),
      );
    }
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
          errorMessage = tr('Title is required');
          loading = false;
        });
        return;
      }
      if (category == null) {
        setState(() {
          errorMessage = tr('Please choose a category');
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
            errorMessage = tr('Price must be a number');
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
      setState(() => errorMessage = friendlyError(e));
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
      appBar: AppBar(title: Text(isEditing ? tr('Edit listing') : tr('New listing'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(tr('Photos ({count}/3)', {'count': photoCount}),
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
                      onTap: uploadingImage ? null : addPhotos,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: kPlaceholderBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 28),
                              SizedBox(height: 4),
                              Text(tr('Add photos'),
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
              decoration: InputDecoration(labelText: tr('Title *')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: InputDecoration(labelText: tr('Category *')),
              items: kListingCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(tr(c))))
                  .toList(),
              onChanged: (v) => setState(() => category = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(labelText: tr('Description')),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              decoration:
                  InputDecoration(labelText: tr('Price in DA (optional)')),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              decoration: InputDecoration(labelText: tr('Location')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contactLinkController,
              decoration: InputDecoration(
                labelText: tr('WhatsApp number or contact link'),
                hintText: tr('0555 12 34 56 or instagram.com/yourname'),
                helperText:
                    tr('Numbers starting with 0 become WhatsApp links for Algeria (+213).'),
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: AppColors.cancelled)),
              ),
            ElevatedButton(
              onPressed: (loading || uploadingImage) ? null : submit,
              child: Text(loading
                  ? tr('Please wait...')
                  : uploadingImage
                      ? tr('Uploading photos...')
                      : (isEditing ? tr('Save changes') : tr('Post listing'))),
            ),
          ],
        ),
      ),
    );
  }
}

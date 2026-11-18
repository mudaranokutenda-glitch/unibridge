import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';

// ---------------- Icons: your own PNG files, or a Material icon ----------------
// If the file assets/icons/<name>.png exists, it is used. If it does not, the
// Material icon is shown instead. Names used by the app:
//   rates, marketplace, student_space, profile
// Size: PNG, 128 x 128 pixels, transparent background (see assets/icons/README.txt).

class AppAssets {
  AppAssets._();

  static Set<String> _files = {};

  // Called once when the app starts: reads the list of files that are inside the app.
  static Future<void> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _files = manifest.listAssets().toSet();
    } catch (e) {
      debugPrint('Could not read the asset list: $e');
      _files = {};
    }
  }

  static bool has(String path) => _files.contains(path);
}

class AppIcon extends StatelessWidget {
  // File name without ".png", for example 'rates'.
  final String name;
  // Shown when there is no PNG file.
  final IconData fallback;
  final double size;
  final Color? color;
  // No PNG file: draw the Material icon on a coloured circle.
  final bool circle;

  const AppIcon({
    super.key,
    required this.name,
    required this.fallback,
    this.size = 24,
    this.color,
    this.circle = false,
  });

  String get path => 'assets/icons/$name.png';

  @override
  Widget build(BuildContext context) {
    final icon = Icon(fallback, size: size, color: color);
    if (!AppAssets.has(path)) {
      return circle ? IconCircle(icon: fallback, size: size * 1.6, color: color) : icon;
    }
    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => icon,
    );
  }
}

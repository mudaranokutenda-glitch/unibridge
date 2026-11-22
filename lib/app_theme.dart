import 'package:flutter/material.dart';

// ---------------- The look of AZSA (one file) ----------------
// Colours, radii, spacing and the light / dark theme are all here.
// To change the look of the whole app, change the numbers in this file.
// The font is the system font for now.

class AppColors {
  AppColors._();

  // Main colour: sky blue.
  static const Color sky = Color(0xFF2F80ED);
  static const Color skyDark = Color(0xFF1F63C2);
  static const Color skyLight = Color(0xFFDCE9FF); // soft blue (chips, icon circles)
  static const Color skyPale = Color(0xFFEAF2FF);

  // Light mode.
  static const Color background = Color(0xFFF4F8FF);
  static const Color card = Colors.white;
  static const Color text = Color(0xFF14233B);
  static const Color mutedText = Color(0xFF6B7A90);

  // Dark mode.
  static const Color darkBackground = Color(0xFF0E1726);
  static const Color darkCard = Color(0xFF16233A);
  static const Color darkSky = Color(0xFF6AA6FF); // sky blue that reads well on dark

  // Meaning colours (the same in light and dark).
  static const Color verified = Color(0xFFD4AF37); // gold
  static const Color cancelled = Color(0xFFD64545); // red
  static const Color expired = Color(0xFF8A8A8A); // grey
  static const Color success = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFE08A1E);
}

class AppRadius {
  AppRadius._();
  static const double card = 20;
  static const double field = 14;
  static const double button = 14;
  static const double chip = 12;
  static const double sheet = 24;
}

class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  // Space on the left and right of a screen.
  static const double screen = 16;
}

class AppShadows {
  AppShadows._();

  // Soft shadow under cards.
  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: dark ? const Color(0x66000000) : const Color(0x1F2F80ED),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }
}

// A white rounded card with a soft shadow. Use it for cards that are not a Material Card.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.l),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).cardTheme.color ?? AppColors.card;
    final radius = BorderRadius.circular(AppRadius.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        boxShadow: AppShadows.soft(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// A round coloured circle with an icon inside (used when no PNG icon is added).
class IconCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const IconCircle({super.key, required this.icon, this.size = 44, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(icon, color: c, size: size * 0.5),
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final base = ColorScheme.fromSeed(seedColor: AppColors.sky, brightness: brightness);
    final scheme = base.copyWith(
      primary: dark ? AppColors.darkSky : AppColors.sky,
      onPrimary: dark ? AppColors.darkBackground : Colors.white,
      primaryContainer: dark ? const Color(0xFF1E3A66) : AppColors.skyLight,
      onPrimaryContainer: dark ? Colors.white : AppColors.skyDark,
      surface: dark ? AppColors.darkBackground : AppColors.background,
      onSurface: dark ? Colors.white : AppColors.text,
      onSurfaceVariant: dark ? const Color(0xFFA9B6CC) : AppColors.mutedText,
      surfaceContainerHighest: dark ? const Color(0xFF22324D) : AppColors.skyPale,
      error: AppColors.cancelled,
    );

    final cardColor = dark ? AppColors.darkCard : AppColors.card;
    final fieldFill = dark ? AppColors.darkCard : Colors.white;
    final border = dark ? const Color(0xFF2C3E5E) : const Color(0xFFD5E3FA);

    OutlineInputBorder fieldBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 3,
        shadowColor: dark ? const Color(0x66000000) : const Color(0x332F80ED),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.l, vertical: 14),
        border: fieldBorder(border),
        enabledBorder: fieldBorder(border),
        disabledBorder: fieldBorder(border.withValues(alpha: 0.5)),
        focusedBorder: fieldBorder(scheme.primary, 1.6),
        errorBorder: fieldBorder(AppColors.cancelled),
        focusedErrorBorder: fieldBorder(AppColors.cancelled, 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 0.6),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}

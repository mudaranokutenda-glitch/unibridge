import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'auth.dart';
import 'email_code.dart';
import 'profile_setup.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'startup_sound.dart';

// ---------------- Start-up intro (about 2 seconds) ----------------
// White screen: the full AZSA logo fades and scales in while the start-up sound
// plays. After that the app goes to the login screen or to the home screen.
// It runs once per cold start. Logo file: assets/logo/logo.jpg (without it a
// simple icon is shown).

const String kLogoAsset = 'assets/logo/logo.jpg';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final Animation<double> logoFade = CurvedAnimation(
    parent: controller,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );
  late final Animation<double> logoScale = Tween<double>(begin: 0.6, end: 1.0)
      .animate(CurvedAnimation(
    parent: controller,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  ));

  @override
  void initState() {
    super.initState();
    StartupSound.playOnce();
    controller.forward().whenComplete(goOn);
  }

  // After the animation: the same screen the app showed before the intro existed.
  Future<void> goOn() async {
    if (!mounted) return;
    // A "Forgot password" left half-way must not leave the user logged in.
    await cancelUnfinishedPasswordReset();
    // Web version, just back from Google: wait (max 6 s) until Supabase has
    // finished logging in from the address (?code=...).
    if (kIsWeb &&
        supabase.auth.currentSession == null &&
        (Uri.base.queryParameters.containsKey('code') ||
            Uri.base.fragment.contains('access_token'))) {
      try {
        await supabase.auth.onAuthStateChange
            .firstWhere((s) => s.session != null)
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('Google login (web) did not finish: $e');
      }
    }
    if (!mounted) return;
    final next = supabase.auth.currentSession == null
        ? const AuthScreen()
        : const ProfileGate();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget logo() {
    if (AppAssets.has(kLogoAsset)) {
      // The full logo (cap, circle and ribbon), as big as the screen allows.
      final w = MediaQuery.of(context).size.width;
      return Image.asset(
        kLogoAsset,
        width: (w * 0.7).clamp(180.0, 340.0),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallbackLogo(),
      );
    }
    return fallbackLogo();
  }

  // Without your logo file: a white circle with a simple icon.
  Widget fallbackLogo() => Container(
        width: 112,
        height: 112,
        decoration: const BoxDecoration(color: AppColors.skyPale, shape: BoxShape.circle),
        child: const Icon(Icons.school_rounded, size: 60, color: AppColors.sky),
      );

  @override
  Widget build(BuildContext context) {
    // White screen with dark status-bar icons, like the logo's own background.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FadeTransition(
            opacity: logoFade,
            child: ScaleTransition(scale: logoScale, child: logo()),
          ),
        ),
      ),
    );
  }
}

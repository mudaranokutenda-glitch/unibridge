import 'package:flutter/material.dart';
import 'config.dart';
import 'auth.dart';
import 'profile_setup.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'sky_background.dart';
import 'startup_sound.dart';

// ---------------- Start-up intro (about 1.5 seconds) ----------------
// The logo fades and scales in, then the app name appears. After that the app goes to
// the login screen or to the home screen, like before. It runs once per cold start.
// Logo file (optional): assets/logo/logo.png. Without it a simple icon is shown.

const String kLogoAsset = 'assets/logo/logo.png';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
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
  late final Animation<double> nameFade = CurvedAnimation(
    parent: controller,
    curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    StartupSound.playOnce();
    controller.forward().whenComplete(goOn);
  }

  // After the animation: the same screen the app showed before the intro existed.
  void goOn() {
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
      return Image.asset(
        kLogoAsset,
        width: 132,
        height: 132,
        errorBuilder: (_, _, _) => fallbackLogo(),
      );
    }
    return fallbackLogo();
  }

  // Without your logo file: a white circle with a simple icon.
  Widget fallbackLogo() => Container(
        width: 112,
        height: 112,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Icon(Icons.school_rounded, size: 60, color: AppColors.sky),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SkyBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: logoFade,
                child: ScaleTransition(scale: logoScale, child: logo()),
              ),
              const SizedBox(height: AppSpace.l),
              FadeTransition(
                opacity: nameFade,
                child: const Text(
                  'UniBridge',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

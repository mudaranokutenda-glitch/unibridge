import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'config.dart';
import 'l10n.dart';

// ---------------- App lock (fingerprint / face / phone PIN) ----------------
// Always on for signed-in users: the app asks to unlock when it opens and
// when it comes back after more than [kRelockAfter] in the background.
// Phones with no screen lock at all cannot be locked, so they go straight in.

const Duration kRelockAfter = Duration(minutes: 1);

class AppLock extends StatefulWidget {
  final Widget child;
  const AppLock({super.key, required this.child});

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  final auth = LocalAuthentication();
  bool locked = false;
  bool authenticating = false;
  DateTime? leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (supabase.auth.currentSession != null) {
      locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unlock());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The fingerprint dialog itself pauses the app, so ignore that.
    if (authenticating) return;
    if (state == AppLifecycleState.paused) {
      leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = leftAt == null
          ? Duration.zero
          : DateTime.now().difference(leftAt!);
      leftAt = null;
      if (!locked &&
          away > kRelockAfter &&
          supabase.auth.currentSession != null) {
        setState(() => locked = true);
        unlock();
      }
    }
  }

  Future<void> unlock() async {
    if (authenticating) return;
    authenticating = true;
    try {
      if (!await auth.isDeviceSupported()) {
        if (mounted) setState(() => locked = false);
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: tr('Unlock UniBridge'),
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) setState(() => locked = false);
    } on LocalAuthException catch (e) {
      // No fingerprint, face or PIN set up on this phone: nothing to check.
      if (e.code == LocalAuthExceptionCode.noCredentialsSet ||
          e.code == LocalAuthExceptionCode.noBiometricHardware) {
        if (mounted) setState(() => locked = false);
      }
      debugPrint('App lock: ${e.code}');
    } catch (e) {
      debugPrint('App lock error: $e');
    } finally {
      authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          tr('UniBridge is locked'),
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('Use your fingerprint, face or phone PIN to unlock.'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: unlock,
                          icon: const Icon(Icons.fingerprint),
                          label: Text(tr('Unlock')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

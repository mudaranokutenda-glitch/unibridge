import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'app_theme.dart';
import 'push.dart';
import 'profile_setup.dart';
import 'auth.dart';
import 'l10n.dart';
import 'errors.dart';

// ---------------- Email code (6 digits) ----------------
// Used after sign-up (confirm the email) and for "Forgot password".
// Supabase sends the code by email. The email template must contain {{ .Token }}
// (see REPORT.md, part "Valid emails only").

enum EmailCodeMode { signup, recovery }

// "Forgot password": a right code already logs the user in. If they leave before
// choosing the new password (back button, app closed), they are logged out
// again, so a half-finished reset never leaves them inside the app.
const String _kPendingPasswordReset = 'pending_password_reset';

Future<void> _setPendingPasswordReset(bool pending) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (pending) {
      await prefs.setBool(_kPendingPasswordReset, true);
    } else {
      await prefs.remove(_kPendingPasswordReset);
    }
  } catch (e) {
    debugPrint('Could not save the password reset state: $e');
  }
}

// Called at app start (intro.dart): a reset left unfinished means log out.
Future<void> cancelUnfinishedPasswordReset() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPendingPasswordReset) == true) {
      await prefs.remove(_kPendingPasswordReset);
      await supabase.auth.signOut();
    }
  } catch (e) {
    debugPrint('Could not cancel the unfinished password reset: $e');
  }
}

class EmailCodeScreen extends StatefulWidget {
  final String email;
  final EmailCodeMode mode;
  const EmailCodeScreen({super.key, required this.email, required this.mode});

  @override
  State<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends State<EmailCodeScreen> {
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final password2Controller = TextEditingController();

  Timer? timer;
  int secondsLeft = 60; // a code was just sent, so wait before sending another
  bool busy = false;
  bool codeAccepted = false; // recovery only: now ask for the new password
  bool passwordSaved = false; // recovery only: the new password was saved
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    startCountdown();
  }

  @override
  void dispose() {
    // Left the page after the right code but without a new password: log out.
    if (codeAccepted && !passwordSaved) {
      supabase.auth
          .signOut()
          .then((_) => _setPendingPasswordReset(false))
          .catchError((Object e) => debugPrint('Sign out failed: $e'));
    }
    timer?.cancel();
    codeController.dispose();
    passwordController.dispose();
    password2Controller.dispose();
    super.dispose();
  }

  void startCountdown() {
    timer?.cancel();
    setState(() => secondsLeft = 60);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (secondsLeft <= 1) {
        t.cancel();
        setState(() => secondsLeft = 0);
      } else {
        setState(() => secondsLeft -= 1);
      }
    });
  }

  Future<void> resend() async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      if (widget.mode == EmailCodeMode.signup) {
        await supabase.auth.resend(type: OtpType.signup, email: widget.email);
      } else {
        await supabase.auth.resetPasswordForEmail(widget.email);
      }
      if (!mounted) return;
      startCountdown();
      setState(() => info = tr('A new code was sent.'));
    } on AuthException catch (e) {
      if (mounted) setState(() => error = authErrorText(e));
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    final code = codeController.text.trim();
    if (code.length != 6) {
      setState(() => error = tr('Enter the 6 digits.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await supabase.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: widget.mode == EmailCodeMode.signup
            ? OtpType.signup
            : OtpType.recovery,
      );
      if (!mounted) return;
      if (widget.mode == EmailCodeMode.signup) {
        await finish();
      } else {
        // The code was right: ask for the new password.
        await _setPendingPasswordReset(true);
        if (mounted) setState(() => codeAccepted = true);
      }
    } on AuthException {
      if (mounted) setState(() => error = tr('Wrong or expired code. Try again.'));
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveNewPassword() async {
    final p1 = passwordController.text;
    if (p1.length < 6) {
      setState(() => error = tr('Password must have at least 6 characters.'));
      return;
    }
    if (p1 != password2Controller.text) {
      setState(() => error = tr('Passwords do not match.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await supabase.auth.updateUser(UserAttributes(password: p1));
      passwordSaved = true;
      await _setPendingPasswordReset(false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Password changed.'))));
      await finish();
    } on AuthException catch (e) {
      if (mounted) setState(() => error = authErrorText(e));
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Signed in: go to the profile set-up (ProfileGate decides what is still missing).
  Future<void> finish() async {
    await setupPushNotifications();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfileGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecovery = widget.mode == EmailCodeMode.recovery;
    return Scaffold(
      appBar: AppBar(
        title: Text(isRecovery ? tr('Reset password') : tr('Verify your email')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            if (!codeAccepted) ...[
              Text(tr('Enter the 6-digit code we sent to {email}',
                  {'email': widget.email})),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                decoration: InputDecoration(labelText: tr('6-digit code')),
                onSubmitted: (_) => busy ? null : verify(),
              ),
            ] else ...[
              Text(tr('Choose a new password.')),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('New password')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password2Controller,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: tr('Confirm new password')),
              ),
            ],
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!, style: const TextStyle(color: AppColors.cancelled)),
              ),
            if (info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(info!),
              ),
            ElevatedButton(
              onPressed:
                  busy ? null : (codeAccepted ? saveNewPassword : verify),
              child: Text(busy
                  ? tr('Please wait...')
                  : (codeAccepted ? tr('Save password') : tr('Verify'))),
            ),
            if (!codeAccepted)
              TextButton(
                onPressed: (busy || secondsLeft > 0) ? null : resend,
                child: Text(secondsLeft > 0
                    ? tr('Resend code in {seconds} s', {'seconds': secondsLeft})
                    : tr('Resend code')),
              ),
          ],
        ),
      ),
    );
  }
}

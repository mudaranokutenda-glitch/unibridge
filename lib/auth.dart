import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'config.dart';
import 'push.dart';
import 'profile_setup.dart';
import 'email_code.dart';
import 'legal.dart';
import 'l10n.dart';

bool _googleSignInInitialized = false;

// "Remember me" keeps ONLY the email address, on this phone. Never the password.
const String _kRememberedEmail = 'remembered_email';

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
  bool emailNotConfirmed = false; // login refused: the email was never confirmed
  bool rememberMe = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final fullNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadRememberedEmail();
  }

  Future<void> loadRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_kRememberedEmail);
      if (email != null && email.isNotEmpty && mounted) {
        setState(() {
          emailController.text = email;
          rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('Could not read the remembered email: $e');
    }
  }

  // After a successful log in: keep the email, or forget it.
  Future<void> saveRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        await prefs.setString(_kRememberedEmail, emailController.text.trim());
      } else {
        await prefs.remove(_kRememberedEmail);
      }
    } catch (e) {
      debugPrint('Could not save the remembered email: $e');
    }
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
      emailNotConfirmed = false;
    });
    try {
      if (isSignUp) {
        final res = await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          data: {
            'full_name': fullNameController.text.trim(),
          },
        );
        // No session = the email still has to be confirmed with the 6-digit code.
        if (res.session == null) {
          // An email that already has an account comes back with no identities
          // (Supabase hides it on purpose): no code is sent in that case.
          if (res.user != null && (res.user!.identities ?? []).isEmpty) {
            setState(() => errorMessage =
                tr('This email already has an account. Please log in.'));
            return;
          }
          if (mounted) await openCodeScreen(EmailCodeMode.signup);
          return;
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        await saveRememberedEmail();
      }
      if (mounted) {
        await setupPushNotifications();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileGate()),
          );
        }
      }
    } on AuthException catch (e) {
      if (!isSignUp &&
          (e.code == 'email_not_confirmed' ||
              e.message.toLowerCase().contains('not confirmed'))) {
        setState(() {
          emailNotConfirmed = true;
          errorMessage =
              tr('Your email is not confirmed yet. Enter the code we sent you.');
        });
      } else {
        setState(() => errorMessage = e.message);
      }
    } catch (e) {
      setState(() => errorMessage = tr('Something went wrong: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Opens the 6-digit code screen for the email typed above.
  Future<void> openCodeScreen(EmailCodeMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailCodeScreen(
            email: emailController.text.trim(), mode: mode),
      ),
    );
  }

  // Login said "not confirmed": send a new code, then ask for it.
  Future<void> resendConfirmation() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      await supabase.auth.resend(
          type: OtpType.signup, email: emailController.text.trim());
      if (mounted) {
        setState(() => emailNotConfirmed = false);
        await openCodeScreen(EmailCodeMode.signup);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(() =>
            errorMessage = tr('Something went wrong: {error}', {'error': e}));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // "Forgot password": the same code flow, with the type "recovery".
  Future<void> forgotPassword() async {
    final email = emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => errorMessage = tr('Enter your email first.'));
      return;
    }
    setState(() {
      loading = true;
      errorMessage = null;
      emailNotConfirmed = false;
    });
    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) await openCodeScreen(EmailCodeMode.recovery);
    } on AuthException catch (e) {
      if (mounted) setState(() => errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(() =>
            errorMessage = tr('Something went wrong: {error}', {'error': e}));
      }
    } finally {
      if (mounted) setState(() => loading = false);
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
            MaterialPageRoute(builder: (_) => const ProfileGate()),
          );
        }
      }
    } catch (e) {
      setState(() => errorMessage = tr('Google sign-in failed: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isSignUp ? tr('Create account') : tr('Log in')),
        actions: [LanguageMenuButton(onChanged: () => setState(() {}))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            if (isSignUp) ...[
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(labelText: tr('Full name')),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: tr('Email')),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(labelText: tr('Password')),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            if (!isSignUp)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: rememberMe,
                onChanged: (v) => setState(() => rememberMe = v ?? false),
                title: Text(tr('Remember me')),
                subtitle: Text(tr('Only your email is remembered, on this phone.')),
              ),
            if (emailNotConfirmed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  onPressed: loading ? null : resendConfirmation,
                  child: Text(tr('Send me a new code')),
                ),
              ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: Text(loading
                  ? tr('Please wait...')
                  : (isSignUp ? tr('Sign up') : tr('Log in'))),
            ),
            if (!isSignUp)
              TextButton(
                onPressed: loading ? null : forgotPassword,
                child: Text(tr('Forgot password?')),
              ),
            TextButton(
              onPressed: () => setState(() {
                isSignUp = !isSignUp;
                errorMessage = null;
                emailNotConfirmed = false;
              }),
              child: Text(isSignUp
                  ? tr('Already have an account? Log in')
                  : tr('New here? Create an account')),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(tr('OR')),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: loading ? null : signInWithGoogle,
              icon: const Icon(Icons.login),
              label: Text(tr('Continue with Google')),
            ),
            const SizedBox(height: 24),
            Text(
              tr('By continuing, you agree to our Terms of use and Privacy policy.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LegalScreen()),
                  ),
                  child: Text(tr('Terms of use')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(initialTab: 1)),
                  ),
                  child: Text(tr('Privacy policy')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Log out (button on the Profile tab) ----------------

Future<void> confirmAndLogOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('Log out?')),
      content: Text(tr('Are you sure you want to log out?')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(tr('Log out')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await clearPushToken();
  await supabase.auth.signOut();
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }
}

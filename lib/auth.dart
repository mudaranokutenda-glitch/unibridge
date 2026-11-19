import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'config.dart';
import 'push.dart';
import 'profile_setup.dart';
import 'email_code.dart';
import 'app_theme.dart';
import 'sky_background.dart';
import 'legal.dart';
import 'l10n.dart';

bool _googleSignInInitialized = false;

// GoogleSignIn must be initialised once before any other call.
Future<void> _ensureGoogleSignIn() async {
  if (_googleSignInInitialized) return;
  await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
  _googleSignInInitialized = true;
}

// "Remember me" keeps ONLY the email address, on this phone. Never the password.
const String _kRememberedEmail = 'remembered_email';

// A short, translated message for the errors Supabase gives at log in / sign up.
String authErrorText(AuthException e) {
  final code = e.code ?? '';
  final msg = e.message.toLowerCase();
  if (code == 'invalid_credentials' || msg.contains('invalid login')) {
    return tr('Wrong email or password.');
  }
  if (code == 'user_already_exists' || msg.contains('already registered')) {
    return tr('This email already has an account. Please log in.');
  }
  if (code == 'weak_password' || msg.contains('password should')) {
    return tr('Password must have at least 6 characters.');
  }
  if (code == 'email_address_invalid' || msg.contains('invalid email')) {
    return tr('Enter a valid email address.');
  }
  if (code.contains('rate_limit') || msg.contains('rate limit') ||
      msg.contains('too many')) {
    return tr('Too many tries. Wait a few minutes and try again.');
  }
  if (msg.contains('network') || msg.contains('socket') ||
      msg.contains('failed host lookup')) {
    return tr('No internet connection. Check it and try again.');
  }
  return tr('Something went wrong: {error}', {'error': e.message});
}

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
  bool showPassword = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final fullNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadRememberedEmail();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    fullNameController.dispose();
    super.dispose();
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

  // Checks the form before anything is sent. Returns the problem, or null.
  String? checkForm() {
    final email = emailController.text.trim();
    if (isSignUp) {
      final name = fullNameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.length < 2 || name.length > 80) {
        return tr('Enter your full name (2 to 80 characters)');
      }
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return tr('Enter a valid email address.');
    }
    if (passwordController.text.isEmpty) return tr('Enter your password.');
    if (isSignUp && passwordController.text.length < 6) {
      return tr('Password must have at least 6 characters.');
    }
    return null;
  }

  Future<void> submit() async {
    final problem = checkForm();
    if (problem != null) {
      setState(() {
        errorMessage = problem;
        emailNotConfirmed = false;
      });
      return;
    }
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
            'full_name':
                fullNameController.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          },
        );
        // No session = the email still has to be confirmed with the 6-digit code.
        if (res.session == null) {
          // An email that already has an account comes back with no identities
          // (Supabase hides it on purpose): no code is sent in that case.
          if (res.user != null && (res.user!.identities ?? []).isEmpty) {
            if (mounted) {
              setState(() => errorMessage =
                  tr('This email already has an account. Please log in.'));
            }
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
      if (!mounted) return;
      if (!isSignUp &&
          (e.code == 'email_not_confirmed' ||
              e.message.toLowerCase().contains('not confirmed'))) {
        setState(() {
          emailNotConfirmed = true;
          errorMessage =
              tr('Your email is not confirmed yet. Enter the code we sent you.');
        });
      } else {
        setState(() => errorMessage = authErrorText(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            errorMessage = tr('Something went wrong: {error}', {'error': e}));
      }
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
      if (mounted) setState(() => errorMessage = authErrorText(e));
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
      if (mounted) setState(() => errorMessage = authErrorText(e));
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
      await _ensureGoogleSignIn();

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
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      final info = (e.description ?? '').toLowerCase();
      if (e.code == GoogleSignInExceptionCode.canceled &&
          !info.contains('reauth')) {
        // The user closed the Google window: nothing to show.
        debugPrint('Google sign-in canceled: $e');
      } else if (info.contains('reauth') || info.contains('[16]') ||
          info.contains('10:')) {
        // Google does not recognise this copy of the app (SHA-1 / client set-up).
        debugPrint('Google sign-in set-up problem: $e');
        setState(() => errorMessage = tr(
            'Google sign-in is not available right now. Use your email and password, or try again later.'));
      } else {
        debugPrint('Google sign-in failed: $e');
        setState(() => errorMessage =
            tr('Google sign-in failed. Check your internet and try again.'));
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => errorMessage = authErrorText(e));
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      if (mounted) {
        setState(() => errorMessage =
            tr('Google sign-in failed. Check your internet and try again.'));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // A text field with a round blue icon at the start.
  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: !obscure && keyboard != TextInputType.emailAddress,
      enableSuggestions: !obscure,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.sky,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.l, vertical: AppSpace.l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          iconTheme: const IconThemeData(color: Colors.white),
                        ),
                        child: IconTheme(
                          data: const IconThemeData(color: Colors.white),
                          child: LanguageMenuButton(
                              onChanged: () => setState(() {})),
                        ),
                      ),
                    ),
                    const Text(
                      'UniBridge',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpace.l),
                    AppCard(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isSignUp ? tr('Create account') : tr('Log In'),
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            isSignUp
                                ? tr('Join UniBridge today.')
                                : tr('Glad to see you again.'),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.xl),
                          if (isSignUp) ...[
                            _field(
                              controller: fullNameController,
                              label: tr('Full name'),
                              icon: Icons.person,
                            ),
                            const SizedBox(height: AppSpace.m),
                          ],
                          _field(
                            controller: emailController,
                            label: tr('Email'),
                            icon: Icons.email,
                            keyboard: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: AppSpace.m),
                          _field(
                            controller: passwordController,
                            label: tr('Password'),
                            icon: Icons.lock,
                            obscure: !showPassword,
                            suffix: IconButton(
                              tooltip: showPassword
                                  ? tr('Hide password')
                                  : tr('Show password'),
                              icon: Icon(showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => showPassword = !showPassword),
                            ),
                            onSubmitted: (_) => loading ? null : submit(),
                          ),
                          if (!isSignUp) ...[
                            const SizedBox(height: AppSpace.s),
                            Row(
                              children: [
                                Checkbox(
                                  value: rememberMe,
                                  onChanged: (v) =>
                                      setState(() => rememberMe = v ?? false),
                                ),
                                Expanded(
                                  child: Text(tr('Remember me'),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                TextButton(
                                  onPressed: loading ? null : forgotPassword,
                                  child: Text(tr('Forgot password?')),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                  start: AppSpace.m),
                              child: Text(
                                tr('Only your email is remembered, on this phone.'),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpace.l),
                          if (errorMessage != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpace.m),
                              child: Text(errorMessage!,
                                  style: const TextStyle(
                                      color: AppColors.cancelled)),
                            ),
                          if (emailNotConfirmed)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpace.m),
                              child: OutlinedButton(
                                onPressed: loading ? null : resendConfirmation,
                                child: Text(tr('Send me a new code')),
                              ),
                            ),
                          ElevatedButton(
                            onPressed: loading ? null : submit,
                            child: Text(loading
                                ? tr('Please wait...')
                                : (isSignUp ? tr('Sign up') : tr('Log In'))),
                          ),
                          const SizedBox(height: AppSpace.l),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.m),
                                child: Text(tr('OR')),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: AppSpace.l),
                          OutlinedButton.icon(
                            onPressed: loading ? null : signInWithGoogle,
                            icon: const Icon(Icons.login),
                            label: Text(tr('Continue with Google')),
                          ),
                          const SizedBox(height: AppSpace.s),
                          Center(
                            child: TextButton(
                              // Not while a request is running: the answer
                              // would be read for the wrong mode.
                              onPressed: loading
                                  ? null
                                  : () => setState(() {
                                        isSignUp = !isSignUp;
                                        errorMessage = null;
                                        emailNotConfirmed = false;
                                      }),
                              child: Text(isSignUp
                                  ? tr('Already have an account? Log in')
                                  : tr("Don't have an account? Sign up")),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.l),
                    Text(
                      tr('By continuing, you agree to our Terms of use and Privacy policy.'),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const LegalScreen()),
                          ),
                          child: Text(tr('Terms of use')),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const LegalScreen(initialTab: 1)),
                          ),
                          child: Text(tr('Privacy policy')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
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
  // Forget the Google account too, so the next Google sign-in lets the user
  // choose an account again.
  try {
    await _ensureGoogleSignIn();
    await GoogleSignIn.instance.signOut();
  } catch (e) {
    debugPrint('Google sign-out failed: $e');
  }
  await supabase.auth.signOut();
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }
}

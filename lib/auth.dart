import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'config.dart';
import 'push.dart';
import 'home.dart';
import 'legal.dart';

bool _googleSignInInitialized = false;

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

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final fullNameController = TextEditingController();
  final inscriptionController = TextEditingController();

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      if (isSignUp) {
        await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          data: {
            'full_name': fullNameController.text.trim(),
            'inscription_number': inscriptionController.text.trim(),
          },
        );
      } else {
        await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      }
      if (mounted) {
        await setupPushNotifications();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => errorMessage = e.message);
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong: $e');
    } finally {
      setState(() => loading = false);
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
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      setState(() => errorMessage = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isSignUp ? 'Create account' : 'Log in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            if (isSignUp) ...[
              TextField(
                controller: fullNameController,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inscriptionController,
                decoration:
                    const InputDecoration(labelText: 'Inscription number'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: loading ? null : submit,
              child: Text(loading
                  ? 'Please wait...'
                  : (isSignUp ? 'Sign up' : 'Log in')),
            ),
            TextButton(
              onPressed: () => setState(() => isSignUp = !isSignUp),
              child: Text(isSignUp
                  ? 'Already have an account? Log in'
                  : 'New here? Create an account'),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('OR'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: loading ? null : signInWithGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 24),
            const Text(
              'By continuing, you agree to our Terms of use and Privacy policy.',
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
                  child: const Text('Terms of use'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(initialTab: 1)),
                  ),
                  child: const Text('Privacy policy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// lib/pages/login_page.dart
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/local_mode_service.dart';
import '../../services/auth_service.dart';
import 'register_page.dart';
import '/auth_gate.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String? errorMessage;
  bool isLoading = false;

  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _logInRevenueCat(User? user) async {
    if (!_rcSupported || user == null) return;
    try {
      await Purchases.logIn(user.uid);
      debugPrint('RevenueCat login OK for ${user.uid}');
    } catch (e) {
      debugPrint('RevenueCat login failed: $e');
    }
  }

  Future<void> login() async {
    if (!mounted) return;
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      await _logInRevenueCat(cred.user);
      // AuthGate will navigate on auth state change.
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => errorMessage = 'Login failed. Please try again.');
    } finally {
      // If AuthGate navigates away, this setState is harmless; otherwise it stops the spinner.
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> loginWithGoogle() async {
    if (!mounted) return;
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    try {
      // New AuthService always returns a UserCredential on success, or throws.
      final cred = await AuthService.instance.signInWithGoogle();
      await _logInRevenueCat(cred.user);
      // AuthGate will navigate after auth state change.
      if (mounted) setState(() => isLoading = false);
    } on AuthFlowException catch (e) {
      // Map friendly messages per error code.
      if (!mounted) return;

      switch (e.code) {
        case AuthFlowCode.redirecting:
          // Web: popup fell back to redirect; page will reload and complete.
          // Keep spinner on and do NOT show an error.
          return;

        case AuthFlowCode.canceled:
          setState(() {
            errorMessage = 'Sign-in canceled.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.busy:
          setState(() {
            errorMessage = 'Sign-in already in progress.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.network:
          setState(() {
            errorMessage = 'Network error. Please check your connection and try again.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.browserOpenFailed:
          setState(() {
            errorMessage = 'Could not open your browser for Google sign-in.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.misconfigured:
          setState(() {
            errorMessage = 'Google sign-in is not configured correctly.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.rateLimited:
          setState(() {
            errorMessage = 'Too many attempts. Please try again later.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.security:
          setState(() {
            errorMessage = 'Security check failed. Please try again.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.unsupported:
          setState(() {
            errorMessage = 'This platform is not supported for Google sign-in.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.accountExistsDifferentCred:
          setState(() {
            errorMessage = 'This email is already linked to a different sign-in method. '
                           'Use your original method, then link Google in Settings.';
            isLoading = false;
          });
          break;

        case AuthFlowCode.unknown:
        setState(() {
            errorMessage = e.message.isNotEmpty ? e.message : 'Google sign-in failed.';
            isLoading = false;
          });
          break;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'Google sign-in failed.';
          isLoading = false;
        });
      }
    }
  }

  void goToRegister() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: resetEmailController,
          decoration: const InputDecoration(
            labelText: 'Enter your email address',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty) {
                if (mounted) setState(() => errorMessage = 'Please enter an email address.');
                return;
              }

              if (mounted) {
                setState(() {
                  isLoading = true;
                  errorMessage = null;
                });
              }

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Password reset email sent.')),
                );
                Navigator.of(dialogContext).pop();
              } on FirebaseAuthException catch (e) {
                if (mounted) setState(() => errorMessage = e.message);
              } catch (_) {
                if (mounted) setState(() => errorMessage = 'An error occurred.');
              } finally {
                if (mounted) setState(() => isLoading = false);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Welcome to FermentaCraft'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/images/carboy.svg',
                height: 100,
                semanticsLabel: 'FermentaCraft Logo',
                placeholderBuilder: (context) => const CircularProgressIndicator(),
              ),
              const SizedBox(height: 20),
              Text(
                'Log in to start crafting!',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Design, track, and perfect your homebrews with ease.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),

              if (errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : const Text('Log In'),
                  onPressed: isLoading ? null : login,
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: SvgPicture.asset(
                    'assets/images/google.svg',
                    height: 24,
                    width: 24,
                    semanticsLabel: 'Google Logo',
                  ),
                  label: const Text('Sign in with Google'),
                  onPressed: isLoading ? null : loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Local-only entry point ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cloud_off),
                label: const Text('Continue without account'),
onPressed: isLoading
    ? null
    : () async {
        setState(() => isLoading = true);
        try {
          // Cache navigator before the await
          final navigator = Navigator.of(context);

          await LocalModeService.instance.enableLocalOnly();

          if (!mounted) return; // guard State after the await

          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        } finally {
          if (mounted) setState(() => isLoading = false);
        }
      },

              ),
            ),
            const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  TextButton(onPressed: goToRegister, child: const Text('Create one')),
                ],
              ),
              TextButton(
                onPressed: isLoading ? null : _showForgotPasswordDialog,
                child: const Text('Forgot password?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

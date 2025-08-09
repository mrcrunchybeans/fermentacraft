import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'register_page.dart';

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

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!mounted) return;
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    bool success = false;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      success = true; // AuthGate will replace this page
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.message;
        });
      }
    } finally {
      // Only stop spinner if we're still on this page and login didn't succeed
      if (mounted && !success) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> loginWithGoogle() async {
    if (!mounted) return;
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    bool success = false;
    try {
      final user = await signInWithGoogle();
      success = user != null;

      if (!success && mounted) {
        setState(() {
          errorMessage = 'Google sign-in failed or was cancelled.';
        });
      }
      // If success, AuthGate will swap this page—do not call setState.
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'Google sign-in failed.';
        });
      }
    } finally {
      if (mounted && !success) {
        setState(() => isLoading = false);
      }
    }
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
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
                if (mounted) {
                  setState(() => errorMessage = 'Please enter an email address.');
                }
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
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
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  TextButton(
                    onPressed: goToRegister,
                    child: const Text('Create one'),
                  ),
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

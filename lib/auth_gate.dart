import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/login_page.dart';
import 'app_shell.dart';
import 'services/local_mode_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final isLocal = LocalModeService.instance.isLocalOnly;
        if (snapshot.connectionState == ConnectionState.waiting && !isLocal) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData || isLocal) {
          return const AppShell(); // ✅ use the full app shell, not just a page
        }

        return const LoginPage(); // User is not logged in
      },
    );
  }
}

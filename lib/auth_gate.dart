import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/login_page.dart';
import 'app_shell.dart';
import 'services/local_mode_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[AUTH] Building AuthGate...');
    
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        debugPrint('[AUTH] StreamBuilder called - ConnectionState: ${snapshot.connectionState}');
        debugPrint('[AUTH] Has data: ${snapshot.hasData}');
        debugPrint('[AUTH] Has error: ${snapshot.hasError}');
        
        final isLocal = LocalModeService.instance.isLocalOnly;
        debugPrint('[AUTH] Is local mode: $isLocal');
        
        if (snapshot.connectionState == ConnectionState.waiting && !isLocal) {
          debugPrint('[AUTH] Showing loading screen');
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData || isLocal) {
          debugPrint('[AUTH] User authenticated or local mode - showing AppShell');
          return const AppShell(); // ✅ use the full app shell, not just a page
        }

        debugPrint('[AUTH] User not authenticated - showing LoginPage');
        return const LoginPage(); // User is not logged in
      },
    );
  }
}

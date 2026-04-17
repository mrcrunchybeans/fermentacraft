import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class LoginPageSimple extends StatelessWidget {
  const LoginPageSimple({super.key});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('LoginPageSimple build() called');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Login'),
        backgroundColor: Colors.blue,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 64,
              color: Colors.blue,
            ),
            SizedBox(height: 20),
            Text(
              'Login Page Works!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'This confirms UI rendering is working',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

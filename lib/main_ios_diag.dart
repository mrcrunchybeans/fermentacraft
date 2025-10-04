// lib/main_ios_diag.dart
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _DiagApp());
}

class _DiagApp extends StatelessWidget {
  const _DiagApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'FermentaCraft iOS DIAG',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apple, size: 96, color: Colors.white),
              SizedBox(height: 24),
              Text(
                'FermentaCraft iOS DIAG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'If you can see this, native iOS config is OK.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

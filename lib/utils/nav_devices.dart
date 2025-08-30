// lib/utils/nav_devices.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fermentacraft/widgets/devices_selection.dart';

Future<void> openDevicesScreen(BuildContext context, {String? batchId}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign in required'),
        content: const Text('Sign in from the Account section to manage devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return;
  }
  // ignore: use_build_context_synchronously
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => DevicesSelection(uid: user.uid, batchId: batchId)),
  );
}

// lib/services/firestore_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreUser {
  FirestoreUser._();
  static final instance = FirestoreUser._();

  /// Ensures we have a signed-in user, waits if needed.
  Future<User> _requireUser() async {
    final auth = FirebaseAuth.instance;
    final u = auth.currentUser;
    if (u != null) return u;
    return (await auth.authStateChanges().firstWhere((x) => x != null))!;
  }

  /// Create users/{uid} if missing (idempotent).
  Future<void> ensureUserDoc([User? user]) async {
    final u = user ?? await _requireUser();
    final ref = FirebaseFirestore.instance.doc('users/${u.uid}');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': u.uid,
        'email': u.email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Safe path builder: never use cached uid.
  Future<DocumentReference<Map<String, dynamic>>> settingsDoc() async {
    final u = await _requireUser();
    return FirebaseFirestore.instance.doc('users/${u.uid}/settings/app');
  }

  /// Safe write with a tiny backoff on freshly-established auth.
  Future<void> writeSettings(Map<String, dynamic> data, {bool ensureUser = true}) async {
    if (ensureUser) {
      // Make sure users/{uid} exists to satisfy rules.
      await ensureUserDoc();
    }
    final doc = await settingsDoc();
    for (int i = 0; i < 2; i++) {
      try {
        await doc.set(data, SetOptions(merge: true));
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' && i == 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        rethrow;
      }
    }
  }
}

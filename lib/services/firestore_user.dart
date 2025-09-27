// lib/services/firestore_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
    
    // Ensure we have a valid ID token before attempting Firestore operations
    try {
      final token = await u.getIdToken(true); // force refresh the token
      if (kDebugMode) {
        print('[FIRESTORE_USER] Token refreshed for user: ${u.uid}');
        if (token != null) {
          print('[FIRESTORE_USER] Token length: ${token.length}');
          print('[FIRESTORE_USER] Token preview: ${token.substring(0, 50)}...');
        }
      }
      
      // Add a small delay to ensure token propagation
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      if (kDebugMode) {
        print('[FIRESTORE_USER] Token refresh failed: $e');
      }
      // Continue anyway, let Firestore operation fail if needed
    }
    
    final ref = FirebaseFirestore.instance.doc('users/${u.uid}');
    
    if (kDebugMode) {
      print('[FIRESTORE_USER] Attempting to check if user doc exists: users/${u.uid}');
    }
    
    try {
      final snap = await ref.get();
      
      if (!snap.exists) {
        if (kDebugMode) {
          print('[FIRESTORE_USER] User document does not exist, creating...');
        }
        
        await ref.set({
          'uid': u.uid,
          'email': u.email,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        if (kDebugMode) {
          print('[FIRESTORE_USER] ✅ User document created successfully');
        }
      } else {
        if (kDebugMode) {
          print('[FIRESTORE_USER] ✅ User document already exists');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FIRESTORE_USER] ❌ Firestore operation failed: $e');
      }
      rethrow;
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

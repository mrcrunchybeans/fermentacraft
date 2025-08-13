// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Simple auth facade for Google sign-in across mobile & web.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// GoogleSignIn is only used on mobile (Android/iOS).
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const <String>['email'], // keep scopes minimal
  );

  /// Call once after Firebase.initializeApp (e.g., in main()).
  /// - Sets LOCAL persistence on web (prevents weird redirect loops/400s).
  /// - Completes a pending redirect result if one exists.
  Future<void> initForWebIfNeeded() async {
    if (!kIsWeb) return;
    try {
      await _auth.setPersistence(Persistence.LOCAL);
    } catch (e) {
      // Non-fatal on native/mobile. Useful log for web.
      // ignore: avoid_print
      print('Auth persistence setup failed (non-fatal): $e');
    }

    try {
      // If a previous signInWithRedirect just returned, this resolves it.
      await _auth.getRedirectResult();
    } catch (e) {
      // ignore: avoid_print
      print('No redirect result (or error resolving it): $e');
    }
  }

  /// Call on your “Sign in with Google” button.
  /// - Web: tries popup; on known errors, falls back to redirect.
  /// - Mobile: uses google_sign_in → Firebase credential.
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters(<String, String>{
          // Forces account chooser; can help when cached session conflicts
          'prompt': 'select_account',
        });

      try {
        return await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        // Log so you can see the REAL cause in DevTools
        // ignore: avoid_print
        print('Web Google sign-in failed: ${e.code} — ${e.message}');

        // Common recoverable cases → try redirect (page will reload).
        const fallbackCodes = <String>{
          'popup-blocked',
          'popup-closed-by-user',
          'unauthorized-domain', // domain not in Firebase Auth → add it!
          'operation-not-supported-in-this-environment',
        };

        if (fallbackCodes.contains(e.code)) {
          await _auth.signInWithRedirect(provider);
          return null; // flow continues after redirect
        }

        // Helpful hints for common 400-ish root causes:
        if (e.code == 'unauthorized-domain') {
          // Make sure app.fermentacraft.com is in Firebase Auth → Authorized domains.
          // Also ensure Google provider is enabled.
        } else if (e.code == 'operation-not-allowed') {
          // Enable the Google provider in Firebase Auth → Sign-in method.
        } else if (e.code == 'account-exists-with-different-credential') {
          // Handle linking flow if you support multiple providers for the same email.
        }

        rethrow; // Let caller surface a toast/snackbar if you want
      }
    }

    // ---- Mobile (Android/iOS) ----
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user canceled
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('Mobile Google sign-in failed: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('Mobile Google sign-in non-Firebase error: $e');
      return null;
    }
  }

  /// Signs out (web: Firebase only; mobile: Google + Firebase).
  Future<void> signOut() async {
    if (kIsWeb) {
      await _auth.signOut();
      return;
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore GoogleSignIn sign-out errors; still sign out of Firebase.
    } finally {
      await _auth.signOut();
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}

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
    scopes: <String>[
      'email',
      'https://www.googleapis.com/auth/userinfo.profile',
    ],
  );

  /// Call on your “Sign in with Google” button.
  /// - Web: tries popup; if blocked/closed/unauthorized-domain, falls back to redirect.
  /// - Mobile: uses google_sign_in → Firebase credential.
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      try {
        return await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        // If popup fails, try redirect (page will reload, result is handled by [completePendingRedirectIfAny]).
        const fallbackCodes = {
          'popup-blocked',
          'popup-closed-by-user',
          'unauthorized-domain',
          'operation-not-supported-in-this-environment',
        };
        if (fallbackCodes.contains(e.code)) {
          await _auth.signInWithRedirect(provider);
          return null; // completes after redirect
        }
        rethrow;
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
    } catch (_) {
      return null;
    }
  }

  /// Optional helper for web: call once on app startup (after Firebase.initializeApp)
  /// to complete a pending redirect sign-in (if popup fallback was used).
  Future<void> completePendingRedirectIfAny() async {
    if (!kIsWeb) return;
    try {
      await _auth.getRedirectResult();
    } catch (_) {
      // You can log/telemetry here if desired.
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

  /// Convenience getter for current user.
  User? get currentUser => _auth.currentUser;

  /// Stream for auth state changes (useful for top-level listeners).
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}

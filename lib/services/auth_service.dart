import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email', 'https://www.googleapis.com/auth/userinfo.profile'],
);

Future<UserCredential?> signInWithGoogle() async {
  try {
    // Prompt user to sign in
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      debugPrint('Google Sign-In cancelled by user.');
      return null;
    }

    // Get the authentication object
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    // Create a Firebase credential
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );

    // Sign in to Firebase with the Google credential
    return await FirebaseAuth.instance.signInWithCredential(credential);
  } catch (e, stack) {
    debugPrint('Error during Google Sign-In: $e');
    debugPrint(stack.toString());
    return null;
  }
}

Future<void> signOutFromGoogle() async {
  try {
    await _googleSignIn.signOut();
    await FirebaseAuth.instance.signOut();
    debugPrint('Signed out from Google and Firebase.');
  } catch (e) {
    debugPrint('Error signing out: $e');
  }
}

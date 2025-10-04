// lib/services/platform/ios_auth_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../utils/result.dart';

/// iOS-specific authentication service implementation
/// Handles iOS-specific auth flows and lifecycle management
class IOSAuthService {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // iOS-specific configuration
    scopes: ['email', 'profile'],
    hostedDomain: null, // Allow any Google account
  );

  /// iOS-optimized Google Sign-In flow
  static Future<Result<User, Exception>> signInWithGoogle() async {
    try {
      debugPrint('Starting iOS Google Sign-In flow');
      
      // Configure Google Sign-In for iOS
      await _configureGoogleSignInForIOS();
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('iOS Google Sign-In cancelled by user');
        return Failure(Exception('Sign in cancelled by user'));
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
  debugPrint('iOS Google Sign-In failed to get tokens');
        return Failure(Exception('Failed to obtain authentication tokens'));
      }

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      final User? user = userCredential.user;
      
      if (user == null) {
        debugPrint('iOS Firebase sign-in returned null user');
        return Failure(Exception('Authentication failed'));
      }

      debugPrint('iOS Google Sign-In successful for user: ${user.email}');
      
      // Set up user attributes for iOS
      await _setupUserAttributes(user);
      
      return Success(user);
    } catch (e, stackTrace) {
      debugPrint('iOS Google Sign-In failed: $e\n$stackTrace');
      return Failure(Exception('Sign in failed: ${e.toString()}'));
    }
  }

  /// Configure Google Sign-In specifically for iOS
  static Future<void> _configureGoogleSignInForIOS() async {
    // iOS-specific configuration if needed
    if (Platform.isIOS) {
      // Additional iOS-specific setup can go here
  debugPrint('Configuring Google Sign-In for iOS');
    }
  }

  /// Set up user attributes for analytics and RevenueCat
  static Future<void> _setupUserAttributes(User user) async {
    try {
      // Set up user attributes for iOS
      final attributes = {
        'platform': 'iOS',
        'user_id': user.uid,
        'email': user.email ?? '',
        'sign_in_method': 'google',
        'created_at': DateTime.now().toIso8601String(),
      };

  debugPrint('Setting up iOS user attributes: $attributes');
      
      // This would integrate with RevenueCat when we implement Task 5
      // await RevenueCatService.setUserAttributes(attributes);
      
    } catch (e, stackTrace) {
      debugPrint('Failed to set up iOS user attributes: $e\n$stackTrace');
      // Don't fail auth for attribute setup errors
    }
  }

  /// iOS-specific sign out handling
  static Future<Result<void, Exception>> signOut() async {
    try {
  debugPrint('Starting iOS sign out');
      
      // Sign out from Google Sign-In
      await _googleSignIn.signOut();
      
      // Sign out from Firebase
      await _firebaseAuth.signOut();
      
      debugPrint('iOS sign out successful');
      return const Success(null);
    } catch (e, stackTrace) {
      debugPrint('iOS sign out failed: $e\n$stackTrace');
      return Failure(Exception('Sign out failed: ${e.toString()}'));
    }
  }

  /// Get current user with iOS-specific handling
  static User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }

  /// iOS-specific auth state listener
  static Stream<User?> authStateChanges() {
    return _firebaseAuth.authStateChanges();
  }

  /// Handle iOS app lifecycle for auth state
  static Future<void> handleAppLifecycle() async {
    if (Platform.isIOS) {
      // iOS-specific auth lifecycle handling
  debugPrint('Handling iOS app lifecycle for auth');
      
      // Check if user is still valid after app becomes active
      final user = getCurrentUser();
      if (user != null) {
        try {
          await user.reload();
          debugPrint('iOS auth state refreshed successfully');
        } catch (e) {
          debugPrint('Failed to refresh iOS auth state: $e');
        }
      }
    }
  }
}
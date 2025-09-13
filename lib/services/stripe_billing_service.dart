// lib/services/stripe_billing_service.dart
//
// Restored public API compatible with your paywall:
//   Future<void> startCheckout({
//     required String priceId,
//     required Uri successUrl,
//     required Uri cancelUrl,
//   })
//
// Behavior:
// • Mobile & Web: use Firebase Functions callable 'createCheckout' (region us-central1).
// • Desktop (Windows/Linux/macOS): call the HTTPS endpoint
//     https://us-central1-fermentacraft.cloudfunctions.net/createCheckoutHttp
//   with the Firebase ID token.
// • Ensures the user is signed in (anonymous is fine) before starting checkout.
// • Opens the returned URL via url_launcher with canLaunchUrl + fallback.
// • Also exposes openBillingPortal() via callable 'createBillingPortal'.
//
// Notes:
// • This version prefers safety on iOS (Simulator/Device) without altering callers.
// • If you later add Pro-Offline vs Subscription options, add optional params but
//   keep the existing named params to avoid breaking call sites.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class StripeBillingService {
  StripeBillingService._();
  static final StripeBillingService instance = StripeBillingService._();

  static const String _region = 'us-central1';
  static const String _projectId = 'fermentacraft';

  static Uri get _httpEndpoint => Uri.parse(
        'https://$_region-$_projectId.cloudfunctions.net/createCheckoutHttp',
      );

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  /// Public API used by your paywall.
  /// Creates a Stripe Checkout Session and opens it in the browser.
  Future<void> startCheckout({
    required String priceId,
    required Uri successUrl,
    required Uri cancelUrl,
  }) async {
    await _ensureSignedIn();

    if (_isDesktop) {
      // Desktop (Windows/Linux/macOS): use HTTPS endpoint with ID token
      await _startCheckoutHttp(priceId, successUrl, cancelUrl);
    } else {
      // Mobile & Web (iOS/Android/Web): use Firebase callable
      await _startCheckoutCallable(priceId, successUrl, cancelUrl);
    }
  }

  /// Opens the Stripe customer billing portal.
  Future<void> openBillingPortal() async {
    final callable =
        FirebaseFunctions.instanceFor(region: _region).httpsCallable('createBillingPortal');

    final resp = await callable.call(<String, dynamic>{});
    final url = (resp.data is Map ? (resp.data as Map)['url'] : null) as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Stripe: no billing portal URL returned.');
    }
    await _open(url);
  }

  // ===== Internals =====

  // Mobile + Web: Firebase callable
  Future<void> _startCheckoutCallable(
    String priceId,
    Uri successUrl,
    Uri cancelUrl,
  ) async {
    final callable =
        FirebaseFunctions.instanceFor(region: _region).httpsCallable('createCheckout');

    final res = await callable.call({
      'priceId': priceId,
      'successUrl': successUrl.toString(),
      'cancelUrl': cancelUrl.toString(),
    });

    final data = (res.data is Map) ? (res.data as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final url = (data['url'] as String?)?.trim();
    if (url == null || url.isEmpty) {
      throw Exception('Stripe: no checkout URL returned from callable.');
    }
    await _open(url);
  }

  // Desktop: plain HTTP to createCheckoutHttp with Firebase ID token
  Future<void> _startCheckoutHttp(
    String priceId,
    Uri successUrl,
    Uri cancelUrl,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Stripe: not signed in.');
    final idToken = await user.getIdToken();

    final resp = await http.post(
      _httpEndpoint,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'priceId': priceId,
        'successUrl': successUrl.toString(),
        'cancelUrl': cancelUrl.toString(),
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Stripe HTTP ${resp.statusCode}: ${resp.body}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = (map['url'] as String?)?.trim();
    if (url == null || url.isEmpty) {
      throw Exception('Stripe: no checkout URL returned from HTTP endpoint.');
    }
    await _open(url);
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        // Prefer leaving the app to a default browser when possible
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
        // Fallback (useful on some platforms & simulators)
        if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
      }
    } catch (_) {
      // Fall through to error below
    }
    throw Exception('Stripe: failed to open checkout URL.');
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class StripeBillingService {
  StripeBillingService._();
  static final instance = StripeBillingService._();

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

  /// Kicks off Stripe-hosted Checkout for subscriptions.
  Future<void> startCheckout({
    required String priceId,
    required Uri successUrl,
    required Uri cancelUrl,
  }) async {
    await _ensureSignedIn();
    if (_isDesktop) {
      await _startCheckoutHttp(priceId, successUrl, cancelUrl);
    } else {
      await _startCheckoutCallable(priceId, successUrl, cancelUrl);
    }
  }

  Future<void> openBillingPortal() async {
    final callable = FirebaseFunctions.instance.httpsCallable('createBillingPortal');
    final resp = await callable.call(<String, dynamic>{});
    final url = Uri.parse(resp.data['url'] as String);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not open billing portal';
    }
  }

  // Mobile + Web: Firebase callable
  Future<void> _startCheckoutCallable(
    String priceId,
    Uri successUrl,
    Uri cancelUrl,
  ) async {
    final callable = FirebaseFunctions.instanceFor(region: _region)
        .httpsCallable('createCheckout');

    final res = await callable.call({
      'priceId': priceId,
      'successUrl': successUrl.toString(),
      'cancelUrl': cancelUrl.toString(),
    });

    final data = (res.data as Map?) ?? const {};
    final url = data['url'] as String?;
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
    final url = map['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Stripe: no checkout URL returned from HTTP endpoint.');
    }
    await _open(url);
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      // fallback (useful on some platforms)
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }
}

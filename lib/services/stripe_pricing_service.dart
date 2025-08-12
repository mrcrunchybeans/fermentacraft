// lib/services/stripe_pricing_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class StripePrice {
  final String id;
  final int? unitAmount; // cents
  final String currency; // 'usd'
  final String? interval; // 'month' | 'year' | null
  final int intervalCount;

  StripePrice({
    required this.id,
    required this.unitAmount,
    required this.currency,
    required this.interval,
    required this.intervalCount,
  });

  String toMoney() {
    if (unitAmount == null) return '—';
    final amt = unitAmount! / 100.0;
    final f = NumberFormat.simpleCurrency(name: currency.toUpperCase());
    return f.format(amt);
  }

  factory StripePrice.fromJson(Map<String, dynamic> j) => StripePrice(
        id: j['id'] as String,
        unitAmount: j['unit_amount'] as int?,
        currency: (j['currency'] as String).toUpperCase(),
        interval: j['interval'] as String?,
        intervalCount: (j['interval_count'] as int?) ?? 1,
      );
}

class StripePricingService {
  StripePricingService._();
  static final instance = StripePricingService._();

  final Map<String, StripePrice> _cache = {};

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<User> _ensureUser() async {
    final auth = FirebaseAuth.instance;
    return auth.currentUser ?? (await auth.signInAnonymously()).user!;
  }

  Uri _httpEndpoint() {
    final proj = Firebase.app().options.projectId;
    return Uri.parse('https://us-central1-$proj.cloudfunctions.net/getStripePricesHttp');
  }

  Future<Map<String, StripePrice>> fetchPrices(List<String> priceIds) async {
    final ordered = priceIds.toList();
    final missing = ordered.where((id) => !_cache.containsKey(id)).toList();

    if (missing.isNotEmpty) {
      // Always ensure we have a user (callable also needs auth in your functions)
      final user = await _ensureUser();

      Map<String, StripePrice> fetched;
      if (_isDesktop) {
        final idToken = await user.getIdToken();
        final resp = await http.post(
          _httpEndpoint(),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'priceIds': missing}),
        );
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception('getStripePricesHttp ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['prices'] as List).cast<Map<String, dynamic>>();
        fetched = {for (final p in list) p['id'] as String: StripePrice.fromJson(p)};
      } else {
        final callable =
            FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getStripePrices');
        final res = await callable.call({'priceIds': missing});
        final list = (res.data['prices'] as List).cast<Map<String, dynamic>>();
        fetched = {for (final p in list) p['id'] as String: StripePrice.fromJson(p)};
      }

      _cache.addAll(fetched);
    }

    return {for (final id in ordered) id: _cache[id]!};
  }
}

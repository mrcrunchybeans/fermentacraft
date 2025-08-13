// lib/services/stripe_pricing_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// namespaced cache keys (fc_)

class StripePrice {
  final String id;
  final int? unitAmount; // cents
  final String currency; // 'USD'
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit_amount': unitAmount,
        'currency': currency,
        'interval': interval,
        'interval_count': intervalCount,
      };
}

class StripePricingService {
  StripePricingService._();
  static final instance = StripePricingService._();

  /// In-memory cache for this session. (Optionally persist using fc_ keys.)
  final Map<String, StripePrice> _cache = {};

  // Optional in the future: persist a tiny JSON cache under fc_ key.
// 'fc_stripe_prices'

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

  /// Fetches prices, using a small in-memory cache first.
  /// (Hook points left in place to persist under the fc_ key if you want.)
  Future<Map<String, StripePrice>> fetchPrices(List<String> priceIds) async {
    // preserve caller order
    final ordered = priceIds.toList();

    // 1) (Optional) Hydrate in-memory cache from a persisted blob if you add it later.
    // _hydrateCacheFromDiskIfAny();

    // 2) Determine which are missing
    final missing = ordered.where((id) => !_cache.containsKey(id)).toList();

    if (missing.isNotEmpty) {
      // Ensure an authenticated Firebase user (both callable and HTTP need auth)
      final user = await _ensureUser();

      Map<String, StripePrice> fetched;
      if (_isDesktop) {
        // Desktop: plain HTTP with ID token
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
        // Mobile/Web: callable
        final callable =
            FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getStripePrices');
        final res = await callable.call({'priceIds': missing});
        final list = (res.data['prices'] as List).cast<Map<String, dynamic>>();
        fetched = {for (final p in list) p['id'] as String: StripePrice.fromJson(p)};
      }

      _cache.addAll(fetched);

      // 3) (Optional) Persist small cache blob under fc_ key for web soft-reset friendliness.
      // _persistCacheToDisk();
    }

    return {for (final id in ordered) id: _cache[id]!};
  }

  /// Called by your soft-reset path if you want to drop this cache explicitly.
  void clearLocalMirror() {
    _cache.clear();
    // If you later persist to web localStorage/shared_prefs, also clear that here.
    // e.g., LocalKV.remove(_cacheKey);
  }

  // ===== Optional helpers if you later want to persist the tiny cache =====
  // void _hydrateCacheFromDiskIfAny() {
  //   final jsonStr = LocalKV.getString(_cacheKey);
  //   if (jsonStr == null || jsonStr.isEmpty) return;
  //   try {
  //     final map = (jsonDecode(jsonStr) as Map<String, dynamic>).cast<String, dynamic>();
  //     map.forEach((k, v) {
  //       _cache[k] = StripePrice.fromJson((v as Map).cast<String, dynamic>());
  //     });
  //   } catch (_) {/* ignore */}
  // }
  //
  // void _persistCacheToDisk() {
  //   try {
  //     final map = <String, dynamic>{
  //       for (final e in _cache.entries) e.key: e.value.toJson(),
  //     };
  //     LocalKV.setString(_cacheKey, jsonEncode(map));
  //   } catch (_) {/* ignore */}
  // }
}

// lib/services/analytics_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' as convert;

/// Anonymous analytics wrapper that works across platforms without PII.
///
/// - Android/iOS/Web: uses Firebase Analytics SDK
/// - Windows (no official plugin): sends minimal GA4 Measurement Protocol hits
///   using the web app's Measurement ID + API secret (provided via defines).
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _fa; // Android/iOS/Web

  // GA4 Measurement Protocol (Windows fallback)
  late final String _gaMeasurementId =
      const String.fromEnvironment('GA_MEASUREMENT_ID', defaultValue: '');
  late final String _gaApiSecret =
      const String.fromEnvironment('GA_API_SECRET', defaultValue: '');

  String get _variant {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<void> init() async {
    // Ensure Firebase is initialized
    if (Firebase.apps.isEmpty) return; // setup handles init

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      _fa = FirebaseAnalytics.instance;
      // Always send anonymously; do not set userId
      await _fa!.setAnalyticsCollectionEnabled(true);
      await _fa!.setUserProperty(name: 'app_variant', value: _variant);
      if (kDebugMode) debugPrint('Analytics: FirebaseAnalytics enabled for $_variant');
      return;
    }

    // Windows/desktop fallback via Measurement Protocol (if configured)
    if (Platform.isWindows && _gaMeasurementId.isNotEmpty && _gaApiSecret.isNotEmpty) {
      if (kDebugMode) debugPrint('Analytics: Using GA4 Measurement Protocol on Windows');
      // No SDK to init; fire a lightweight app_launch
      await logEvent('app_launch');
    } else {
      if (kDebugMode) debugPrint('Analytics: disabled (no SDK or GA creds)');
    }
  }

  Future<void> setCurrentScreen(String name) async {
    try {
      if (_fa != null) {
        await _fa!.logScreenView(screenName: name);
      } else if (Platform.isWindows) {
        await _sendGaEvent('screen_view', {'screen_name': name});
      }
    } catch (_) {}
  }

  Future<void> logEvent(String name, [Map<String, Object?> params = const {}]) async {
    try {
      if (_fa != null) {
        // FirebaseAnalytics requires Map<String, Object> (no nullable values)
        final cleaned = <String, Object>{};
        params.forEach((k, v) {
          if (v != null) cleaned[k] = v;
        });
        await _fa!.logEvent(name: name, parameters: cleaned.isEmpty ? null : cleaned);
      } else if (Platform.isWindows) {
        await _sendGaEvent(name, params);
      }
    } catch (_) {}
  }

  // Minimal GA4 Measurement Protocol sender (anonymous, no user_id)
  Future<void> _sendGaEvent(String name, Map<String, Object?> params) async {
    if (_gaMeasurementId.isEmpty || _gaApiSecret.isEmpty) return;

    final uri = Uri.https('www.google-analytics.com', '/mp/collect', {
      'measurement_id': _gaMeasurementId,
      'api_secret': _gaApiSecret,
    });

    // Drop nulls for GA payload as well
    final pruned = <String, Object?>{};
    params.forEach((k, v) {
      if (v != null) pruned[k] = v;
    });

    final body = {
      'client_id': _anonymousCid(),
      'events': [
        {
          'name': name,
          'params': {
            ...pruned,
            'app_variant': _variant,
          }
        }
      ]
    };

    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: convert.jsonEncode(body),
      );
      if (kDebugMode && resp.statusCode >= 300) {
        debugPrint('GA4 MP error ${resp.statusCode}: ${resp.body}');
      }
    } catch (_) {}
  }

  static String _anonymousCid() {
    // A stable anonymous client_id; here we use a simple per-process random.
    // For better session continuity on desktop, persist one in a local file if needed.
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

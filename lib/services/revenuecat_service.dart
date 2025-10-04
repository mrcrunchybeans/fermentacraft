// lib/services/revenuecat_service.dart
//
// RevenueCat wrapper that provides the same experience on Android & iOS:
// - Reads API keys from --dart-define (RC_API_KEY_IOS / RC_API_KEY_ANDROID)
// - Configures Purchases exactly once and only when a key is present
// - Mirrors entitlements into your FeatureGate
// - Falls back to Firestore mirror if RC is unavailable/unconfigured
//
// Build-time example:
//   flutter run \
//     --dart-define=RC_API_KEY_ANDROID=goog_xxx \
//     --dart-define=RC_API_KEY_IOS=rc_ios_xxx
//
// CI: pass the same defines in your build step (e.g., GitHub Actions).

import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'local_mode_service.dart';
import 'feature_gate.dart';

class RevenueCatService {
  RevenueCatService._();
  static final instance = RevenueCatService._();

  // ───────────────────────────────────────────────────────────────────────────
  // Keys (prefer to provide at build time via --dart-define)
  // ───────────────────────────────────────────────────────────────────────────
  static const String _kIosKeyFromEnv =
      String.fromEnvironment('RC_API_KEY_IOS', defaultValue: '');
  static const String _kAndroidKeyFromEnv =
      String.fromEnvironment('RC_API_KEY_ANDROID', defaultValue: '');

  // Optional hardcoded fallbacks (keep empty for safety; Android example shown)
  static const String _kIosKeyFallback = '';
  static const String _kAndroidKeyFallback =
      ''; // e.g. 'goog_XXXXXXXX' (leave empty if you always pass via define)

  static String get _iosKey =>
      _kIosKeyFromEnv.isNotEmpty ? _kIosKeyFromEnv : _kIosKeyFallback;
  static String get _androidKey => _kAndroidKeyFromEnv.isNotEmpty
      ? _kAndroidKeyFromEnv
      : _kAndroidKeyFallback;

  static const entitlementId = 'premium';

  // ───────────────────────────────────────────────────────────────────────────
  // Capability / availability checks
  // ───────────────────────────────────────────────────────────────────────────
  bool get _platformSupportsRC {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? get _platformKey {
    if (!_platformSupportsRC) return null;
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosKey;
    if (defaultTargetPlatform == TargetPlatform.android) return _androidKey;
    return null;
  }

  bool get _rcAvailable =>
      _platformSupportsRC && (_platformKey?.isNotEmpty ?? false);

  /// Exposed so UI can choose Paywall vs fallback flows.
  bool get isSupported => _rcAvailable;

  // ───────────────────────────────────────────────────────────────────────────
  // Internal state
  // ───────────────────────────────────────────────────────────────────────────
  bool _serviceInitialized = false; // our wrapper initialized
  bool _rcConfigured = false; // Purchases.configure succeeded
  Future<void>? _rcConfigFuture;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumDocSub;

  // ───────────────────────────────────────────────────────────────────────────
  // Public lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  /// Back-compat for older bootstrap code that called `configure()`.
  Future<void> configure() => init();

  Future<void> init() async {
    if (_serviceInitialized) return;

    // Listen to Firebase user changes; skip first to avoid double work.
    final authStream = FirebaseAuth.instance.authStateChanges();
    final firstUser = await authStream.first;

    _authSub = authStream.skip(1).listen((user) async {
      final local = LocalModeService.instance.isLocalOnly;
      final u = local ? null : user; // force anonymous in local mode

      if (_rcAvailable) {
        await _syncRCWithFirebaseUser(u);
      } else {
        await _syncFirestorePremium(u);
      }
    });

    // Seed once on startup
    final firstLocal = LocalModeService.instance.isLocalOnly;
    final seedUser = firstLocal ? null : firstUser;
    if (_rcAvailable) {
      await _syncRCWithFirebaseUser(seedUser);
    } else {
      await _syncFirestorePremium(seedUser);
    }

    _serviceInitialized = true;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _premiumDocSub?.cancel();
    _authSub = null;
    _premiumDocSub = null;
    _serviceInitialized = false;
    _rcConfigured = false;
    _rcConfigFuture = null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // RC configuration
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _ensureRCConfigured() {
    if (!_rcAvailable) {
      _rcConfigured = false;
      return Future.value();
    }
    if (_rcConfigured) return Future.value();
    if (_rcConfigFuture != null) return _rcConfigFuture!;

    _rcConfigFuture = () async {
      final apiKey = _platformKey!;
      if (apiKey.isEmpty) {
        _rcConfigured = false;
        return;
      }

      // Purchases 9.x: simple constructor; no observerMode setter.
      final configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);

      // Keep FeatureGate in sync whenever RC updates
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        FeatureGate.instance.refreshFromCustomerInfo(customerInfo);
      });

      // Seed FeatureGate from current RC state if possible
      try {
        final info = await Purchases.getCustomerInfo();
        FeatureGate.instance.refreshFromCustomerInfo(info);
      } catch (_) {
        // ignore; will refresh later
      }

      _rcConfigured = true;
    }();

    return _rcConfigFuture!;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // RC path (Android/iOS)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _syncRCWithFirebaseUser(User? user) async {
    if (!_rcAvailable) {
      // No key? behave like desktop/web mirror
      await _syncFirestorePremium(user);
      return;
    }

    try {
      await _ensureRCConfigured();
      if (!_rcConfigured) {
        await _syncFirestorePremium(user);
        return;
      }

      if (user == null) {
        // Only logOut if not already anonymous to avoid warnings
        try {
          final currentId = await Purchases.appUserID;
          final isAnon =
              currentId.isEmpty || currentId.startsWith(r'$RCAnonymousID');
          if (!isAnon) {
            await Purchases.logOut();
          }
        } catch (_) {}
        FeatureGate.instance.setFromBackend(false);
        return;
      }

      // Link Firebase UID to RC if needed
      try {
        final currentId = await Purchases.appUserID;
        if (currentId != user.uid) {
          await Purchases.logIn(user.uid);
        }
      } catch (_) {
        // continue with current identity
      }

      // Optional: call a function to mirror RC -> Firestore, then read it
      try {
        final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('syncPremiumFromRC');
        await fn.call(<String, dynamic>{});

        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('premium')
            .doc('status')
            .get();
        final active = (snap.data()?['active'] as bool?) ?? false;
        FeatureGate.instance.setFromBackend(active);
      } catch (_) {
        // ignore; RC state still authoritative below
      }

      // Fresh RC pull (real purchases or promo entitlements)
      final info = await _safeGetCustomerInfo(forceSync: true);
      if (info != null) {
        FeatureGate.instance.refreshFromCustomerInfo(info);
      }
    } catch (_) {
      // keep last known state
    }
  }

  Future<CustomerInfo?> _safeGetCustomerInfo({bool forceSync = false}) async {
    if (!_rcConfigured) return null;
    try {
      if (forceSync) {
        await Purchases.syncPurchases();
      }
      return await Purchases.getCustomerInfo();
    } catch (_) {
      return null;
    }
  }

  // Public RC APIs (guarded)

  Future<Offerings> getOfferings() async {
    if (!_rcAvailable) {
      throw UnsupportedError('RevenueCat not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError(
          'RevenueCat not configured: missing API key or configure failed.');
    }
    return Purchases.getOfferings();
  }

  Future<CustomerInfo> purchasePackage(Package pkg) async {
    if (!_rcAvailable) {
      throw UnsupportedError('Purchases not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError('RevenueCat not configured.');
    }
    // purchases_flutter 9.x returns PurchaseResult, extract CustomerInfo
    final result = await Purchases.purchasePackage(pkg);
    FeatureGate.instance.refreshFromCustomerInfo(result.customerInfo);
    return result.customerInfo;
  }

  /// iOS-style restore (safe). Prefer `sync()` on Android.
  Future<CustomerInfo> restore() async {
    if (!_rcAvailable) {
      throw UnsupportedError('Restore not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError('RevenueCat not configured.');
    }
    final info = await Purchases.restorePurchases();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  /// Android-safe “refresh” that does not alias other Play users on device.
  Future<CustomerInfo> sync() async {
    if (!_rcAvailable) {
      throw UnsupportedError('Sync not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError('RevenueCat not configured.');
    }
    await Purchases.syncPurchases();
    final info = await Purchases.getCustomerInfo();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  /// Force-fetch latest CustomerInfo and mirror into FeatureGate.
  Future<CustomerInfo> refreshCustomerInfo() async {
    if (!_rcAvailable) {
      throw UnsupportedError('CustomerInfo not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError('RevenueCat not configured.');
    }
    final info = await Purchases.getCustomerInfo();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Desktop/Web style Firestore mirror (fallback)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _syncFirestorePremium(User? user) async {
    await _premiumDocSub?.cancel();
    _premiumDocSub = null;

    FeatureGate.instance.setFromBackend(false);
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('premium')
        .doc('status'); // users/{uid}/premium/status

    _premiumDocSub = docRef.snapshots().listen((snap) async {
      final data = snap.data();
      final premiumActive = (data?['active'] as bool?) ?? false;
      final proOfflineOwned = (data?['proOffline'] as bool?) ?? false;

      if (premiumActive) {
        FeatureGate.instance.setFromBackend(true);
      } else {
        // Clear backend premium; allow Pro-Offline if set in mirror
        FeatureGate.instance.setFromBackend(false);
        if (proOfflineOwned) {
          await FeatureGate.instance.activateProOffline();
        }
      }
    });
  }
}

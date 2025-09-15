// lib/services/revenuecat_service.dart
//
// Safe RevenueCat wrapper that never calls Purchases.* unless configured.
// - Reads API keys from --dart-define (RC_API_KEY_IOS / RC_API_KEY_ANDROID)
// - Guards all Purchases calls
// - Falls back to Firestore mirror when RC is unavailable or unconfigured

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'local_mode_service.dart';
import 'feature_gate.dart';

class RevenueCatService {
  RevenueCatService._();
  static final instance = RevenueCatService._();

  // ── Keys ───────────────────────────────────────────────────────────────────
  // Prefer passing these at build time:
  //   --dart-define=RC_API_KEY_IOS=rc_ios_... --dart-define=RC_API_KEY_ANDROID=goog_...
  static const String _kIosKeyFromEnv =
      String.fromEnvironment('RC_API_KEY_IOS', defaultValue: '');
  static const String _kAndroidKeyFromEnv =
      String.fromEnvironment('RC_API_KEY_ANDROID', defaultValue: '');

  // Optional hardcoded fallbacks (leave empty for safety)
  static const String _kIosKeyFallback = ''; // e.g., 'rc_ios_xxx'
  static const String _kAndroidKeyFallback = 'goog_NLVqxCUYZETbdnxlAqMHfjiXAzx';

  static String get _iosKey => _kIosKeyFromEnv.isNotEmpty ? _kIosKeyFromEnv : _kIosKeyFallback;
  static String get _androidKey =>
      _kAndroidKeyFromEnv.isNotEmpty ? _kAndroidKeyFromEnv : _kAndroidKeyFallback;

  static const entitlementId = 'premium';

  // ── Capability checks ──────────────────────────────────────────────────────
  bool get _platformSupportsRC =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  String? get _platformKey {
    if (!_platformSupportsRC) return null;
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosKey;
    if (defaultTargetPlatform == TargetPlatform.android) return _androidKey;
    return null;
  }

  bool get _rcAvailable => _platformSupportsRC && (_platformKey?.isNotEmpty ?? false);

  /// Exposed so UI can decide between RC vs Stripe/Firestore flows.
  bool get isSupported => _rcAvailable;

  // ── Internal state ─────────────────────────────────────────────────────────
  bool _configured = false;      // service initialized
  bool _rcConfigured = false;    // Purchases.configure completed successfully
  Future<void>? _rcConfigFuture;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumDocSub;

  // ── Public lifecycle ───────────────────────────────────────────────────────
  Future<void> init() async {
    if (_configured) return;

    // Listen to Firebase user changes (skip first to avoid double-work)
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

    // Seed once
    final firstLocal = LocalModeService.instance.isLocalOnly;
    final seedUser = firstLocal ? null : firstUser;
    if (_rcAvailable) {
      await _syncRCWithFirebaseUser(seedUser);
    } else {
      await _syncFirestorePremium(seedUser);
    }

    _configured = true;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _premiumDocSub?.cancel();
    _authSub = null;
    _premiumDocSub = null;
    _configured = false;
    _rcConfigured = false;
    _rcConfigFuture = null;
  }

  // ── RC configuration ───────────────────────────────────────────────────────
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
        // Not available; ensure we mark as unconfigured and bail
        _rcConfigured = false;
        return;
      }

      // Configure exactly once
      final config = PurchasesConfiguration(apiKey)
        ..observerMode = false
        ..appUserID = null;

      await Purchases.configure(config);

      // Mirror entitlements into FeatureGate whenever RC updates
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        FeatureGate.instance.refreshFromCustomerInfo(customerInfo);
      });

      // Seed FeatureGate from current RC state if possible
      try {
        final info = await Purchases.getCustomerInfo();
        FeatureGate.instance.refreshFromCustomerInfo(info);
      } catch (_) {
        // no-op
      }

      _rcConfigured = true;
    }();

    return _rcConfigFuture!;
  }

  // ── RC path (Android/iOS) ──────────────────────────────────────────────────
  Future<void> _syncRCWithFirebaseUser(User? user) async {
    // If RC not available (no key) → NEVER call Purchases.* (fallback to Firestore)
    if (!_rcAvailable) {
      await _syncFirestorePremium(user);
      return;
    }

    try {
      await _ensureRCConfigured();
      if (!_rcConfigured) {
        // Still not configured (e.g., bad/missing key) → fallback
        await _syncFirestorePremium(user);
        return;
      }

      if (user == null) {
        // Avoid RC warnings: only logOut if current appUserID is not anonymous
        try {
          final currentId = await Purchases.appUserID;
          final isAnon = currentId.isEmpty || currentId.startsWith(r'$RCAnonymousID');
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
        // If linking fails, continue with current identity
      }

      // (Optional) server mirror: syncPremiumFromRC then read users/{uid}/premium/status
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
        // ignore; keep RC state
      }

      // Fresh pull from RC (real purchases or entitlements)
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

  Future<Offerings> getOfferings() async {
    if (!_rcAvailable) {
      throw UnsupportedError('RevenueCat not available on this platform.');
    }
    await _ensureRCConfigured();
    if (!_rcConfigured) {
      throw StateError('RevenueCat not configured: missing API key or configure failed.');
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
    final result = await Purchases.purchasePackage(pkg);
    final info = result.customerInfo;
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
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

  /// Force-fetch latest CustomerInfo from RevenueCat and mirror into FeatureGate.
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

  // ── Desktop/Web path (Firestore mirror) ────────────────────────────────────
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
      final premiumActive   = (data?['active'] as bool?) ?? false;
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

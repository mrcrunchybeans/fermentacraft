import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'local_mode_service.dart';
import 'feature_gate.dart';
// ⛔️ remove any tester-allowlist logic on RC platforms to avoid extra reads
// import 'tester_premium_service.dart';

class RevenueCatService {
  RevenueCatService._();
  static final instance = RevenueCatService._();

  // ── Configure your keys ────────────────────────────────────────────────────
  static const _androidKey = 'goog_NLVqxCUYZETbdnxlAqMHfjiXAzx';
  static const _iosKey     = ''; // add when shipping iOS
  static const entitlementId = 'premium';

  // ── Internal state ─────────────────────────────────────────────────────────
  bool _configured = false;     // service init done
  bool _rcConfigured = false;   // RC SDK configured
  Future<void>? _rcConfigFuture; // guard against double-config

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumDocSub;

  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  /// Exposed so UI can decide between RC vs Stripe flows.
  bool get isSupported => _rcSupported;

  // ── Public lifecycle ───────────────────────────────────────────────────────
  Future<void> init() async {
    if (_configured) return;

    // Seed once, then listen (skip the first event to avoid double-work)
    final authStream = FirebaseAuth.instance.authStateChanges();
    final firstUser = await authStream.first;

    _authSub = authStream.skip(1).listen((user) async {
      final local = LocalModeService.instance.isLocalOnly;
      final u = local ? null : user; // force anonymous in local mode
      if (_rcSupported) {
        await _syncRCWithFirebaseUser(u);
      } else {
        await _syncFirestorePremium(u);
    }
    });

    // Seed once
  final firstLocal = LocalModeService.instance.isLocalOnly;
  final seedUser = firstLocal ? null : firstUser;
  if (_rcSupported) {
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
  }

  // ── RC path (Android/iOS) ──────────────────────────────────────────────────
  Future<void> _ensureRCConfigured() {
    if (!_rcSupported) return Future.value();
    if (_rcConfigured) return Future.value();
    if (_rcConfigFuture != null) return _rcConfigFuture!;

    _rcConfigFuture = () async {
      final apiKey = (defaultTargetPlatform == TargetPlatform.android)
          ? _androidKey
          : _iosKey;

      if (apiKey.isEmpty) {
        // No key for this platform; treat as unsupported
        return;
      }

      await Purchases.configure(PurchasesConfiguration(apiKey));

      // Mirror entitlements into FeatureGate whenever RC updates
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        FeatureGate.instance.refreshFromCustomerInfo(customerInfo);
      });

      // Seed from current RC state if possible
      try {
        final info = await Purchases.getCustomerInfo();
        FeatureGate.instance.refreshFromCustomerInfo(info);
      } catch (_) {}

      _rcConfigured = true;
    }();

    return _rcConfigFuture!;
  }

Future<void> _syncRCWithFirebaseUser(User? user) async {
  if (!_rcSupported) return;

  try {
    await _ensureRCConfigured();

    if (user == null) {
      // Only call logOut if we're not already anonymous to avoid RC warnings
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

    final currentId = await Purchases.appUserID;
    if (currentId != user.uid) {
      try { await Purchases.logIn(user.uid); } catch (_) {}
    }

    // Optionally sync tester allowlist + mirror Firestore (server-side)
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('syncPremiumFromRC');
      await fn.call(<String, dynamic>{});

      // Read the mirror and update the FeatureGate
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('premium').doc('status')
          .get();
      final active = (snap.data()?['active'] as bool?) ?? false;
      FeatureGate.instance.setFromBackend(active);
    } catch (_) {
      // ignore; keep RC state
    }

    // Fresh pull from RC (real purchases or promo entitlements)
    final info = await _safeGetCustomerInfo(forceSync: true);
    if (info != null) {
      FeatureGate.instance.refreshFromCustomerInfo(info);
    }
  } catch (_) {
    // keep last known state
  }
}


  Future<CustomerInfo?> _safeGetCustomerInfo({bool forceSync = false}) async {
    if (!_rcSupported) return null;
    try {
      if (forceSync) {
        await Purchases.syncPurchases();
      }
      final info = await Purchases.getCustomerInfo();
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<Offerings> getOfferings() async {
    if (!_rcSupported) {
      throw UnsupportedError('RevenueCat not available on this platform.');
    }
    await _ensureRCConfigured();
    return Purchases.getOfferings();
  }

  Future<CustomerInfo> purchasePackage(Package pkg) async {
    if (!_rcSupported) {
      throw UnsupportedError('Purchases not available on this platform.');
    }
    await _ensureRCConfigured();
    final result = await Purchases.purchasePackage(pkg);
    final info = result.customerInfo;
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  /// iOS-style restore (safe). Prefer `sync()` on Android.
  Future<CustomerInfo> restore() async {
    if (!_rcSupported) {
      throw UnsupportedError('Restore not available on this platform.');
    }
    await _ensureRCConfigured();
    final info = await Purchases.restorePurchases();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  /// Android-safe “refresh” that does not alias other Play users on device.
  Future<CustomerInfo> sync() async {
    if (!_rcSupported) {
      throw UnsupportedError('Sync not available on this platform.');
    }
    await _ensureRCConfigured();
    await Purchases.syncPurchases();
    final info = await Purchases.getCustomerInfo();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  /// Force-fetch latest CustomerInfo from RevenueCat and mirror into FeatureGate.
  Future<CustomerInfo> refreshCustomerInfo() async {
    if (!_rcSupported) {
      throw UnsupportedError('CustomerInfo not available on this platform.');
    }
    await _ensureRCConfigured();
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

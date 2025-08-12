// lib/services/revenuecat_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'feature_gate.dart';
import 'tester_premium_service.dart'; // ⬅️ NEW (calls the Cloud Function)

class RevenueCatService {
  RevenueCatService._();
  static final instance = RevenueCatService._();

  // ── Configure your keys ────────────────────────────────────────────────────
  static const _androidKey = 'goog_UtmkZanhtAfZZhUtNfrKGiBueUu';
  static const _iosKey     = ''; // TODO: add when you ship iOS
  static const entitlementId = 'premium';

  // ── Internal state ─────────────────────────────────────────────────────────
  bool _configured = false;     // service init done
  bool _rcConfigured = false;   // RC SDK configured
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumDocSub;

  // Prevent spamming the CF: remember the last UID we attempted to claim for
  String? _lastClaimAttemptUid;

  // RevenueCat only supports Android/iOS via purchases_flutter
  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  /// Exposed so UI can decide between RC vs Stripe flows.
  bool get isSupported => _rcSupported;

  // ── Public lifecycle ───────────────────────────────────────────────────────
  Future<void> init() async {
    if (_configured) return;

    // Wait for a definitive initial auth state, then attach listener.
    final firstUser = await FirebaseAuth.instance.authStateChanges().first;

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (_rcSupported) {
        await _syncRCWithFirebaseUser(user);
      } else {
        await _syncFirestorePremium(user);
      }
    });

    // Seed state once we know who is signed in
    if (_rcSupported) {
      await _syncRCWithFirebaseUser(firstUser);
    } else {
      await _syncFirestorePremium(firstUser);
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
  Future<void> _ensureRCConfigured() async {
    if (_rcConfigured || !_rcSupported) return;

    final apiKey = (defaultTargetPlatform == TargetPlatform.android)
        ? _androidKey
        : _iosKey;

    if (apiKey.isEmpty) {
      // No key for this platform; treat as unsupported
      return;
    }

    final conf = PurchasesConfiguration(apiKey);
    await Purchases.configure(conf);

    // Mirror entitlements into FeatureGate whenever RC updates
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      FeatureGate.instance.refreshFromCustomerInfo(customerInfo);
    });

    // Seed from current RC state (ignore if not available yet)
    try {
      final info = await Purchases.getCustomerInfo();
      FeatureGate.instance.refreshFromCustomerInfo(info);
    } catch (_) {}

    _rcConfigured = true;
  }

  Future<void> _syncRCWithFirebaseUser(User? user) async {
    if (!_rcSupported) return;

    try {
      await _ensureRCConfigured();

      if (user == null) {
        try { await Purchases.logOut(); } catch (_) {}
        FeatureGate.instance.setFromBackend(false);
        _lastClaimAttemptUid = null;
        return;
      }

      // Log into RC with Firebase UID
      try { await Purchases.logIn(user.uid); } catch (_) {}

      // First refresh: do we already have premium?
      var info = await _safeGetCustomerInfo();
      final hasPremiumNow = info != null && _hasPremium(info);

      if (!hasPremiumNow) {
        // Try to claim tester premium only once per UID (if allowlisted)
        if (_lastClaimAttemptUid != user.uid) {
          _lastClaimAttemptUid = user.uid;
          try {
            final claimed = await TesterPremiumService.instance.claim();
            if (claimed) {
              // Pull fresh entitlements after claim
              info = await _safeGetCustomerInfo(forceSync: true);
            }
          } catch (_) {
            // ignore; fall back to whatever RC says
          }
        }
      }

      // final mirror to FeatureGate from latest info (if we have it)
      if (info != null) {
        FeatureGate.instance.refreshFromCustomerInfo(info);
      } else {
        // as a fallback, keep previous state
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

  bool _hasPremium(CustomerInfo info) {
    final ent = info.entitlements.all[entitlementId];
    return ent?.isActive == true;
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

  Future<CustomerInfo> restore() async {
    if (!_rcSupported) {
      throw UnsupportedError('Restore not available on this platform.');
    }
    await _ensureRCConfigured();
    final info = await Purchases.restorePurchases();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

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
    _lastClaimAttemptUid = null;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('premium')
        .doc('status'); // users/{uid}/premium/status

    _premiumDocSub = docRef.snapshots().listen((snap) {
      final data = snap.data();
      final active = (data?['active'] as bool?) ?? false;
      FeatureGate.instance.setFromBackend(active);
    });
  }
}

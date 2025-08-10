import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'feature_gate.dart';

class RevenueCatService {
  RevenueCatService._();
  static final instance = RevenueCatService._();

  static const _androidKey = 'goog_UtmkZanhtAfZZhUtNfrKGiBueUu';
  static const _iosKey     = ''; // add later if/when you ship iOS
  static const entitlementId = 'premium';

  bool _configured = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumDocSub;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (_configured) return;

    // Listen to Firebase auth changes and keep RC / backend mirrors aligned.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (_isMobile) {
        await _syncRCWithFirebaseUser(user);
      } else {
        await _syncFirestorePremium(user);
      }
    });

    if (_isMobile) {
      // Configure RevenueCat once on mobile
      final apiKey = Platform.isAndroid ? _androidKey : _iosKey;
      if (apiKey.isNotEmpty) {
        final conf = PurchasesConfiguration(apiKey);
        await Purchases.configure(conf);

        // Keep FeatureGate mirrored to RC at all times
        Purchases.addCustomerInfoUpdateListener((customerInfo) {
          FeatureGate.instance.refreshFromCustomerInfo(customerInfo);
        });

        // Seed FeatureGate from current RC state
        try {
          final info = await Purchases.getCustomerInfo();
          FeatureGate.instance.refreshFromCustomerInfo(info);
        } catch (_) {}
      }

      // Seed from current auth user
      await _syncRCWithFirebaseUser(FirebaseAuth.instance.currentUser);
    } else {
      // Desktop/Web: seed from Firestore mirror
      await _syncFirestorePremium(FirebaseAuth.instance.currentUser);
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

  // ---- Mobile (RevenueCat SDK) ----
  Future<void> _syncRCWithFirebaseUser(User? user) async {
    if (!_isMobile) return;
    try {
      if (user == null) {
        // Log out of RC -> entitlements should be cleared
        await Purchases.logOut();
        // Clear locally from a trusted source (backend/app state)
        FeatureGate.instance.setFromBackend(false);
        return;
      }
      // Log in to RC with stable user id (Firebase UID)
      try { await Purchases.logIn(user.uid); } catch (_) {}
      await _refreshEntitlements();
    } catch (_) {
      // ignore; user remains on last known state
    }
  }

  Future<bool> _refreshEntitlements() async {
    try {
      final info = await Purchases.getCustomerInfo();
      FeatureGate.instance.refreshFromCustomerInfo(info);
      return _hasPremium(info);
    } catch (_) {
      return false;
    }
  }

  bool _hasPremium(CustomerInfo info) {
    final ent = info.entitlements.all[entitlementId];
    return ent?.isActive == true;
  }

  Future<Offerings> getOfferings() => Purchases.getOfferings();

  Future<CustomerInfo> purchasePackage(Package pkg) async {
    final result = await Purchases.purchasePackage(pkg);
    final info = result.customerInfo;
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  Future<CustomerInfo> restore() async {
    final info = await Purchases.restorePurchases();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  Future<CustomerInfo> sync() async {
    await Purchases.syncPurchases();
    final info = await Purchases.getCustomerInfo();
    FeatureGate.instance.refreshFromCustomerInfo(info);
    return info;
  }

  // ---- Desktop/Web (Firestore mirror as trusted backend) ----
  Future<void> _syncFirestorePremium(User? user) async {
    await _premiumDocSub?.cancel();
    _premiumDocSub = null;

    // Default to free until backend says otherwise
    FeatureGate.instance.setFromBackend(false);
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('premium')
        .doc('status'); // e.g., users/{uid}/premium/status

    _premiumDocSub = docRef.snapshots().listen((snap) {
      final data = snap.data();
      final active = (data?['active'] as bool?) ?? false;
      // Apply from a trusted backend source (not from UI)
      FeatureGate.instance.setFromBackend(active);
    });
  }
}

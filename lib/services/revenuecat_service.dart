// lib/services/revenuecat_service.dart
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

    // Start listening to Firebase user changes
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (_isMobile) {
        await _syncRCWithFirebaseUser(user);
      } else {
        await _syncFirestorePremium(user);
      }
    });

    if (_isMobile) {
      // Configure RC once on mobile
      final apiKey = Platform.isAndroid ? _androidKey : _iosKey;
      if (apiKey.isEmpty) {
        // On iOS without a key, just no-op
      } else {
        final conf = PurchasesConfiguration(apiKey);
        await Purchases.configure(conf);
        Purchases.addCustomerInfoUpdateListener((customerInfo) {
          FeatureGate.instance.setPremium(_hasPremium(customerInfo));
        });
      }
      // Seed from current
      await _syncRCWithFirebaseUser(FirebaseAuth.instance.currentUser);
    } else {
      // Desktop/Web: seed Firestore-based premium
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

  // ---- Mobile (RC SDK) ----
  Future<void> _syncRCWithFirebaseUser(User? user) async {
    if (!_isMobile) return;
    try {
      if (user == null) {
        await Purchases.logOut();
        FeatureGate.instance.setPremium(false);
        return;
      }
      try { await Purchases.logIn(user.uid); } catch (_) {}
      await _refreshEntitlements();
    } catch (_) {
      // swallow
    }
  }

  Future<bool> _refreshEntitlements() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final isPremium = _hasPremium(info);
      FeatureGate.instance.setPremium(isPremium);
      return isPremium;
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
    FeatureGate.instance.setPremium(_hasPremium(info));
    return info;
  }

  Future<CustomerInfo> restore() async {
    final info = await Purchases.restorePurchases();
    FeatureGate.instance.setPremium(_hasPremium(info));
    return info;
  }

  // ---- Desktop/Web (Firestore mirror) ----
  Future<void> _syncFirestorePremium(User? user) async {
    await _premiumDocSub?.cancel();
    _premiumDocSub = null;
    FeatureGate.instance.setPremium(false);
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('premium')
        .doc('status'); // e.g., users/{uid}/premium/status

    _premiumDocSub = docRef.snapshots().listen((snap) {
      final data = snap.data();
      final active = (data?['active'] as bool?) ?? false;
      FeatureGate.instance.setPremium(active);
    });
  }
}

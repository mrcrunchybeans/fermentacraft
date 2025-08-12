import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class TesterPremiumService {
  TesterPremiumService._();
  static final instance = TesterPremiumService._();

  /// Calls the Cloud Function, then refreshes RevenueCat entitlements.
  Future<bool> claim() async {
    final u = FirebaseAuth.instance.currentUser;

    // Make sure RC is logged in as the Firebase UID
    if (u != null) {
      await Purchases.logIn(u.uid);
    } else {
      debugPrint('claimTesterPremium: no auth user.');
      return false;
    }

    try {
      // If your function is not in the default region, set it:
      // FirebaseFunctions.instanceFor(region: 'us-central1')
      final res = await FirebaseFunctions.instance
          .httpsCallable('ensureTesterPremium')
          .call();

      // Immediately refresh entitlements
      await Purchases.syncPurchases();
      final info = await Purchases.getCustomerInfo();
      final hasPremium = info.entitlements.active.containsKey('premium');

      debugPrint('ensureTesterPremium -> ${res.data}, RC premium=$hasPremium');
      return hasPremium;
    } catch (e) {
      debugPrint('ensureTesterPremium failed: $e');
      return false;
    }
  }
}

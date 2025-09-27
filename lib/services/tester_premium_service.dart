import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_logger.dart';

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
      PremiumLogger.purchaseResult(
        userId: 'anonymous',
        productId: 'tester_premium',
        success: false,
        error: 'No authenticated user',
      );
      return false;
    }

    PremiumLogger.purchaseAttempt(
      userId: u.uid,
      productId: 'tester_premium',
      operation: 'claim_tester_premium',
    );

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

      PremiumLogger.purchaseResult(
        userId: u.uid,
        productId: 'tester_premium',
        success: hasPremium,
        transactionId: res.data?.toString(),
      );
      
      return hasPremium;
    } catch (e) {
      PremiumLogger.purchaseResult(
        userId: u.uid,
        productId: 'tester_premium',
        success: false,
        error: e,
      );
      return false;
    }
  }
}

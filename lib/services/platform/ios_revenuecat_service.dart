// lib/services/platform/ios_revenuecat_service.dart
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../utils/result.dart';

/// iOS-specific RevenueCat implementation for App Store subscriptions
class IOSRevenueCatService {
  static bool _isConfigured = false;
  static const String _apiKey = 'appl_your_api_key_here'; // Replace with actual key
  
  /// Configure RevenueCat for iOS
  static Future<Result<void, Exception>> configure() async {
    try {
      if (_isConfigured) {
        return const Success(null);
      }

      print('Configuring RevenueCat for iOS...');
      
      // iOS-specific configuration
      final configuration = PurchasesConfiguration(_apiKey);
      
      // Set iOS-specific user attributes
      configuration.appUserID = null; // Use anonymous ID initially
      
      await Purchases.configure(configuration);
      
      // Set platform-specific attributes
      await Purchases.setAttributes({
        'platform': 'iOS',
        'app_version': '2.5.0', // This should come from package_info_plus
      });

      _isConfigured = true;
      print('RevenueCat configured successfully for iOS');
      
      return const Success(null);
    } catch (e) {
      print('Failed to configure RevenueCat for iOS: $e');
      return Failure(Exception('RevenueCat configuration failed: $e'));
    }
  }

  /// Get available iOS subscription products
  static Future<Result<List<Package>, Exception>> getAvailableProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current == null) {
        return Failure(Exception('No subscription offerings available'));
      }

      final packages = offerings.current!.availablePackages;
      print('Found ${packages.length} iOS subscription packages');
      
      return Success(packages);
    } catch (e) {
      print('Failed to get iOS subscription products: $e');
      return Failure(Exception('Failed to load subscription products: $e'));
    }
  }

  /// Purchase iOS subscription
  static Future<Result<CustomerInfo, Exception>> purchaseProduct(Package package) async {
    try {
      print('Attempting to purchase iOS package: ${package.identifier}');
      
      final purchaserInfo = await Purchases.purchasePackage(package);
      
      print('iOS purchase successful: ${purchaserInfo.customerInfo.entitlements.all}');
      
      return Success(purchaserInfo.customerInfo);
    } catch (e) {
      print('iOS purchase failed: $e');
      
      if (e is PlatformException) {
        final errorCode = e.code;
        final errorMessage = e.message ?? 'Unknown error';
        
        // Handle iOS-specific error codes
        switch (errorCode) {
          case 'PURCHASE_CANCELLED':
            return Failure(Exception('Purchase was cancelled by user'));
          case 'STORE_PROBLEM':
            return Failure(Exception('App Store connection problem'));
          case 'PURCHASE_NOT_ALLOWED':
            return Failure(Exception('Purchases not allowed on this device'));
          default:
            return Failure(Exception('Purchase failed: $errorMessage'));
        }
      }
      
      return Failure(Exception('Purchase failed: $e'));
    }
  }

  /// Restore iOS purchases
  static Future<Result<CustomerInfo, Exception>> restorePurchases() async {
    try {
      print('Restoring iOS purchases...');
      
      final customerInfo = await Purchases.restorePurchases();
      
      print('iOS purchases restored successfully');
      
      return Success(customerInfo);
    } catch (e) {
      print('Failed to restore iOS purchases: $e');
      return Failure(Exception('Failed to restore purchases: $e'));
    }
  }

  /// Check current iOS subscription status
  static Future<Result<bool, Exception>> isPremiumActive() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      
      // Check for active entitlements
      final isPremium = customerInfo.entitlements.active.isNotEmpty;
      
      print('iOS Premium status: $isPremium');
      
      return Success(isPremium);
    } catch (e) {
      print('Failed to check iOS premium status: $e');
      return Failure(Exception('Failed to check premium status: $e'));
    }
  }

  /// Get customer info with iOS-specific details
  static Future<Result<CustomerInfo, Exception>> getCustomerInfo() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return Success(customerInfo);
    } catch (e) {
      print('Failed to get iOS customer info: $e');
      return Failure(Exception('Failed to get customer info: $e'));
    }
  }

  /// Set iOS user ID for RevenueCat
  static Future<Result<void, Exception>> setUserID(String userID) async {
    try {
      await Purchases.logIn(userID);
      
      // Set additional iOS-specific attributes
      await Purchases.setAttributes({
        'platform': 'iOS',
        'user_id': userID,
        'login_timestamp': DateTime.now().toIso8601String(),
      });
      
      print('iOS user ID set successfully: $userID');
      
      return const Success(null);
    } catch (e) {
      print('Failed to set iOS user ID: $e');
      return Failure(Exception('Failed to set user ID: $e'));
    }
  }

  /// Handle iOS subscription lifecycle events
  static Future<Result<void, Exception>> handleSubscriptionEvent(
    String eventType, 
    Map<String, dynamic> eventData,
  ) async {
    try {
      print('Handling iOS subscription event: $eventType');
      
      // iOS-specific subscription event handling
      switch (eventType) {
        case 'subscription_started':
          await _handleSubscriptionStarted(eventData);
          break;
        case 'subscription_renewed':
          await _handleSubscriptionRenewed(eventData);
          break;
        case 'subscription_cancelled':
          await _handleSubscriptionCancelled(eventData);
          break;
        case 'subscription_expired':
          await _handleSubscriptionExpired(eventData);
          break;
        default:
          print('Unknown iOS subscription event: $eventType');
      }
      
      return const Success(null);
    } catch (e) {
      print('Failed to handle iOS subscription event: $e');
      return Failure(Exception('Failed to handle subscription event: $e'));
    }
  }

  static Future<void> _handleSubscriptionStarted(Map<String, dynamic> data) async {
    print('iOS subscription started: $data');
    // Handle subscription start logic
  }

  static Future<void> _handleSubscriptionRenewed(Map<String, dynamic> data) async {
    print('iOS subscription renewed: $data');
    // Handle subscription renewal logic
  }

  static Future<void> _handleSubscriptionCancelled(Map<String, dynamic> data) async {
    print('iOS subscription cancelled: $data');
    // Handle subscription cancellation logic
  }

  static Future<void> _handleSubscriptionExpired(Map<String, dynamic> data) async {
    print('iOS subscription expired: $data');
    // Handle subscription expiration logic
  }

  /// iOS-specific cleanup
  static Future<Result<void, Exception>> cleanup() async {
    try {
      // Perform any iOS-specific cleanup
      _isConfigured = false;
      print('iOS RevenueCat service cleaned up');
      return const Success(null);
    } catch (e) {
      return Failure(Exception('Failed to cleanup iOS RevenueCat service: $e'));
    }
  }
}
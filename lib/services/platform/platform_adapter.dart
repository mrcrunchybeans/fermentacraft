// lib/services/platform/platform_adapter.dart
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../service_locator.dart';
import '../../utils/result.dart';
import 'ios_auth_service.dart';
import 'ios_file_service.dart';
import 'ios_revenuecat_service.dart';

/// Platform-adaptive service layer that automatically chooses
/// the appropriate implementation based on the current platform
class PlatformAdapter {
  
  /// Initialize platform-specific services
  static Future<Result<void, Exception>> initializePlatformServices() async {
    try {
  debugPrint('Initializing platform services for: ${Platform.operatingSystem}');
      
      if (Platform.isIOS) {
  debugPrint('Setting up iOS-specific services...');
        
        // Configure iOS-specific RevenueCat
        final revenueCatResult = await IOSRevenueCatService.configure();
        if (revenueCatResult is Failure) {
          debugPrint('Warning: iOS RevenueCat configuration failed: ${revenueCatResult.error}');
          // Don't fail initialization for RevenueCat issues
        }
        
        // Initialize iOS file system
        final storageResult = await IOSFileService.checkStorageStatus();
        if (storageResult is Failure) {
          return Failure(Exception('iOS file system not accessible: ${storageResult.error}'));
        }
        
        debugPrint('iOS platform services initialized successfully');
      } else {
        debugPrint('Using default platform services for ${Platform.operatingSystem}');
      }
      
      return const Success(null);
    } catch (e) {
      debugPrint('Failed to initialize platform services: $e');
      return Failure(Exception('Platform services initialization failed: $e'));
    }
  }

  /// Platform-adaptive authentication
  static Future<Result<User, Exception>> signInWithGoogle() async {
    if (Platform.isIOS) {
      return IOSAuthService.signInWithGoogle();
    } else {
      // Use existing auth service for other platforms
      return ServiceLocator.get<AuthService>().signInWithGoogle();
    }
  }

  /// Platform-adaptive sign out
  static Future<Result<void, Exception>> signOut() async {
    if (Platform.isIOS) {
      return IOSAuthService.signOut();
    } else {
      // Use existing auth service for other platforms
      return ServiceLocator.get<AuthService>().signOut();
    }
  }

  /// Platform-adaptive file operations
  static Future<Result<String?, Exception>> pickRecipeFile() async {
    if (Platform.isIOS) {
      return IOSFileService.pickRecipeFile();
    } else {
      // Use existing file service for other platforms
      return ServiceLocator.get<FileService>().pickRecipeFile();
    }
  }

  /// Platform-adaptive file sharing
  static Future<Result<void, Exception>> shareRecipeFile(String filePath, String fileName) async {
    if (Platform.isIOS) {
      return IOSFileService.shareRecipeFile(filePath, fileName);
    } else {
      // Use existing file service for other platforms
      return ServiceLocator.get<FileService>().shareRecipeFile(filePath, fileName);
    }
  }

  /// Platform-adaptive premium subscription check
  static Future<Result<bool, Exception>> isPremiumActive() async {
    if (Platform.isIOS) {
      return IOSRevenueCatService.isPremiumActive();
    } else {
      // Use existing RevenueCat service for other platforms
      return ServiceLocator.get<RevenueCatService>().isPremiumActive();
    }
  }

  /// Platform-adaptive subscription purchase
  static Future<Result<CustomerInfo, Exception>> purchaseSubscription(Package package) async {
    if (Platform.isIOS) {
      return IOSRevenueCatService.purchaseProduct(package);
    } else {
      // Use existing RevenueCat service for other platforms
      return ServiceLocator.get<RevenueCatService>().purchaseProduct(package);
    }
  }

  /// Platform-adaptive subscription restoration
  static Future<Result<CustomerInfo, Exception>> restorePurchases() async {
    if (Platform.isIOS) {
      return IOSRevenueCatService.restorePurchases();
    } else {
      // Use existing RevenueCat service for other platforms
      return ServiceLocator.get<RevenueCatService>().restorePurchases();
    }
  }

  /// Handle platform-specific app lifecycle events
  static Future<Result<void, Exception>> handleAppLifecycleChange(AppLifecycleState state) async {
    try {
  debugPrint('Handling app lifecycle change: $state on ${Platform.operatingSystem}');
      
      if (Platform.isIOS) {
        switch (state) {
          case AppLifecycleState.resumed:
            // iOS-specific resume handling
            await IOSAuthService.handleAppLifecycle();
            await IOSFileService.cleanupTemporaryFiles();
            break;
          case AppLifecycleState.paused:
            // iOS-specific pause handling
            debugPrint('iOS app paused - saving state if needed');
            break;
          case AppLifecycleState.detached:
            // iOS-specific cleanup
            await IOSRevenueCatService.cleanup();
            break;
          default:
            break;
        }
      }
      
      return const Success(null);
    } catch (e) {
      debugPrint('Failed to handle app lifecycle change: $e');
      return Failure(Exception('App lifecycle handling failed: $e'));
    }
  }

  /// Get platform-specific configuration info
  static Map<String, dynamic> getPlatformInfo() {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'is_ios': Platform.isIOS,
      'is_android': Platform.isAndroid,
      'is_web': false, // Platform.isWeb doesn't exist in dart:io
      'supports_platform_services': Platform.isIOS || Platform.isAndroid,
      'sprint_version': '2.5',
    };
  }

  /// Clean up platform-specific resources
  static Future<Result<void, Exception>> cleanup() async {
    try {
      debugPrint('Cleaning up platform services...');
      
      if (Platform.isIOS) {
        await IOSRevenueCatService.cleanup();
        await IOSFileService.cleanupTemporaryFiles();
      }
      
      debugPrint('Platform services cleanup completed');
      return const Success(null);
    } catch (e) {
      debugPrint('Failed to cleanup platform services: $e');
      return Failure(Exception('Platform cleanup failed: $e'));
    }
  }
}

// Placeholder classes for services that don't exist yet
// These would be replaced with actual service implementations
class AuthService {
  Future<Result<User, Exception>> signInWithGoogle() async {
    throw UnimplementedError('AuthService not implemented');
  }
  
  Future<Result<void, Exception>> signOut() async {
    throw UnimplementedError('AuthService not implemented');
  }
}

class FileService {
  Future<Result<String?, Exception>> pickRecipeFile() async {
    throw UnimplementedError('FileService not implemented');
  }
  
  Future<Result<void, Exception>> shareRecipeFile(String filePath, String fileName) async {
    throw UnimplementedError('FileService not implemented');
  }
}

class RevenueCatService {
  Future<Result<bool, Exception>> isPremiumActive() async {
    throw UnimplementedError('RevenueCatService not implemented');
  }
  
  Future<Result<CustomerInfo, Exception>> purchaseProduct(Package package) async {
    throw UnimplementedError('RevenueCatService not implemented');
  }
  
  Future<Result<CustomerInfo, Exception>> restorePurchases() async {
    throw UnimplementedError('RevenueCatService not implemented');
  }
}
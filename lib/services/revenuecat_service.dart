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
//     --dart-define=RC_API_KEY_IOS=appl_xxx
//
// iOS Setup (App Store Connect + RevenueCat):
// 1. Create in-app purchase products in App Store Connect
// 2. Set up RevenueCat project and get iOS API key
// 3. Configure products in RevenueCat dashboard to match App Store Connect
// 4. Pass iOS API key via --dart-define=RC_API_KEY_IOS=your_key
// 5. iOS will use StoreKit (Apple's native payment system)
//
// Android Setup (Google Play + RevenueCat):
// 1. Create in-app products in Google Play Console
// 2. Link Google Play to RevenueCat
// 3. Pass Android API key via --dart-define=RC_API_KEY_ANDROID=your_key
//
// CI: pass the same defines in your build step (e.g., GitHub Actions).

import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:package_info_plus/package_info_plus.dart';

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

  static String get _iosKey {
    final key = _kIosKeyFromEnv.isNotEmpty ? _kIosKeyFromEnv : _kIosKeyFallback;
    if (kDebugMode && defaultTargetPlatform == TargetPlatform.iOS) {
      if (key.isEmpty) {
        debugPrint(
            '[RC] No iOS API key found. RevenueCat will not be configured.');
        debugPrint(
            '[RC] iOS should use App Store Connect for in-app purchases.');
        debugPrint(
            '[RC] Expected products: pro_offline_ios, premium_monthly, premium_yearly');
        debugPrint(
            '[RC] To configure: pass --dart-define=RC_API_KEY_IOS=your_ios_key');
      } else {
        debugPrint('[RC] iOS API key found: ${key.substring(0, 8)}...');
        if (!key.startsWith('appl_')) {
          debugPrint(
              '[RC] WARNING: iOS key does not start with "appl_". Double-check you are using the iOS Public SDK Key (not Android/REST).');
        }
        debugPrint('[RC] RevenueCat will be configured for iOS with StoreKit');
      }
    }
    return key;
  }

  static String get _androidKey {
    final key = _kAndroidKeyFromEnv.isNotEmpty
        ? _kAndroidKeyFromEnv
        : _kAndroidKeyFallback;
    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      if (key.isEmpty) {
        debugPrint(
            '[RC] No Android API key found. RevenueCat will not be configured.');
        debugPrint(
            '[RC] To configure: pass --dart-define=RC_API_KEY_ANDROID=your_android_key');
      } else {
        debugPrint('[RC] Android API key found: ${key.substring(0, 8)}...');
        if (!key.startsWith('goog_')) {
          debugPrint(
              '[RC] WARNING: Android key does not start with "goog_". Double-check you are using the Android Public SDK Key (not iOS/REST).');
        }
      }
    }
    return key;
  }

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

  /// Exposed so other services can check if RevenueCat is actually configured.
  bool get isConfigured => _rcConfigured;

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
  // Debug helpers
  // ───────────────────────────────────────────────────────────────────────────
  /// Log the first few characters of any baked-in dart-defines for RC.
  /// Helpful to verify that --dart-define=RC_API_KEY_* was compiled into this build.
  void debugLogBuildTimeDefines() {
    if (!kDebugMode) return;
    String prefix(String s) {
      if (s.isEmpty) return '(empty)';
      return s.length <= 8 ? s : s.substring(0, 8);
    }

    final iosPref = prefix(_kIosKeyFromEnv);
    final andPref = prefix(_kAndroidKeyFromEnv);
    debugPrint(
        '[RC] defines baked-in → RC_API_KEY_IOS=$iosPref… RC_API_KEY_ANDROID=$andPref…');
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
        if (kDebugMode) {
          debugPrint('[RC] No API key provided, skipping configuration');
        }
        _rcConfigured = false;
        return;
      }

      try {
        // Enable verbose logs in debug to diagnose configuration issues
        try {
          await Purchases.setLogLevel(LogLevel.debug);
        } catch (_) {/* ignore if older SDK */}

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
        if (kDebugMode) debugPrint('[RC] Successfully configured with API key');
      } catch (e) {
        if (kDebugMode) debugPrint('[RC] Configuration failed: $e');
        try {
          if (e is PlatformException) {
            final mapped = PurchasesErrorHelper.getErrorCode(e);
            debugPrint(
                '[RC] Configure PlatformException mapped: ${mapped.name}');
            debugPrint('[RC] Configure PlatformException code: ${e.code}');
            if (e.details != null) {
              debugPrint(
                  '[RC] Configure PlatformException details: ${e.details}');
            }
          }
        } catch (_) {}
        _rcConfigured = false;
      }
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

  // ───────────────────────────────────────────────────────────────────────────
  // Debug diagnostics (prints to console)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> debugPrintDiagnostics() async {
    if (!kDebugMode) return;
    try {
      final info = await PackageInfo.fromPlatform();
      debugPrint('┌──────────────────── RC Diagnostics ────────────────────');
      debugPrint('│ app: ${info.appName} ${info.version}+${info.buildNumber}');
      debugPrint(
          '│ package: ${info.packageName} platform: ${defaultTargetPlatform.name}');
      debugPrint(
          '│ rcSupported=$_platformSupportsRC rcAvailable=$_rcAvailable rcConfigured=$_rcConfigured');
      // Print key prefix (masked)
      final key = _platformKey ?? '';
      final keyPref =
          key.isEmpty ? '(empty)' : key.substring(0, key.length.clamp(0, 8));
      debugPrint('│ apiKeyPrefix=$keyPref…');

      // Ensure configured and fetch details
      await _ensureRCConfigured();
      if (!_rcConfigured) {
        debugPrint(
            '│ Purchases not configured (missing key or failed configure)');
        debugPrint('└────────────────────────────────────────────────────────');
        return;
      }

      try {
        final appUserId = await Purchases.appUserID;
        debugPrint('│ appUserID=$appUserId');
      } catch (_) {}

      try {
        final offs = await Purchases.getOfferings();
        final curr = offs.current;
        if (curr == null) {
          debugPrint('│ currentOffering=null (set a Current offering in RC)');
        } else {
          debugPrint(
              '│ currentOffering=${curr.identifier} packages=${curr.availablePackages.length}');
          for (final p in curr.availablePackages) {
            final pid = p.storeProduct.identifier;
            debugPrint('│  - package=${p.identifier} productId=$pid');
          }
        }
      } catch (e) {
        debugPrint('│ getOfferings threw: $e');
        if (e is PlatformException) {
          try {
            final mapped = PurchasesErrorHelper.getErrorCode(e);
            debugPrint(
                '│ mapped=${mapped.name} code=${e.code} details=${e.details}');
          } catch (_) {}
        }
      }

      debugPrint('└────────────────────────────────────────────────────────');
    } catch (e) {
      debugPrint('[RC] Diagnostics failed: $e');
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

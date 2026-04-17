// lib/services/feature_gate.dart (refactored)
// Single source of truth for plan state.
// - Persists locally so Pro‑Offline works offline immediately
// - Mirrors RevenueCat on Android/iOS when available
// - Mirrors backend flags (Firestore/Stripe/RC webhooks)
// - Debounced writes + no‑op updates to minimize Hive churn

import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform,
        debugPrint;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'revenuecat_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/boxes.dart';
import '../utils/cache_keys.dart';

/// Subscription / license plan
enum Plan { free, proOffline, premium }

class FeatureGate extends ChangeNotifier {
  FeatureGate._();
  static final FeatureGate instance = FeatureGate._();

  // ────────────────────────────────────────────────────────────────────────────
  // Config / constants
  // ────────────────────────────────────────────────────────────────────────────
  static const String mirrorKey = CacheKeys.featureGate; // reserved namespace
  static const String _kPlanKey = 'plan'; // Hive key in Boxes.featureGate

  // Entitlement ids as constants to avoid typos
  static const String rcEntitlementPremium = 'premium';
  static const String rcEntitlementProOffline = 'pro_offline';

  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ────────────────────────────────────────────────────────────────────────────
  // Canonical plan state (single source of truth)
  // ────────────────────────────────────────────────────────────────────────────
  Plan _plan = Plan.free;
  Plan get plan => _plan;

  bool get isPremium => _plan == Plan.premium;
  bool get isProOffline => _plan == Plan.proOffline;
  bool get isFree => !isPremium && !isProOffline;

  // ────────────────────────────────────────────────────────────────────────────
  // Persistence (Hive)
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _loadPlan() async {
    try {
      if (!Hive.isBoxOpen(Boxes.featureGate)) {
        debugPrint('[FeatureGate] Box not open, using default plan');
        return;
      }

      final box = Hive.box(Boxes.featureGate);
      final raw = box.get(_kPlanKey) as String?;
      _plan = switch (raw) {
        'premium' => Plan.premium,
        'proOffline' => Plan.proOffline,
        _ => Plan.free,
      };
    } catch (e) {
      debugPrint('[FeatureGate] Failed to load plan: $e');
      _plan = Plan.free;
    }
  }

  Future<void> _savePlan() async {
    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (!Hive.isBoxOpen(Boxes.featureGate)) {
          if (attempt == 1) {
            debugPrint(
                '[FeatureGate] Box not open, cannot save plan (attempt $attempt/$maxRetries)');
          }
          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 100 * attempt));
            continue;
          } else {
            debugPrint(
                '[FeatureGate] Box still not open after $maxRetries attempts, giving up');
            return;
          }
        }

        final box = Hive.box(Boxes.featureGate);
        final value = switch (_plan) {
          Plan.premium => 'premium',
          Plan.proOffline => 'proOffline',
          Plan.free => 'free',
        };
        await box.put(_kPlanKey, value);
        return; // Success
      } catch (e) {
        debugPrint(
            '[FeatureGate] Failed to save plan (attempt $attempt/$maxRetries): $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ────────────────────────────────────────────────────────────────────────────
  /// Call once during app init, *after* Hive boxes are opened and **after**
  /// RevenueCatService.init() for mobile.
  Future<void> bootstrap() async {
    await _loadPlan();
    notifyListeners(); // show locally stored plan immediately

    if (!_rcSupported) return; // desktop/web mirror handled elsewhere

    // Try to seed from RC if available, otherwise keep local plan until updates arrive
    try {
      // Check if RevenueCat is properly configured before calling it
      if (RevenueCatService.instance.isConfigured) {
        final appUserID = await Purchases.appUserID;
        if (appUserID.isNotEmpty) {
          final info = await Purchases.getCustomerInfo();
          _applyRC(info);
        }
      }
    } catch (_) {
      // keep local - RevenueCat might not be configured yet
      debugPrint('[FeatureGate] RevenueCat not available, using local plan');
    }

    // Only add listeners if RevenueCat is available
    try {
      // Avoid adding duplicate listeners on hot restarts
      Purchases.removeCustomerInfoUpdateListener(_onRCUpdate);
      Purchases.addCustomerInfoUpdateListener(_onRCUpdate);
    } catch (_) {
      // RevenueCat not configured, skip listener setup
      debugPrint('[FeatureGate] RevenueCat listeners not available');
    }
  }

  void _onRCUpdate(CustomerInfo info) => _applyRC(info);

  /// Use after explicit RC restore/purchase flows (mobile only).
  void refreshFromCustomerInfo(CustomerInfo info) {
    if (_rcSupported) _applyRC(info);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Backend mirror (Firestore / Stripe webhooks)
  // ────────────────────────────────────────────────────────────────────────────
  /// Mirrors backend flags into the local plan.
  /// Priority: Premium > Pro‑Offline > Free.
  void applyBackendMirror({
    required bool premiumActive,
    required bool proOfflineOwned,
  }) {
    if (premiumActive) {
      _setPlanPersist(Plan.premium);
    } else if (proOfflineOwned) {
      _setPlanPersist(Plan.proOffline);
    } else {
      _setPlanPersist(Plan.free);
    }
  }

  /// Back-compat for older call sites that only knew about Premium.
  void setFromBackend(bool active) {
    applyBackendMirror(premiumActive: active, proOfflineOwned: isProOffline);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Public actions
  // ────────────────────────────────────────────────────────────────────────────
  /// Activate local, one‑time Pro‑Offline on this device.
  Future<void> activateProOffline() async => _setPlanPersist(Plan.proOffline);

  /// Optional: for QA / debug flows to clear Pro‑Offline back to free.
  Future<void> deactivateProOffline() async => _setPlanPersist(Plan.free);

  // ────────────────────────────────────────────────────────────────────────────
  // Internal setters
  // ────────────────────────────────────────────────────────────────────────────
  void _applyRC(CustomerInfo info) {
    final hasPremium =
        info.entitlements.active.containsKey(rcEntitlementPremium);
    final hasPro =
        info.entitlements.active.containsKey(rcEntitlementProOffline);

    final next = hasPremium
        ? Plan.premium
        : (hasPro ? Plan.proOffline : _plan /* keep current/local */);

    _setPlanPersist(next);
  }

  Future<void> _setPlanPersist(Plan next) async {
    if (_plan == next) return; // no-op
    _plan = next;
    notifyListeners();
    try {
      await _savePlan();
    } catch (e) {
      debugPrint('[FeatureGate] failed to persist plan: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Gating & Limits
  // ────────────────────────────────────────────────────────────────────────────
  // Free limits
  final int recipeLimitFree = 5;
  final int activeBatchLimitFree = 3;
  final int archivedBatchLimitFree = 5;
  final int inventoryLimitFree = 12;

  // Treat Pro‑Offline like Premium for OFFLINE objects
  bool get _hasOfflineUnlimited => isPremium || isProOffline;
  bool get hasOfflineUnlimited => _hasOfflineUnlimited;

  // Count checks
  bool canAddRecipe(int current) =>
      _hasOfflineUnlimited || current < recipeLimitFree;
  bool canAddActiveBatch(int current) =>
      _hasOfflineUnlimited || current < activeBatchLimitFree;
  bool canAddArchivedBatch(int current) =>
      _hasOfflineUnlimited || current < archivedBatchLimitFree;
  bool canAddInventoryItem(int current) =>
      _hasOfflineUnlimited || current < inventoryLimitFree;

  // Cloud/online features (Premium only)
  bool get allowSync => isPremium; // Firebase/cloud sync
  bool get allowDevices => isPremium; // device linking UI (cloud)
  bool get allowDeviceStreaming => isPremium; // live Firestore ingest
  bool get allowDeviceExport => isPremium; // cloud/raw export if applicable

  // Offline premium features (Premium OR Pro‑Offline)
  bool get allowShoppingList => isPremium || isProOffline;
  bool get allowDataExport => isPremium || isProOffline; // local export/backup
  bool get allowGravityAdjust => isPremium || isProOffline;
  bool get allowSO2 => isPremium || isProOffline;
  bool get allowAcidTA => isPremium || isProOffline;
  bool get allowStripReader => isPremium || isProOffline;

  // Always-free tools
  bool get allowABV => true;
  bool get allowSGCorrection => true;
  bool get allowFSU => true;
  bool get allowBubbleCounter => true;
  bool get allowAcidPH => true;
  bool get allowUnitConverter => true;
}

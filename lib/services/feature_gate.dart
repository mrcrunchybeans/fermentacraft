// lib/services/feature_gate.dart
import 'package:flutter/foundation.dart'
    show ChangeNotifier, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/boxes.dart';
import '../utils/cache_keys.dart';

/// Subscription / license plan
enum Plan { free, proOffline, premium }

class FeatureGate extends ChangeNotifier {
  FeatureGate._();
  static final instance = FeatureGate._();

  // ====== Canonical plan state (single source of truth) ======
  Plan _plan = Plan.free;
  Plan get plan => _plan;

  bool get isPremium => _plan == Plan.premium;
  bool get isProOffline => _plan == Plan.proOffline;

  static const String mirrorKey = CacheKeys.featureGate; // reserved namespace

  // RevenueCat is only used on Android/iOS.
  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ---------- Persistence (local) ----------
  static const _kPlanKey = 'plan'; // stored in Boxes.featureGate


  Future<void> _loadPlan() async {
    final box = Hive.box(Boxes.featureGate);
    final raw = box.get(_kPlanKey) as String?;
    _plan = switch (raw) {
      'premium' => Plan.premium,
      'proOffline' => Plan.proOffline,
      _ => Plan.free,
    };
  }
  

  Future<void> _savePlan() async {
    final box = Hive.box(Boxes.featureGate);
    final v = switch (_plan) {
      Plan.premium => 'premium',
      Plan.proOffline => 'proOffline',
      Plan.free => 'free',
    };
    await box.put(_kPlanKey, v);
  }

  // ---------- Bootstrap ----------
  /// Call once during app init, after Hive boxes are opened.
  /// - Loads local plan (so Pro-Offline works instantly offline).
  /// - On Android/iOS, mirrors RC entitlements (Premium > Pro-Offline > Free).
  Future<void> bootstrap() async {
    await _loadPlan();
    notifyListeners();

    if (!_rcSupported) return;

    try {
      final info = await Purchases.getCustomerInfo();
      _applyRC(info);
    } catch (_) {
      // Keep locally loaded plan until RC responds.
    }

    Purchases.addCustomerInfoUpdateListener((info) => _applyRC(info));
  }

  /// Use after explicit RC restore/purchase flows (mobile only).
  void refreshFromCustomerInfo(CustomerInfo info) {
    if (_rcSupported) _applyRC(info);
  }

  // ---------- Backend mirror (Firestore / Stripe webhooks) ----------
  /// Mirrors your backend premium & proOffline bits to local plan.
  /// Example usage after reading Firestore doc `users/{uid}/premium/status`:
  ///   gate.applyBackendMirror(
  ///     premiumActive: data['active'] == true,
  ///     proOfflineOwned: data['proOffline'] == true,
  ///   );
  ///
  /// Priority: Premium > Pro-Offline > Free.
/// Mirror backend flags (e.g., from Firestore via Stripe/RC webhooks)
// Mirrors your backend/Firestore status into the local plan.
// - Premium wins over Pro-Offline.
// - If premiumActive is false but proOfflineOwned is true, enable Pro-Offline locally.
void applyBackendMirror({
  required bool premiumActive,
  required bool proOfflineOwned,
}) {
  if (premiumActive) {
    setFromBackend(true); // -> Premium
  } else {
    setFromBackend(false); // clear Premium
    if (proOfflineOwned) {
      activateProOffline(); // keep Pro-Offline locally
    }
  }
}


  /// Backward-compat (kept for existing call sites that only knew about Premium).
  void setFromBackend(bool active) {
    applyBackendMirror(premiumActive: active, proOfflineOwned: isProOffline);
  }

  // ---------- Public actions ----------
  /// Activate local, one-time Pro-Offline on this device.
  Future<void> activateProOffline() async {
    _setPlan(Plan.proOffline);
    await _savePlan();
  }

  /// Optional: for QA / debug flows to clear Pro-Offline back to free.
  Future<void> deactivateProOffline() async {
    _setPlan(Plan.free);
    await _savePlan();
  }

  void clearLocalMirror() {
    // reserved for future local flags
  }

  // ---------- Internal setters ----------
  void _applyRC(CustomerInfo info) {
    final hasPremium = info.entitlements.active.containsKey('premium');
    final hasProOffline = info.entitlements.active.containsKey('pro_offline');

    final next = hasPremium
        ? Plan.premium
        : (hasProOffline ? Plan.proOffline : _plan /* keep local/free */);

    _setPlan(next);
    _savePlan();
  }

  void _setPlan(Plan next) {
    if (_plan != next) {
      _plan = next;
      notifyListeners();
    }
  }

  // ===================== Gating & Limits =====================

  // ---- Free limits ----
  final int recipeLimitFree = 5;
  final int activeBatchLimitFree = 3;
  final int archivedBatchLimitFree = 5;
  final int inventoryLimitFree = 12;

  // Treat Pro-Offline like Premium for OFFLINE objects
  bool get _hasOfflineUnlimited => isPremium || isProOffline;

  // ---- Count checks ----
  bool canAddRecipe(int current) => _hasOfflineUnlimited || current < recipeLimitFree;
  bool canAddActiveBatch(int current) =>
      _hasOfflineUnlimited || current < activeBatchLimitFree;
  bool canAddArchivedBatch(int current) =>
      _hasOfflineUnlimited || current < archivedBatchLimitFree;
  bool canAddInventoryItem(int current) =>
      _hasOfflineUnlimited || current < inventoryLimitFree;

  // ---- Cloud/online features (Premium only) ----
  bool get allowSync => isPremium;               // Firebase/cloud sync
  bool get allowDevices => isPremium;            // device linking UI (cloud)
  bool get allowDeviceStreaming => isPremium;    // live Firestore ingest
  bool get allowDeviceExport => isPremium;       // cloud/raw export if applicable

  // ---- Offline premium features (Premium OR Pro-Offline) ----
  bool get allowShoppingList => isPremium || isProOffline;
  bool get allowDataExport => isPremium || isProOffline;   // local export/backup
  bool get allowGravityAdjust => isPremium || isProOffline;
  bool get allowSO2 => isPremium || isProOffline;
  bool get allowAcidTA => isPremium || isProOffline;
  bool get allowStripReader => isPremium || isProOffline;

  // ---- Always-free tools ----
  bool get allowABV => true;
  bool get allowSGCorrection => true;
  bool get allowFSU => true;
  bool get allowBubbleCounter => true;
  bool get allowAcidPH => true;
  bool get allowUnitConverter => true;
}

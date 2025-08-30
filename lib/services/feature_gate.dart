// lib/services/feature_gate.dart
import 'package:flutter/foundation.dart'
    show ChangeNotifier, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:purchases_flutter/purchases_flutter.dart';

// namespaced cache keys (fc_)
import '../utils/cache_keys.dart';

class FeatureGate extends ChangeNotifier {
  FeatureGate._();
  static final instance = FeatureGate._();

  // ---- Premium state (single source of truth for the UI) ----
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  // Optional: tiny local mirror key for instant boot on web (fc_feature_gate).
  static const String mirrorKey = CacheKeys.featureGate;

  // RevenueCat is only available/used on mobile platforms.
  bool get _rcSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Call once during app init.
  /// - On Android/iOS, mirrors RevenueCat entitlements.
  /// - On desktop/web, no-op (you should call `setFromBackend(...)`
  ///   from your Firestore listener when the Stripe/CF mirror flips premium).
  Future<void> bootstrap() async {
    // If you later add a local mirror, you can hydrate here for instant boot:
    // _hydrateFromLocalMirror();

    if (!_rcSupported) return;

    try {
      final info = await Purchases.getCustomerInfo();
      _applyRC(info);
    } catch (_) {
      // Start as free until RC responds.
    }

    Purchases.addCustomerInfoUpdateListener((info) => _applyRC(info));
  }

  /// Use after explicit RC restore/purchase flows (mobile only).
  void refreshFromCustomerInfo(CustomerInfo info) {
    if (_rcSupported) _applyRC(info);
  }

  /// Desktop/Web (or any trusted backend signal):
  /// call this when your Firestore mirror says premium is active/inactive.
  void setFromBackend(bool active) {
    _setPremium(active);
  }

  // ---- Internal setters ----
  void _applyRC(CustomerInfo info) {
    final hasPremium = info.entitlements.active.containsKey('premium');
    _setPremium(hasPremium);
  }

  void _setPremium(bool next) {
    if (_isPremium != next) {
      _isPremium = next;
      // If you add a local mirror later, persist under fc_ key here:
      // _persistLocalMirror();
      notifyListeners();
    }
  }

  /// Soft-reset hook. Call from your reset flow.
  void clearLocalMirror() {
    // If you later persist a tiny mirror flag to storage, remove it here:
    // LocalKV.remove(_mirrorKey);
  }

  // ===== Optional helpers if you later want to mirror tiny state locally =====
  // void _hydrateFromLocalMirror() {
  //   final s = LocalKV.getString(_mirrorKey);
  //   if (s == '1') _isPremium = true;
  // }
  // void _persistLocalMirror() {
  //   LocalKV.setString(_mirrorKey, _isPremium ? '1' : '0');
  // }

  // ---- Free limits ----
  final int recipeLimitFree = 3;
  final int activeBatchLimitFree = 1;
  final int archivedBatchLimitFree = 3;
  final int inventoryLimitFree = 10;

  // ---- Count checks ----
  bool canAddRecipe(int current) => isPremium || current < recipeLimitFree;
  bool canAddActiveBatch(int current) => isPremium || current < activeBatchLimitFree;
  bool canAddArchivedBatch(int current) => isPremium || current < archivedBatchLimitFree;
  bool canAddInventoryItem(int current) => isPremium || current < inventoryLimitFree;

  // ---- Premium-only features ----
  bool get allowSync => isPremium;
  bool get allowShoppingList => isPremium;
  bool get allowDataExport => isPremium;
  bool get allowGravityAdjust => isPremium;
  bool get allowSO2 => isPremium;
  bool get allowAcidTA => isPremium;
  bool get allowStripReader => isPremium;
  bool get allowDevices => isPremium;               // show device UI, attach/link
  bool get allowDeviceStreaming => isPremium;       // read live Firestore measurements
  bool get allowDeviceExport => isPremium;          // export raw CSV

  // ---- Always-free tools ----
  bool get allowABV => true;
  bool get allowSGCorrection => true;
  bool get allowFSU => true;
  bool get allowBubbleCounter => true;
  bool get allowAcidPH => true;
  bool get allowUnitConverter => true;
}

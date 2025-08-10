// lib/services/feature_gate.dart
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class FeatureGate extends ChangeNotifier {
  FeatureGate._();
  static final instance = FeatureGate._();

  // ---- Premium state (mirrors RevenueCat only) ----
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  /// Call once after `Purchases.configure(...)` (e.g., in app init).
  Future<void> bootstrap() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _apply(info);
    } catch (_) {
      // swallow; user just starts as free until RC responds
    }
    Purchases.addCustomerInfoUpdateListener((info) => _apply(info));
  }

  /// Use after explicit restore or purchase flows.
  void refreshFromCustomerInfo(CustomerInfo info) => _apply(info);

  void _apply(CustomerInfo info) {
    final hasPremium = info.entitlements.active.containsKey('premium');
    if (_isPremium != hasPremium) {
      _isPremium = hasPremium;
      notifyListeners();
    }
  }

    void setFromBackend(bool active) {
    if (_isPremium != active) {
      _isPremium = active;
      notifyListeners();
    }
  }

  // ---- Free limits ----
  final int recipeLimitFree = 3;
  final int activeBatchLimitFree = 1;
  final int archivedBatchLimitFree = 3;
  final int inventoryLimitFree = 10;

  // ---- Count checks ----
  bool canAddRecipe(int current)        => isPremium || current < recipeLimitFree;
  bool canAddActiveBatch(int current)   => isPremium || current < activeBatchLimitFree;
  bool canAddArchivedBatch(int current) => isPremium || current < archivedBatchLimitFree;
  bool canAddInventoryItem(int current) => isPremium || current < inventoryLimitFree;

  // ---- Premium-only features ----
  bool get allowSync          => isPremium;
  bool get allowShoppingList  => isPremium;
  bool get allowDataExport    => isPremium;
  bool get allowGravityAdjust => isPremium;
  bool get allowSO2           => isPremium;
  bool get allowAcidTA        => isPremium;
  bool get allowStripReader   => isPremium;

  // ---- Free tools ----
  bool get allowABV           => true;
  bool get allowSGCorrection  => true;
  bool get allowFSU           => true;
  bool get allowBubbleCounter => true;
  bool get allowAcidPH        => true;
  bool get allowUnitConverter => true;
}

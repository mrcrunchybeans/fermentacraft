// lib/services/feature_gate.dart

/// Central switchboard for Free vs Pro behavior.
/// - Flip [isPro] during development to simulate entitlements
///   (we’ll wire this to RevenueCat later).
class FeatureGate {
  FeatureGate._();
  static final instance = FeatureGate._();

  /// TEMP: simulated entitlement (replace via RevenueCat later).
  /// Set this in main() or a debug toggle in Settings.
  bool isPro = false;

  // ---- Free limits ----
  final int recipeLimitFree = 3;
  final int activeBatchLimitFree = 1;
  final int archivedBatchLimitFree = 3;
  final int inventoryLimitFree = 10;

  // ---- Count checks ----
  bool canAddRecipe(int current)        => isPro || current < recipeLimitFree;
  bool canAddActiveBatch(int current)   => isPro || current < activeBatchLimitFree;
  bool canAddArchivedBatch(int current) => isPro || current < archivedBatchLimitFree;
  bool canAddInventoryItem(int current) => isPro || current < inventoryLimitFree;

  // ---- Pro-only features (soft-locked when false) ----
  bool get allowSync          => isPro;
  bool get allowShoppingList  => isPro;
  bool get allowDataExport    => isPro;
  bool get allowGravityAdjust => isPro;
  bool get allowSO2           => isPro;
  bool get allowAcidTA        => isPro;
  bool get allowStripReader   => isPro;

  // ---- Free tools (always available) ----
  bool get allowABV           => true;
  bool get allowSGCorrection  => true;
  bool get allowFSU           => true;
  bool get allowBubbleCounter => true;
  bool get allowAcidPH        => true;
  bool get allowUnitConverter => true;
}

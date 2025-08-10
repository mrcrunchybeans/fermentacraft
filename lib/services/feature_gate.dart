// lib/services/feature_gate.dart
class FeatureGate {
  FeatureGate._();
  static final instance = FeatureGate._();

  bool isPremium = false;

  void setPremium(bool value) {
    if (isPremium == value) return;
    isPremium = value;
    // Later: if you wrap this with ChangeNotifier, call notifyListeners().
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

// lib/utils/inventory_item_extensions.dart
import 'package:hive/hive.dart';

import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Sidecar store for soft-archive flags (avoids schema changes on InventoryItem)
/// ─────────────────────────────────────────────────────────────────────────────
class InventoryArchiveStore {
  static const boxName = 'inventory_archive_flags';

  static Future<Box<bool>> ensureOpen() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<bool>(boxName);
    }
    return Hive.box<bool>(boxName);
  }

  static Box<bool> get box => Hive.box<bool>(boxName);
}

/// Soft-archive flag stored in a sidecar Hive box.
/// Call InventoryArchiveStore.ensureOpen() once at app boot.
extension InventoryItemArchiveX on InventoryItem {
  bool get isArchived {
    if (!Hive.isBoxOpen(InventoryArchiveStore.boxName)) return false;
    return InventoryArchiveStore.box.get(key, defaultValue: false) ?? false;
  }

  set isArchived(bool v) {
    if (!Hive.isBoxOpen(InventoryArchiveStore.boxName)) {
      throw StateError(
        'Archive flags box not open. Call InventoryArchiveStore.ensureOpen() first.',
      );
    }
    InventoryArchiveStore.box.put(key, v);
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Display helpers (units, formatting, pricing)
/// ─────────────────────────────────────────────────────────────────────────────
extension InventoryItemDisplayX on InventoryItem {
  /// Pluralizes common "package-style" units; leaves invariant units alone.
  String getDisplayUnit(double amount) {
    final singular = unit.toLowerCase();

    // Units that pluralize with 's'
    const simplePlurals = {
      'package': 'packages',
      'bottle': 'bottles',
      'can': 'cans',
      'tablet': 'tablets',
      'cap': 'caps',
      'packet': 'packets',
      'carboy': 'carboys',
    };

    // Units that do not change with amount
    const invariantUnits = {
      'g', 'gram', 'grams',
      'kg', 'oz', 'lb', 'mg',
      'ml', 'l',
      'tsp', 'tbsp', 'fl oz', 'cup', 'gal',
    };

    if (amount == 1) return unit;
    if (simplePlurals.containsKey(singular)) return simplePlurals[singular]!;
    if (invariantUnits.contains(singular)) return unit;

    return unit.endsWith('s') ? unit : '${unit}s';
  }

  /// Convenience: unit label for the current stock level.
  String get displayUnit => getDisplayUnit(amountInStock);

  /// Weighted **average cost per unit** based on priced purchases only.
  ///
  /// - Ignores transactions with total cost <= 0 (free/unknown price).
  /// - Uses only positive amounts when averaging (purchases, not deductions).
  /// - Falls back to the most recent priced unit cost if present.
  /// - Returns 0 when no priced data exists.
  double get averageCostPerUnit {
    double pricedAmount = 0;
    double pricedCostTotal = 0;

    for (final tx in purchaseHistory) {
      final double amt = tx.amount;
      // Prefer a model-provided `totalCost` getter if available; otherwise use `cost`.
      final double tCost = _txTotalCost(tx);
      if (amt > 0 && tCost > 0) {
        pricedAmount += amt;
        pricedCostTotal += tCost;
      }
    }

    if (pricedAmount > 0) {
      return pricedCostTotal / pricedAmount;
    }

    // Fallback: last priced transaction's unit cost, if any.
    for (final tx in purchaseHistory.reversed) {
      final double amt = tx.amount;
      final double tCost = _txTotalCost(tx);
      if (amt > 0 && tCost > 0) {
        return tCost / amt;
      }
    }

    return 0;
  }

  /// Nicely formatted price-per-unit (returns '—' when unknown).
  String get averageCostPerUnitLabel {
    final cpu = averageCostPerUnit;
    return cpu > 0 ? '\$${cpu.toStringAsFixed(2)}/$unit' : '—';
  }

  /// Pretty "amount + unit" for display (e.g., "2.5 kg" or "3 bottles").
  String formatAmount(double amount, {int fractionDigits = 2}) {
    final isInt = amount == amount.roundToDouble();
    final numStr =
        isInt ? amount.toStringAsFixed(0) : amount.toStringAsFixed(fractionDigits);
    return '$numStr ${getDisplayUnit(amount)}';
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Mutating helpers for stock changes (keeps semantics obvious)
/// NOTE:
///   - We assume InventoryItem.amountInStock is derived from purchaseHistory.
///   - These helpers DO NOT call save(); the caller should save() the item.
///   - Price can be omitted; zero-cost entries are allowed and ignored in
///     pricing averages.
/// ─────────────────────────────────────────────────────────────────────────────
extension InventoryItemOpsX on InventoryItem {
  /// Record a purchase or stock increase.
  ///
  /// [amount] must be > 0. [totalCost] is the total dollars spent for this
  /// increase (not per-unit); pass 0 to indicate unknown/free.
  void addPurchase({
    required double amount,
    double totalCost = 0,
    DateTime? date,
    DateTime? expirationDate,
  }) {
    if (amount <= 0) return;
    purchaseHistory.add(
      PurchaseTransaction(
        date: date ?? DateTime.now(),
        amount: amount,
        cost: totalCost, // interpreted as TOTAL cost for this transaction
        expirationDate: expirationDate,
      ),
    );
  }

  /// Deduct stock (e.g., used in a batch). Adds a zero-cost negative entry.
  void use(double amount, {DateTime? date}) {
    if (amount <= 0) return;
    purchaseHistory.add(
      PurchaseTransaction(
        date: date ?? DateTime.now(),
        amount: -amount,
        cost: 0,
      ),
    );
  }

  /// Restore stock (undo a deduction). Adds a zero-cost positive entry.
  void restore(double amount, {DateTime? date}) {
    if (amount <= 0) return;
    purchaseHistory.add(
      PurchaseTransaction(
        date: date ?? DateTime.now(),
        amount: amount,
        cost: 0,
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Private helpers
/// ─────────────────────────────────────────────────────────────────────────────

/// Some codebases have `PurchaseTransaction.totalCost` as a computed getter,
/// others store total in `cost`. This normalizes to a total-dollar value.
double _txTotalCost(PurchaseTransaction tx) {
  try {
    // If the model exposes a `totalCost` getter, prefer it.
    // ignore: unnecessary_cast
    final dynamic d = tx as dynamic;
    final val = d.totalCost;
    if (val is num) return val.toDouble();
  } catch (_) {
    // fall through
  }
  // Otherwise, interpret `cost` as TOTAL cost for the transaction.
  return tx.cost.toDouble();
}

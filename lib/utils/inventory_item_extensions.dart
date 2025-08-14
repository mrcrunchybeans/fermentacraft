// lib/utils/inventory_item_extensions.dart
import 'package:hive_flutter/hive_flutter.dart';

import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import 'package:fermentacraft/utils/money.dart'; // for moneyWithSymbol()

/// ─────────────────────────────────────────────────────────────────────────────
/// Sidecar store for soft-archive flags (avoids schema changes on InventoryItem)
/// Call InventoryArchiveStore.ensureOpen() once at app boot.
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

    const simplePlurals = {
      'package': 'packages',
      'bottle': 'bottles',
      'can': 'cans',
      'tablet': 'tablets',
      'cap': 'caps',
      'packet': 'packets',
      'carboy': 'carboys',
    };

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
  double get averageCostPerUnit {
    double pricedAmount = 0;
    double pricedCostTotal = 0;

    for (final tx in purchaseHistory) {
      final double amt = tx.amount;
      final double tCost = _txTotalCost(tx);
      if (amt > 0 && tCost > 0) {
        pricedAmount += amt;
        pricedCostTotal += tCost;
      }
    }

    if (pricedAmount > 0) return pricedCostTotal / pricedAmount;

    // Fallback: last priced transaction's unit cost, if any.
    for (final tx in purchaseHistory.reversed) {
      final double amt = tx.amount;
      final double tCost = _txTotalCost(tx);
      if (amt > 0 && tCost > 0) return tCost / amt;
    }
    return 0;
  }

  /// Symbol-aware label for avg cost per unit (UI passes the chosen symbol).
  String averageCostPerUnitLabelWith(String symbol, {int decimals = 2}) {
    final cpu = averageCostPerUnit;
    return cpu > 0 ? '${moneyWithSymbol(symbol, cpu, decimals: decimals)}/$unit' : '—';
  }

  /// (Deprecated) Replace usages with averageCostPerUnitLabelWith(symbol).
  @Deprecated('Use averageCostPerUnitLabelWith(symbol) so the UI can pick the currency.')
  String get averageCostPerUnitLabel {
    final cpu = averageCostPerUnit;
    return cpu > 0 ? '\$${cpu.toStringAsFixed(2)}/$unit' : '—';
  }

  /// Pretty "amount + unit" for display (e.g., "2.5 kg" or "3 bottles").
  String formatAmount(double amount, {int fractionDigits = 2}) {
    final isInt = amount == amount.roundToDouble();
    final numStr = isInt ? amount.toStringAsFixed(0) : amount.toStringAsFixed(fractionDigits);
    return '$numStr ${getDisplayUnit(amount)}';
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Mutating helpers for stock changes (caller should save() afterwards)
/// ─────────────────────────────────────────────────────────────────────────────
extension InventoryItemOpsX on InventoryItem {
  /// Add a purchase by passing the full transaction object.
  void addPurchaseTx(PurchaseTransaction tx) {
    purchaseHistory.add(tx);
  }

  /// Add a purchase using named parameters (amount & totalCost).
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
        cost: totalCost, // total cost for this transaction
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

/// Normalize to TOTAL transaction cost (supports models that expose `totalCost`).
double _txTotalCost(PurchaseTransaction tx) {
  try {
    final dynamic d = tx as dynamic;
    final val = d.totalCost;
    if (val is num) return val.toDouble();
  } catch (_) {
    // ignore
  }
  return tx.cost.toDouble();
}

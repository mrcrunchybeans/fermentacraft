import 'package:hive/hive.dart';
import '../models/inventory_item.dart';

/// Sidecar store to track archived flags without changing the InventoryItem schema.
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

/// Adds a soft-archive flag to InventoryItem, stored in a sidecar Hive box.
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

/// Your existing display/cost helpers.
extension InventoryItemDisplay on InventoryItem {
  String getDisplayUnit(double amount) {
    final singular = unit.toLowerCase();

    // Units that get pluralized by adding 's'
    const simplePlurals = {
      'package': 'packages',
      'bottle': 'bottles',
      'can': 'cans',
      'tablet': 'tablets',
      'cap': 'caps',
      'packet': 'packets',
      'carboy': 'carboys',
    };

    // Units that stay the same regardless of amount
    const invariantUnits = {
      'g', 'gram', 'grams',
      'kg', 'oz', 'lb', 'mg',
      'ml', 'l', // normalize if you want
      'tsp', 'tbsp', 'fl oz', 'cup', 'gal',
    };

    if (amount == 1) return unit;
    if (simplePlurals.containsKey(singular)) return simplePlurals[singular]!;
    if (invariantUnits.contains(singular)) return unit;

    return unit.endsWith('s') ? unit : '${unit}s';
  }

  String get displayUnit => getDisplayUnit(amountInStock);

  double get averageCostPerUnit {
    double totalAmount = 0;
    double totalCost = 0;

    for (final entry in purchaseHistory) {
      totalAmount += entry.amount;
      totalCost += entry.totalCost;
    }

    return totalAmount > 0 ? totalCost / totalAmount : costPerUnit;
  }
}

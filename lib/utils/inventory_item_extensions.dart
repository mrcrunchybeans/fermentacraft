import '../models/inventory_item.dart';

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
      'ml', 'mL', 'L',
      'tsp', 'tbsp', 'fl oz', 'cup', 'gallon',
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

return totalAmount > 0 ? totalCost / totalAmount : (costPerUnit ?? 0.0);
  }
}

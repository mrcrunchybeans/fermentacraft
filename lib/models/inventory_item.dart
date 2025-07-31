import 'package:hive/hive.dart';
import 'purchase_transaction.dart';
import 'unit_type.dart';

part 'inventory_item.g.dart';

@HiveType(typeId: 20)
class InventoryItem extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  double amountInStock;

  @HiveField(2)
  String unit;

  @HiveField(3)
  UnitType unitType;

  @HiveField(4)
  double? costPerUnit; // Nullable to allow null safety

  @HiveField(5)
  String? notes;

  @HiveField(6)
  List<PurchaseTransaction> purchaseHistory;

  @HiveField(7)
  String category;

  @HiveField(8)
  DateTime? expirationDate;

  InventoryItem({
    required this.name,
    required this.amountInStock,
    required this.unit,
    required this.unitType,
    this.costPerUnit,
    required this.category,
    this.notes,
    this.expirationDate,
    List<PurchaseTransaction>? purchaseHistory,
  }) : purchaseHistory = purchaseHistory ?? [];

  /// Returns 0.0 if costPerUnit is null
  double get safeCostPerUnit => costPerUnit ?? 0.0;

  /// Optional: Pre-formatted for display
  String get safeCostPerUnitFormatted =>
      '\$${safeCostPerUnit.toStringAsFixed(2)}';
}

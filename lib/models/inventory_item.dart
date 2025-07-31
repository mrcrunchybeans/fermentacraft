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
  double costPerUnit;

  @HiveField(5)
  String? notes;

  @HiveField(6)
  List<PurchaseTransaction> purchaseHistory;

  @HiveField(7)
  String category;

  InventoryItem({
    required this.name,
    required this.amountInStock,
    required this.unit,
    required this.unitType,
    required this.costPerUnit,
    required this.category,
    this.notes,
    List<PurchaseTransaction>? purchaseHistory,
  }) : purchaseHistory = purchaseHistory ?? [];
}

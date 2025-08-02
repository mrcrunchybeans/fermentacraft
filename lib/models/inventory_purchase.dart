import 'package:hive/hive.dart';

part 'inventory_purchase.g.dart';

@HiveType(typeId: 26)
class InventoryPurchase {
  @HiveField(0)
  double amount;

  @HiveField(1)
  DateTime? purchaseDate;

  @HiveField(2)
  DateTime? expiration;

  @HiveField(3)
  double? costPerUnit;

  InventoryPurchase({
    required this.amount,
    this.purchaseDate,
    this.expiration,
    this.costPerUnit,
  });
}

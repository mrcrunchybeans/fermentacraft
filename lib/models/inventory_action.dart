// models/inventory_action.dart

import 'package:hive/hive.dart';

part 'inventory_action.g.dart';

@HiveType(typeId: 29)
class InventoryAction extends HiveObject {
  @HiveField(0)
  String itemName;

  @HiveField(1)
  double amount;

  @HiveField(2)
  String unit;

  @HiveField(3)
  bool wasDeducted; // true = deducted, false = restored

  @HiveField(4)
  DateTime timestamp;

  @HiveField(5)
  String? reason; // Optional: e.g., "Used in Batch ABC", "Manually Added"

  InventoryAction({
    required this.itemName,
    required this.amount,
    required this.unit,
    required this.wasDeducted,
    required this.timestamp,
    this.reason,
  });
}

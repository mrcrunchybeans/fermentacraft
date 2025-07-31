import 'package:hive/hive.dart';

part 'inventory_transaction_model.g.dart';

@HiveType(typeId: 21)
class InventoryTransaction {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  double amount;

  @HiveField(2)
  double cost;

  InventoryTransaction({
    required this.date,
    required this.amount,
    required this.cost,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'amount': amount,
      'cost': cost,
    };
  }
}

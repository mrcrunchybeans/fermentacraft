import 'package:hive_flutter/hive_flutter.dart';

part 'inventory_transaction_model.g.dart';

@HiveType(typeId: 21)
class InventoryTransaction extends HiveObject { // Added extends HiveObject
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

  // Add this factory for consistency
  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      date: DateTime.parse(json['date']),
      amount: (json['amount'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
    );
  }
}
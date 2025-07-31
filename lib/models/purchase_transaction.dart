import 'package:hive/hive.dart';

part 'purchase_transaction.g.dart';

@HiveType(typeId: 2)
class PurchaseTransaction extends HiveObject {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  double amount;

  @HiveField(2)
  double cost;

  @HiveField(3)
  DateTime? expirationDate;

  PurchaseTransaction({
    required this.date,
    required this.amount,
    required this.cost,
    this.expirationDate,
  });

  double get totalCost => cost;

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'amount': amount,
      'cost': cost,
      'expirationDate': expirationDate?.toIso8601String(),
    };
  }
}

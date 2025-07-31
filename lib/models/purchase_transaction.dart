import 'package:hive/hive.dart';

part 'purchase_transaction.g.dart';

@HiveType(typeId: 2)
class PurchaseTransaction {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  double amount;

  @HiveField(2)
  double cost;

  PurchaseTransaction({
    required this.date,
    required this.amount,
    required this.cost,
  });

  Null get totalCost => null;
}

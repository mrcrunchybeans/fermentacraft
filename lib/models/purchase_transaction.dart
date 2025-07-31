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

  @HiveField(3) // New field for expiration date
  DateTime? expirationDate;

  PurchaseTransaction({
    required this.date,
    required this.amount,
    required this.cost,
    this.expirationDate, // Added to constructor
  });

  double get totalCost => cost;
}
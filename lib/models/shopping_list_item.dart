// lib/models/shopping_list_item.dart

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'shopping_list_item.g.dart';

@HiveType(typeId: 5)
class ShoppingListItem extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double amount;

  @HiveField(3)
  String unit;

  @HiveField(4)
  String recipeName;

  @HiveField(5)
  bool isChecked;

  ShoppingListItem({
    required this.name,
    required this.amount,
    required this.unit,
    required this.recipeName,
    this.isChecked = false,
  }) {
    id = const Uuid().v4();
  }

  // FIX: Added fromJson factory constructor for data import.
  factory ShoppingListItem.fromJson(Map<String, dynamic> json) {
    return ShoppingListItem(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
      recipeName: json['recipeName'] as String,
      isChecked: json['isChecked'] as bool,
    )..id = json['id'] as String;
  }

  // FIX: Added toJson method for data export.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'unit': unit,
      'recipeName': recipeName,
      'isChecked': isChecked,
    };
  }
}

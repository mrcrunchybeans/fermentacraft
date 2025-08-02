// lib/models/shopping_list_item.dart

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// Run this command to generate the adapter:
// flutter pub run build_runner build --delete-conflicting-outputs

part 'shopping_list_item.g.dart';

@HiveType(typeId: 32) // Ensure this typeId is unique in your project
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
}
// lib/models/shopping_list_item.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

part 'shopping_list_item.g.dart';

@HiveType(typeId: 51)
class ShoppingListItem extends HiveObject {
  /// 🔑 Stable string id used as both the Hive key and Firestore doc id.
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double amount;

  @HiveField(3)
  String unit;

  @HiveField(4)
  String recipeName;

  @HiveField(5, defaultValue: false)
  bool isChecked;

  /// Primary constructor — requires an id. Use [ShoppingListItem.newItem] to create with a fresh UUID.
  ShoppingListItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.unit,
    required this.recipeName,
    this.isChecked = false,
  });

  /// Convenience factory for creating a brand-new item with a generated id.
  factory ShoppingListItem.newItem({
    required String name,
    required double amount,
    required String unit,
    required String recipeName,
    bool isChecked = false,
  }) {
    return ShoppingListItem(
      id: const Uuid().v4(),
      name: name,
      amount: amount,
      unit: unit,
      recipeName: recipeName,
      isChecked: isChecked,
    );
  }

  // ---------- JSON (Firestore / export) ----------

  factory ShoppingListItem.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    return ShoppingListItem(
      // If the incoming JSON somehow lacks an id, generate one so we never create a duplicate with a new int key.
      id: id.isNotEmpty ? id : const Uuid().v4(),
      name: (json['name'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      unit: (json['unit'] ?? '').toString(),
      recipeName: (json['recipeName'] ?? '').toString(),
      isChecked: (json['isChecked'] as bool?) ?? false,
    );
  }

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

import 'package:hive/hive.dart';
import 'purchase_transaction.dart';
import 'unit_type.dart';

part 'inventory_item.g.dart';

@HiveType(typeId: 20)
class InventoryItem extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  double amountInStock;

  @HiveField(2)
  String unit;

  @HiveField(3)
  UnitType unitType;

  @HiveField(4)
  double? costPerUnit;

  @HiveField(5)
  String? notes;

  @HiveField(6)
  List<PurchaseTransaction> purchaseHistory;

  @HiveField(7)
  String category;

  @HiveField(8)
  DateTime? expirationDate;

  InventoryItem({
    required this.name,
    required this.amountInStock,
    required this.unit,
    required this.unitType,
    this.costPerUnit,
    required this.category,
    this.notes,
    this.expirationDate,
    List<PurchaseTransaction>? purchaseHistory,
  }) : purchaseHistory = purchaseHistory ?? [];

  double get safeCostPerUnit => costPerUnit ?? 0.0;

  String get safeCostPerUnitFormatted =>
      '\$${safeCostPerUnit.toStringAsFixed(2)}';

  // --- CORRECTED toJson and fromJson Methods ---

  Map<String, dynamic> toJson() => {
        'name': name,
        'amountInStock': amountInStock,
        'unit': unit,
        'unitType': unitType.name, // Converts the enum to a string
        'costPerUnit': costPerUnit,
        'notes': notes,
        'category': category,
        'expirationDate': expirationDate?.toIso8601String(),
        // Convert each PurchaseTransaction to a simple map for JSON
        'purchaseHistory': purchaseHistory.map((p) => {
          'date': p.date.toIso8601String(),
          'amount': p.amount,
          'cost': p.cost,
          'expirationDate': p.expirationDate?.toIso8601String(),
        }).toList(),
      };

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        name: json['name'],
        amountInStock: (json['amountInStock'] as num).toDouble(),
        unit: json['unit'],
        unitType: UnitType.values.firstWhere((e) => e.name == json['unitType']),
        costPerUnit: (json['costPerUnit'] as num?)?.toDouble(),
        notes: json['notes'],
        category: json['category'],
        expirationDate: json['expirationDate'] != null ? DateTime.parse(json['expirationDate']) : null,
        // Reconstruct each PurchaseTransaction from its map representation
        purchaseHistory: (json['purchaseHistory'] as List).map((pJson) => PurchaseTransaction(
          date: DateTime.parse(pJson['date']),
          amount: (pJson['amount'] as num).toDouble(),
          cost: (pJson['cost'] as num).toDouble(),
          expirationDate: pJson['expirationDate'] != null ? DateTime.parse(pJson['expirationDate']) : null,
        )).toList(),
      );
}

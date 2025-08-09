import 'package:hive/hive.dart';
import 'purchase_transaction.dart';
import 'unit_type.dart';

part 'inventory_item.g.dart';

@HiveType(typeId: 20)
class InventoryItem extends HiveObject {
  // 🔑 Stable string ID used for both Hive key and Firestore docId
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String unit;

  @HiveField(3)
  UnitType unitType;

  @HiveField(4)
  String? notes;

  @HiveField(5)
  List<PurchaseTransaction> purchaseHistory;

  @HiveField(6)
  String category;

  InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitType,
    required this.category,
    this.notes,
    List<PurchaseTransaction>? purchaseHistory,
  }) : purchaseHistory = purchaseHistory ?? [];

  // --------- Derived values ---------

  double get amountInStock =>
      purchaseHistory.fold(0.0, (sum, p) => sum + p.remainingAmount);

  DateTime? get expirationDate {
    final available = purchaseHistory
        .where((p) => p.remainingAmount > 0 && p.expirationDate != null)
        .toList();
    if (available.isEmpty) return null;
    available.sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));
    return available.first.expirationDate;
  }

  double get costPerUnit {
    if (amountInStock <= 0) return 0.0;
    final totalCostOfStock = purchaseHistory.fold(0.0, (sum, p) {
      if (p.amount <= 0) return sum;
      final originalCostPerUnit = p.cost / p.amount;
      return sum + (p.remainingAmount * originalCostPerUnit);
    });
    return totalCostOfStock / amountInStock;
  }

  // --------- Mutations ---------

  void addPurchase(PurchaseTransaction purchase) {
    purchaseHistory.add(purchase);
    save();
  }

  void use(double amountToDeduct) {
    final available =
        purchaseHistory.where((p) => p.remainingAmount > 0).toList();
    available.sort((a, b) {
      if (a.expirationDate == null) return 1;
      if (b.expirationDate == null) return -1;
      return a.expirationDate!.compareTo(b.expirationDate!);
    });

    double remainingToDeduct = amountToDeduct;
    for (var purchase in available) {
      if (remainingToDeduct <= 0) break;
      final canUse = remainingToDeduct < purchase.remainingAmount
          ? remainingToDeduct
          : purchase.remainingAmount;
      purchase.usedAmount += canUse;
      remainingToDeduct -= canUse;
    }
    save();
  }

  void restore(double amountToRestore) {
    final used = purchaseHistory.where((p) => p.usedAmount > 0).toList();
    used.sort((a, b) {
      if (a.expirationDate == null) return -1;
      if (b.expirationDate == null) return 1;
      return b.expirationDate!.compareTo(a.expirationDate!);
    });

    double remainingToRestore = amountToRestore;
    for (var purchase in used) {
      if (remainingToRestore <= 0) break;
      final canRestore = remainingToRestore < purchase.usedAmount
          ? remainingToRestore
          : purchase.usedAmount;
      purchase.usedAmount -= canRestore;
      remainingToRestore -= canRestore;
    }
    save();
  }

  // --------- JSON (for Firestore sync) ---------

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'unitType': unitType.name, // enum -> string
      'notes': notes,
      'purchaseHistory': purchaseHistory.map((p) => p.toJson()).toList(),
      'category': category,
    };
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      unitType: UnitType.values.firstWhere(
        (e) => e.name == (json['unitType'] ?? '').toString(),
        orElse: () => UnitType.values.first,
      ),
      category: (json['category'] ?? '').toString(),
      notes: json['notes']?.toString(),
      purchaseHistory: (json['purchaseHistory'] as List? ?? [])
          .map((p) => PurchaseTransaction.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
    );
  }

  // Optional convenience
  InventoryItem copyWith({
    String? id,
    String? name,
    String? unit,
    UnitType? unitType,
    String? notes,
    List<PurchaseTransaction>? purchaseHistory,
    String? category,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitType: unitType ?? this.unitType,
      notes: notes ?? this.notes,
      purchaseHistory: purchaseHistory ?? List<PurchaseTransaction>.from(this.purchaseHistory),
      category: category ?? this.category,
    );
  }
}

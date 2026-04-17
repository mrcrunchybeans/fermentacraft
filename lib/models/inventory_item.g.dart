// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryItemAdapter extends TypeAdapter<InventoryItem> {
  @override
  final int typeId = 20;

  @override
  InventoryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryItem(
      id: fields[0] as String,
      name: fields[1] as String,
      unit: fields[2] as String,
      unitType: fields[3] as UnitType,
      category: fields[6] as String,
      sg: fields[7] as double?,
      brix: fields[8] as double?,
      notes: fields[4] as String?,
      purchaseHistory: (fields[5] as List?)?.cast<PurchaseTransaction>(),
    );
  }

  @override
  void write(BinaryWriter writer, InventoryItem obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.unit)
      ..writeByte(3)
      ..write(obj.unitType)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.purchaseHistory)
      ..writeByte(6)
      ..write(obj.category)
      ..writeByte(7)
      ..write(obj.sg)
      ..writeByte(8)
      ..write(obj.brix);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

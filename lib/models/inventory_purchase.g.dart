// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_purchase.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryPurchaseAdapter extends TypeAdapter<InventoryPurchase> {
  @override
  final int typeId = 26;

  @override
  InventoryPurchase read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryPurchase(
      amount: fields[0] as double,
      purchaseDate: fields[1] as DateTime?,
      expiration: fields[2] as DateTime?,
      costPerUnit: fields[3] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryPurchase obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.amount)
      ..writeByte(1)
      ..write(obj.purchaseDate)
      ..writeByte(2)
      ..write(obj.expiration)
      ..writeByte(3)
      ..write(obj.costPerUnit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryPurchaseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

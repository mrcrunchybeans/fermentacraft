// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_transaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryTransactionAdapter extends TypeAdapter<InventoryTransaction> {
  @override
  final int typeId = 21;

  @override
  InventoryTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return InventoryTransaction(
      date: fields[0] as DateTime,
      amount: fields[1] as double,
      cost: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryTransaction obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.cost);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

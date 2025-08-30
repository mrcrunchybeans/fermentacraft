// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_action.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryActionAdapter extends TypeAdapter<InventoryAction> {
  @override
  final int typeId = 29;

  @override
  InventoryAction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryAction(
      itemName: fields[0] as String,
      amount: fields[1] as double,
      unit: fields[2] as String,
      wasDeducted: fields[3] == null ? false : fields[3] as bool,
      timestamp: fields[4] as DateTime,
      reason: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryAction obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.itemName)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.unit)
      ..writeByte(3)
      ..write(obj.wasDeducted)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.reason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryActionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

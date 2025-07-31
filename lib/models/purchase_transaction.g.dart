// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PurchaseTransactionAdapter extends TypeAdapter<PurchaseTransaction> {
  @override
  final int typeId = 2;

  @override
  PurchaseTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return PurchaseTransaction(
      date: fields[0] as DateTime,
      amount: fields[1] as double,
      cost: fields[2] as double,
      expirationDate: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PurchaseTransaction obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.amount)
      ..writeByte(2)
      ..write(obj.cost)
      ..writeByte(3)
      ..write(obj.expirationDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

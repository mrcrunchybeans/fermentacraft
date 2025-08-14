// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_yeast.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserYeastAdapter extends TypeAdapter<UserYeast> {
  @override
  final int typeId = 91;

  @override
  UserYeast read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserYeast(
      name: fields[0] as String,
      notes: fields[1] as String?,
      minTempC: fields[2] as double?,
      maxTempC: fields[3] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, UserYeast obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.notes)
      ..writeByte(2)
      ..write(obj.minTempC)
      ..writeByte(3)
      ..write(obj.maxTempC);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserYeastAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unit_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UnitTypeAdapter extends TypeAdapter<UnitType> {
  @override
  final int typeId = 24;

  @override
  UnitType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return UnitType.volume;
      case 1:
        return UnitType.mass;
      case 2:
        return UnitType.temperature;
      case 3:
        return UnitType.gravity;
      default:
        return UnitType.volume;
    }
  }

  @override
  void write(BinaryWriter writer, UnitType obj) {
    switch (obj) {
      case UnitType.volume:
        writer.writeByte(0);
        break;
      case UnitType.mass:
        writer.writeByte(1);
        break;
      case UnitType.temperature:
        writer.writeByte(2);
        break;
      case UnitType.gravity:
        writer.writeByte(3);
        break;
    }
  }
}

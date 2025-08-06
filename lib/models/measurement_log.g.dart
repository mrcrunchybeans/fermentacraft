// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'measurement_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeasurementLogAdapter extends TypeAdapter<MeasurementLog> {
  @override
  final int typeId = 12;

  @override
  MeasurementLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MeasurementLog(
      timestamp: fields[0] as DateTime,
      sg: fields[1] as double,
      tempC: fields[2] as double?,
      pH: fields[3] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, MeasurementLog obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.sg)
      ..writeByte(2)
      ..write(obj.tempC)
      ..writeByte(3)
      ..write(obj.pH);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

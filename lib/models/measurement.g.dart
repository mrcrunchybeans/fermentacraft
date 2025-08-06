// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'measurement.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeasurementAdapter extends TypeAdapter<Measurement> {
  @override
  final int typeId = 6;

  @override
  Measurement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Measurement(
      timestamp: fields[0] as DateTime,
      gravity: fields[1] as double?,
      temperature: fields[2] as double?,
      notes: fields[3] as String?,
      gravityUnit: fields[4] as String?,
      interventions: (fields[5] as List?)?.cast<String>(),
      ta: fields[6] as double?,
      brix: fields[7] as double?,
      sgCorrected: fields[8] as double?,
      fsuspeed: fields[9] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Measurement obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.gravity)
      ..writeByte(2)
      ..write(obj.temperature)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.gravityUnit)
      ..writeByte(5)
      ..write(obj.interventions)
      ..writeByte(6)
      ..write(obj.ta)
      ..writeByte(7)
      ..write(obj.brix)
      ..writeByte(8)
      ..write(obj.sgCorrected)
      ..writeByte(9)
      ..write(obj.fsuspeed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

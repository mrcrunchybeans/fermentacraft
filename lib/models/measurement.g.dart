// lib/models/measurement.g.dart
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
      id: fields[0] as String?,
      timestamp: fields[1] as DateTime,
      gravity: fields[2] as double?,
      temperature: fields[3] as double?,
      notes: fields[4] as String?,
      gravityUnit: fields[5] as String?,
      interventions: (fields[6] as List?)?.cast<String>(),
      ta: fields[7] as double?,
      brix: fields[8] as double?,
      sgCorrected: fields[9] as double?,
      fsuspeed: fields[10] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Measurement obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.gravity)
      ..writeByte(3)
      ..write(obj.temperature)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.gravityUnit)
      ..writeByte(6)
      ..write(obj.interventions)
      ..writeByte(7)
      ..write(obj.ta)
      ..writeByte(8)
      ..write(obj.brix)
      ..writeByte(9)
      ..write(obj.sgCorrected)
      ..writeByte(10)
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

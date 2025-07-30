// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'measurement.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeasurementAdapter extends TypeAdapter<Measurement> {
  @override
  final int typeId = 16;

  @override
  Measurement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Measurement(
      timestamp: fields[0] as DateTime,
      gravityUnit: fields[4] as String,
      temperature: fields[1] as double?,
      sg: fields[2] as double?,
      brix: fields[3] as double?,
      note: fields[5] as String?,
      fsuspeed: fields[6] as double?,
      ta: fields[7] as double?,
      interventions: (fields[8] as List).cast<String>(),
      sgCorrected: fields[9] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Measurement obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.temperature)
      ..writeByte(2)
      ..write(obj.sg)
      ..writeByte(3)
      ..write(obj.brix)
      ..writeByte(4)
      ..write(obj.gravityUnit)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.fsuspeed)
      ..writeByte(7)
      ..write(obj.ta)
      ..writeByte(8)
      ..write(obj.interventions)
      ..writeByte(9)
      ..write(obj.sgCorrected);
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

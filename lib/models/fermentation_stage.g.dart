// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fermentation_stage.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FermentationStageAdapter extends TypeAdapter<FermentationStage> {
  @override
  final int typeId = 11;

  @override
  FermentationStage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FermentationStage(
      name: fields[0] as String,
      startDate: fields[1] as DateTime,
      durationDays: fields[2] as int,
      targetTempC: fields[3] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, FermentationStage obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.startDate)
      ..writeByte(2)
      ..write(obj.durationDays)
      ..writeByte(3)
      ..write(obj.targetTempC);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FermentationStageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

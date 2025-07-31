// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fermentation_stage.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FermentationStageAdapter extends TypeAdapter<FermentationStage> {
  @override
  final int typeId = 1;

  @override
  FermentationStage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return FermentationStage(
      name: fields[0] as String,
      durationDays: fields[1] as int,
      targetTempC: fields[2] as double?,
      startDate: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, FermentationStage obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.durationDays)
      ..writeByte(2)
      ..write(obj.targetTempC)
      ..writeByte(3)
      ..write(obj.startDate);
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

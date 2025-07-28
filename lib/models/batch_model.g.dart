// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BatchModelAdapter extends TypeAdapter<BatchModel> {
  @override
  final int typeId = 10;

  @override
  BatchModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BatchModel(
      id: fields[0] as String,
      name: fields[1] as String,
      recipeId: fields[2] as String,
      startDate: fields[3] as DateTime,
      bottleDate: fields[4] as DateTime?,
      batchVolume: fields[5] as double?,
      stages: (fields[6] as List).cast<FermentationStage>(),
      measurementLogs: (fields[7] as List).cast<MeasurementLog>(),
      status: fields[8] as String,
      notes: fields[9] as String?,
      deductedIngredients: (fields[10] as Map).cast<String, bool>(),
    );
  }

  @override
  void write(BinaryWriter writer, BatchModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.recipeId)
      ..writeByte(3)
      ..write(obj.startDate)
      ..writeByte(4)
      ..write(obj.bottleDate)
      ..writeByte(5)
      ..write(obj.batchVolume)
      ..writeByte(6)
      ..write(obj.stages)
      ..writeByte(7)
      ..write(obj.measurementLogs)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.notes)
      ..writeByte(10)
      ..write(obj.deductedIngredients);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

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
    final fields = Map<int, dynamic>.fromIterables(
      List.generate(numOfFields, (_) => reader.readByte()),
      List.generate(numOfFields, (_) => reader.read()),
    );
    return BatchModel(
      id: fields[0] as String,
      name: fields[1] as String,
      recipeId: fields[2] as String,
      startDate: fields[3] as DateTime,
      bottleDate: fields[4] as DateTime?,
      batchVolume: fields[5] as double?,
      fermentationStages: (fields[6] as List).cast<FermentationStage>(),
      measurementLogs: (fields[7] as List).cast<MeasurementLog>(),
      status: fields[8] as String,
      notes: fields[9] as String?,
      deductedIngredients: (fields[10] as Map).cast<String, bool>(),
      type: fields[11] as String?,
      plannedOg: fields[12] as double?,
      plannedAbv: fields[13] as double?,
      ingredients: (fields[14] as List).cast<Map<String, dynamic>>(),
      plannedEvents: (fields[15] as List?)?.cast<PlannedEvent>(),
      additives: (fields[16] as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  void write(BinaryWriter writer, BatchModel obj) {
    writer
      ..writeByte(17)
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
      ..write(obj.fermentationStages)
      ..writeByte(7)
      ..write(obj.measurementLogs)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.notes)
      ..writeByte(10)
      ..write(obj.deductedIngredients)
      ..writeByte(11)
      ..write(obj.type)
      ..writeByte(12)
      ..write(obj.plannedOg)
      ..writeByte(13)
      ..write(obj.plannedAbv)
      ..writeByte(14)
      ..write(obj.ingredients)
      ..writeByte(15)
      ..write(obj.plannedEvents)
      ..writeByte(16)
      ..write(obj.additives);
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

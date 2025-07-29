// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_model.dart';

class BatchModelAdapter extends TypeAdapter<BatchModel> {
  @override
  final int typeId = 34;

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
      fermentationStages: (fields[6] as List).cast<FermentationStage>(),
      measurementLogs: (fields[7] as List).cast<MeasurementLog>(),
      status: fields[8] as String? ?? 'Planning',
      notes: fields[9] as String?,
      deductedIngredients: (fields[10] as Map).cast<String, bool>(),
      type: fields[11] as String?,
      plannedOg: fields[12] as double?,
      plannedAbv: fields[13] as double?,
      ingredients: (fields[14] as List).cast<Map<String, dynamic>>(),
      plannedEvents: (fields[15] as List?)?.cast<PlannedEvent>(),
      additives: (fields[16] as List).cast<Map<String, dynamic>>(),
      yeast: fields[17] as Map<String, dynamic>?,
      createdAt: fields[18] as DateTime,
      tags: (fields[19] as List).cast<Tag>(),
      og: fields[20] as double?,
      fg: fields[21] as double?,
      abv: fields[22] as double?,
      measurements: (fields[23] as List).cast<Measurement>(),
    )..fsuDate = fields[24] as DateTime?;
  }

  @override
  void write(BinaryWriter writer, BatchModel obj) {
    writer
      ..writeByte(25)
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
      ..write(obj.additives)
      ..writeByte(17)
      ..write(obj.yeast)
      ..writeByte(18)
      ..write(obj.createdAt)
      ..writeByte(19)
      ..write(obj.tags)
      ..writeByte(20)
      ..write(obj.og)
      ..writeByte(21)
      ..write(obj.fg)
      ..writeByte(22)
      ..write(obj.abv)
      ..writeByte(23)
      ..write(obj.measurements)
      ..writeByte(24)
      ..write(obj.fsuDate);
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

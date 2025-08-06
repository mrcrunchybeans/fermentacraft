// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecipeModelAdapter extends TypeAdapter<RecipeModel> {
  @override
  final int typeId = 4;

  @override
  RecipeModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return RecipeModel(
      id: fields[0] as String,
      name: fields[1] as String,
      tags: (fields[3] as List).cast<Tag>(),
      createdAt: fields[2] as DateTime,
      og: fields[4] as double?,
      fg: fields[5] as double?,
      abv: fields[6] as double?,
      additives: (fields[7] as List).cast<Map<dynamic, dynamic>>(),
      ingredients: (fields[8] as List).cast<Map<dynamic, dynamic>>(),
      fermentationStages: (fields[9] as List).cast<FermentationStage>(),
      yeast: (fields[10] as List).cast<Map<dynamic, dynamic>>(),
      notes: fields[11] as String,
      lastOpened: fields[12] as DateTime?,
      batchVolume: fields[13] as double?,
      plannedOg: fields[14] as double?,
      plannedAbv: fields[15] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, RecipeModel obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.tags)
      ..writeByte(4)
      ..write(obj.og)
      ..writeByte(5)
      ..write(obj.fg)
      ..writeByte(6)
      ..write(obj.abv)
      ..writeByte(7)
      ..write(obj.additives)
      ..writeByte(8)
      ..write(obj.ingredients)
      ..writeByte(9)
      ..write(obj.fermentationStages)
      ..writeByte(10)
      ..write(obj.yeast)
      ..writeByte(11)
      ..write(obj.notes)
      ..writeByte(12)
      ..write(obj.lastOpened)
      ..writeByte(13)
      ..write(obj.batchVolume)
      ..writeByte(14)
      ..write(obj.plannedOg)
      ..writeByte(15)
      ..write(obj.plannedAbv);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

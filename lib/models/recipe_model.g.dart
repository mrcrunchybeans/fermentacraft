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
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecipeModel(
      id: fields[0] as String?,
      name: fields[1] as String,
      tags: (fields[3] as List).cast<Tag>(),
      createdAt: fields[2] as DateTime,
      og: fields[4] as double?,
      fg: fields[5] as double?,
      abv: fields[6] as double?,
      additives: (fields[7] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      fermentables: (fields[8] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      fermentationStages: (fields[9] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      yeast: (fields[10] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      notes: fields[11] as String,
      lastOpened: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, RecipeModel obj) {
    writer
      ..writeByte(13)
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
      ..write(obj.fermentables)
      ..writeByte(9)
      ..write(obj.fermentationStages)
      ..writeByte(10)
      ..write(obj.yeast)
      ..writeByte(11)
      ..write(obj.notes)
      ..writeByte(12)
      ..write(obj.lastOpened);
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

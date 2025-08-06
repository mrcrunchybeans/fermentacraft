// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'planned_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlannedEventAdapter extends TypeAdapter<PlannedEvent> {
  @override
  final int typeId = 5;

  @override
  PlannedEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlannedEvent(
      title: fields[0] as String,
      date: fields[1] as DateTime,
      notes: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PlannedEvent obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.notes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlannedEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

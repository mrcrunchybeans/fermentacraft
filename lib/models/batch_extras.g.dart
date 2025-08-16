// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_extras.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BatchExtrasAdapter extends TypeAdapter<BatchExtras> {
  @override
  final int typeId = 37;

  @override
  BatchExtras read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BatchExtras(
      batchId: fields[0] as String,
      measuredOg: fields[1] as double?,
      useMeasuredOg: fields[2] == null ? false : fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, BatchExtras obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.batchId)
      ..writeByte(1)
      ..write(obj.measuredOg)
      ..writeByte(2)
      ..write(obj.useMeasuredOg);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchExtrasAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

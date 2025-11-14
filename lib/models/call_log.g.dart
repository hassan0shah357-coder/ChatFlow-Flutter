// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CallLogAdapter extends TypeAdapter<CallLog> {
  @override
  final int typeId = 4;

  @override
  CallLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CallLog(
      callerId: fields[0] as String,
      receiverId: fields[1] as String,
      type: fields[2] as String,
      timestamp: fields[3] as DateTime,
      incoming: fields[4] as bool,
      accepted: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, CallLog obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.callerId)
      ..writeByte(1)
      ..write(obj.receiverId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.incoming)
      ..writeByte(5)
      ..write(obj.accepted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

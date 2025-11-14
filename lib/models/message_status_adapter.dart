import 'package:hive/hive.dart';
import 'message_status.dart';

class MessageStatusAdapter extends TypeAdapter<MessageStatus> {
  @override
  final typeId = 1;

  @override
  MessageStatus read(BinaryReader reader) {
    return MessageStatus.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, MessageStatus obj) {
    writer.writeByte(obj.index);
  }
}

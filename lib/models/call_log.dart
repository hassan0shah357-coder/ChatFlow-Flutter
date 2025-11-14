// lib/models/call_log.dart
import 'package:hive/hive.dart';

part 'call_log.g.dart';

@HiveType(typeId: 4)
class CallLog extends HiveObject {
  @HiveField(0)
  String callerId;

  @HiveField(1)
  String receiverId;

  @HiveField(2)
  String type; // voice, video

  @HiveField(3)
  DateTime timestamp;

  @HiveField(4)
  bool incoming;

  @HiveField(5)
  bool accepted;

  CallLog({
    required this.callerId,
    required this.receiverId,
    required this.type,
    required this.timestamp,
    required this.incoming,
    required this.accepted,
  });

  CallLog copyWith({
    String? callerId,
    String? receiverId,
    String? type,
    DateTime? timestamp,
    bool? incoming,
    bool? accepted,
  }) {
    return CallLog(
      callerId: callerId ?? this.callerId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      incoming: incoming ?? this.incoming,
      accepted: accepted ?? this.accepted,
    );
  }
}

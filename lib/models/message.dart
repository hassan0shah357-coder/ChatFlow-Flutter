// lib/models/message.dart
import 'package:hive/hive.dart';
import 'message_status.dart';
import 'user.dart';

part 'message.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fromUserId;

  @HiveField(2)
  final String toUserId;

  @HiveField(3)
  final String? content;

  @HiveField(4)
  final String type; // text, image, doc, voice

  @HiveField(5)
  final String? url;

  @HiveField(6)
  final DateTime timestamp;

  @HiveField(7)
  bool isRead;

  @HiveField(8)
  MessageStatus status;

  @HiveField(9)
  final DateTime? createdAt;

  // Non-persistent field to carry sender information when received via socket
  User? senderInfo;

  Message({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    this.content,
    required this.type,
    this.url,
    required this.timestamp,
    this.isRead = false,
    this.status = MessageStatus.sending,
    this.senderInfo,
  }) : createdAt = DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    // Parse sender info if available
    User? senderInfo;
    if (json['senderInfo'] != null) {
      try {
        // Convert _id to id if needed for User.fromJson compatibility
        final senderData = Map<String, dynamic>.from(json['senderInfo']);
        if (senderData['id'] != null && senderData['_id'] == null) {
          senderData['_id'] = senderData['id'];
        }
        senderInfo = User.fromJson(senderData);
      } catch (e) {
        // If parsing fails, ignore sender info
        senderInfo = null;
      }
    }

    return Message(
      id: json['_id'] ?? json['id'] ?? '',
      fromUserId: json['from'] ?? json['fromUserId'] ?? '',
      toUserId: json['to'] ?? json['toUserId'] ?? '',
      // Support both REST (content) and socket payloads (text)
      content: json['content'] ?? json['text'],
      type: json['type'] ?? 'text',
      url: json['url'],
      // Support various timestamp keys and formats
      timestamp: _parseDateTime(
        json['createdAt'] ?? json['timestamp'] ?? json['ts'],
      ),
      isRead: json['isRead'] ?? false,
      status: _parseMessageStatus(json['status']),
      senderInfo: senderInfo,
    );
  }

  static MessageStatus _parseMessageStatus(dynamic status) {
    if (status == null) return MessageStatus.sent;

    switch (status.toString().toLowerCase()) {
      case 'sending':
        return MessageStatus.sending;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      case 'sent':
      default:
        return MessageStatus.sent;
    }
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    if (value is int) {
      try {
        // Assume milliseconds since epoch
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': fromUserId,
      'to': toUserId,
      'content': content,
      'type': type,
      'url': url,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'status': status.toString().split('.').last,
    };
  }

  Message copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    String? content,
    String? type,
    String? url,
    DateTime? timestamp,
    bool? isRead,
    MessageStatus? status,
    User? senderInfo,
  }) {
    return Message(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      content: content ?? this.content,
      type: type ?? this.type,
      url: url ?? this.url,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      status: status ?? this.status,
      senderInfo: senderInfo ?? this.senderInfo,
    );
  }
}

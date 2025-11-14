import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../models/message_status_adapter.dart';
import '../models/datetime_adapter.dart';
import '../models/user.dart';
import '../models/call_log.dart';
import '../services/socket_service.dart';

class LocalStorage {
  static const String messagesBox = 'messages';
  static const String mediaBox = 'media';
  static const String recentChatsBox = 'recent_chats';
  static const String usersBox = 'users';
  static const String callLogsBox = 'call_logs';

  static Box<Message>? _messagesBox;
  static Box<String>? _mediaBox;
  static Box<User>? _usersBox;
  static Box<Map>? _recentChatsBox;
  static Box<CallLog>? _callLogsBox;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Directory('${appDir.path}/media').create(recursive: true);
    Hive.init(appDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MessageAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MessageStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(DateTimeAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(CallLogAdapter());
    }

    // Open boxes
    _messagesBox = await Hive.openBox<Message>(messagesBox);
    _mediaBox = await Hive.openBox<String>(mediaBox);
    _usersBox = await Hive.openBox<User>(usersBox);
    _recentChatsBox = await Hive.openBox<Map>(recentChatsBox);
    _callLogsBox = await Hive.openBox<CallLog>(callLogsBox);
  }

  static Future<String> saveMediaFile(
    String userId,
    String fileName,
    File file,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${appDir.path}/media/$userId');
    await mediaDir.create(recursive: true);

    final savedFile = await file.copy('${mediaDir.path}/$fileName');
    return savedFile.path;
  }

  static Future<List<Message>> getMessages(String userId) async {
    if (_messagesBox == null || SocketService.userId == null) return [];

    final currentUserId = SocketService.userId!;
    return _messagesBox!.values
        .where(
          (msg) =>
              (msg.fromUserId == userId && msg.toUserId == currentUserId) ||
              (msg.fromUserId == currentUserId && msg.toUserId == userId),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Get messages for a specific user without depending on SocketService.userId
  /// This is useful during app initialization when SocketService might not be ready
  static Future<List<Message>> getMessagesWithUserId(
    String userId,
    String currentUserId,
  ) async {
    if (_messagesBox == null) return [];

    return _messagesBox!.values
        .where(
          (msg) =>
              (msg.fromUserId == userId && msg.toUserId == currentUserId) ||
              (msg.fromUserId == currentUserId && msg.toUserId == userId),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  static Future<void> saveMessage(Message message) async {
    await _messagesBox?.put(message.id, message);
    await _updateRecentChat(message);
  }

  static Future<void> _updateRecentChat(Message message) async {
    if (_recentChatsBox == null) return;

    final chatId = message.fromUserId == SocketService.userId
        ? message.toUserId
        : message.fromUserId;

    final existingChat = _recentChatsBox!.get(chatId) ?? {};
    final unreadCount =
        (existingChat['unreadCount'] as int? ?? 0) +
        (message.fromUserId == SocketService.userId ? 0 : 1);

    await _recentChatsBox!.put(chatId, {
      'lastMessage': message.content ?? 'Media message',
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
      'type': message.type,
      'url': message.url,
    });
  }

  /// Mark messages as read for a specific user
  static Future<void> markMessagesAsRead(String userId) async {
    if (_recentChatsBox == null ||
        _messagesBox == null ||
        SocketService.userId == null) {
      return;
    }

    final currentUserId = SocketService.userId!;
    await _markMessagesAsReadWithUserId(userId, currentUserId);
  }

  /// Mark messages as read with explicit current user ID
  static Future<void> _markMessagesAsReadWithUserId(
    String userId,
    String currentUserId,
  ) async {
    if (_recentChatsBox == null || _messagesBox == null) {
      return;
    }

    // Update the unread count in recent chats
    final existingChat = _recentChatsBox!.get(userId);
    if (existingChat != null) {
      final updatedChat = Map<String, dynamic>.from(existingChat);
      updatedChat['unreadCount'] = 0;
      await _recentChatsBox!.put(userId, updatedChat);
    }

    // Update the isRead property of actual message objects
    final messages = _messagesBox!.values
        .where(
          (msg) =>
              msg.fromUserId == userId &&
              msg.toUserId == currentUserId &&
              !msg.isRead,
        )
        .toList();

    for (final message in messages) {
      message.isRead = true;
      await message.save(); // Save the updated message back to Hive
    }
  }

  static Future<Map<String, dynamic>> getRecentChats() async {
    if (_recentChatsBox == null) return {};
    return Map<String, dynamic>.from(_recentChatsBox!.toMap());
  }

  static Future<void> saveUser(User user) async {
    await _usersBox?.put(user.id, user);
  }

  static Future<User?> getUser(String userId) async {
    return _usersBox?.get(userId);
  }

  /// Get all stored users from local storage
  static Future<List<User>> getAllUsers() async {
    if (_usersBox == null) return [];
    return _usersBox!.values.toList();
  }

  /// Get user with fallback display name logic
  static Future<User> getUserWithFallback(String userId) async {
    User? user = await getUser(userId);
    if (user == null) {
      // Create a fallback user if not found in storage
      return User(id: userId, username: 'Unknown User', email: null);
    }
    return user;
  }

  /// Update recent chats data by loading from local storage
  static Future<Map<String, dynamic>> getRecentChatsWithUserData() async {
    if (_recentChatsBox == null) return {};

    final recentChats = Map<String, dynamic>.from(_recentChatsBox!.toMap());
    final enhancedChats = <String, dynamic>{};

    // Enhance each chat with user data
    for (final userId in recentChats.keys) {
      final chatData = recentChats[userId];
      final user = await getUserWithFallback(userId);

      enhancedChats[userId] = {
        ...chatData,
        'user': user.toJson(),
        'displayName': user.displayNameWithFallback,
      };
    }

    return enhancedChats;
  }

  static Future<void> clearAllData() async {
    await _messagesBox?.clear();
    await _mediaBox?.clear();
    await _usersBox?.clear();
    await _recentChatsBox?.clear();
    await _callLogsBox?.clear();

    // Delete media directory as well
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${appDir.path}/media');
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
    }
  }

  /// Call Log Management
  static Future<void> saveCallLog(CallLog callLog) async {
    await _callLogsBox?.put(
      callLog.callerId + callLog.timestamp.millisecondsSinceEpoch.toString(),
      callLog,
    );
  }

  static Future<List<CallLog>> getCallLogs() async {
    if (_callLogsBox == null) return [];

    final logs = _callLogsBox!.values.toList();
    // Sort by timestamp, most recent first
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  static Future<List<CallLog>> getMissedCalls() async {
    if (_callLogsBox == null) return [];

    return _callLogsBox!.values
        .where((log) => log.incoming && !log.accepted)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static Future<void> markCallLogAsViewed(String callLogId) async {
    // This can be used to mark missed calls as viewed
    // For now, we'll use a simple approach where we don't need to track viewed status
    // But we can extend the CallLog model later if needed
  }

  static Future<void> clearCallLogs() async {
    await _callLogsBox?.clear();
  }

  // Delete a specific chat and all its messages
  static Future<void> deleteChat(String userId) async {
    try {
      // Delete all messages for this user
      final messagesBox = _messagesBox;
      if (messagesBox != null) {
        final messagesToDelete = messagesBox.values
            .where(
              (message) =>
                  message.fromUserId == userId || message.toUserId == userId,
            )
            .toList();

        for (final message in messagesToDelete) {
          final messageKey = messagesBox.keys.firstWhere(
            (key) => messagesBox.get(key) == message,
            orElse: () => null,
          );
          if (messageKey != null) {
            await messagesBox.delete(messageKey);
          }
        }
      }

      // Delete recent chat entry
      await _recentChatsBox?.delete(userId);

      print('Successfully deleted chat with user: $userId');
    } catch (e) {
      print('Error deleting chat: $e');
      rethrow;
    }
  }

  /// Delete conversation with a specific user (including all messages between current user and that user)
  static Future<void> deleteConversation(
    String userId,
    String currentUserId,
  ) async {
    try {
      // Delete all messages between current user and the specified user
      final messagesBox = _messagesBox;
      if (messagesBox != null) {
        final messagesToDelete = messagesBox.values
            .where(
              (message) =>
                  (message.fromUserId == userId &&
                      message.toUserId == currentUserId) ||
                  (message.fromUserId == currentUserId &&
                      message.toUserId == userId),
            )
            .toList();

        for (final message in messagesToDelete) {
          final messageKey = messagesBox.keys.firstWhere(
            (key) => messagesBox.get(key) == message,
            orElse: () => null,
          );
          if (messageKey != null) {
            await messagesBox.delete(messageKey);
          }
        }
      }

      // Delete recent chat entry for this conversation
      await _recentChatsBox?.delete(userId);

      print(
        'Successfully deleted conversation with user: $userId for current user: $currentUserId',
      );
    } catch (e) {
      print('Error deleting conversation: $e');
      rethrow;
    }
  }
}

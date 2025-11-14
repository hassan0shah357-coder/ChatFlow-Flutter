import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/models/message.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/services/api_service.dart';
import 'package:node_chat/services/socket_service.dart';
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/models/message_status.dart';
import 'package:node_chat/services/notification_service.dart';
import 'package:node_chat/services/sound_service.dart';

class ChatController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();
  final ApiService _apiService = Get.find<ApiService>();
  final SoundService _soundService = SoundService();

  final RxList<User> users = <User>[].obs;
  final RxMap<String, List<Message>> conversations =
      <String, List<Message>>{}.obs;
  final RxSet<String> onlineUsers = <String>{}.obs;
  final RxMap<String, bool> typingUsers = <String, bool>{}.obs;
  final RxMap<String, Message?> lastMessages = <String, Message?>{}.obs;
  final RxBool isInitialized = false.obs;
  final RxnString currentChatUserId = RxnString();
  final RxInt chatUpdateTrigger = 0.obs; // Trigger for forcing UI updates

  bool isUserOnline(String userId) => onlineUsers.contains(userId);

  void setInitialOnlineUsers(List<String> userIds) {
    onlineUsers.assignAll(userIds);

    // Update User objects' isOnline field
    for (final user in users) {
      user.isOnline = userIds.contains(user.id);
    }
    users.refresh();
  }

  void updateUserOnlineStatus(String userId, bool isOnline) {
    if (isOnline) {
      onlineUsers.add(userId);
    } else {
      onlineUsers.remove(userId);
    }

    // Also update the User object's isOnline field
    final userIndex = users.indexWhere((u) => u.id == userId);
    if (userIndex != -1) {
      users[userIndex].isOnline = isOnline;
      users.refresh();
      debugPrint(
        '✅ [ChatController] Updated user $userId online status to $isOnline',
      );
    }
  }

  void _updateLastMessage(String userId, Message message) {
    debugPrint(
      '🔔 [ChatController] BEFORE _updateLastMessage - lastMessages has ${lastMessages.length} chats',
    );
    debugPrint(
      '🔔 [ChatController] Current lastMessage for $userId: ${lastMessages[userId]?.content ?? "null"}',
    );
    debugPrint(
      '🔔 [ChatController] Updating last message for user $userId: ${message.content?.substring(0, message.content!.length > 20 ? 20 : message.content!.length)}...',
    );
    lastMessages[userId] = message;
    typingUsers[userId] = false;
    // CRITICAL: Force GetX to detect the change by incrementing trigger
    chatUpdateTrigger.value++;
    lastMessages.refresh();
    conversations.refresh();
    debugPrint(
      '✅ [ChatController] AFTER _updateLastMessage - lastMessages has ${lastMessages.length} chats, trigger: ${chatUpdateTrigger.value}',
    );
    debugPrint(
      '✅ [ChatController] New lastMessage for $userId: ${lastMessages[userId]?.content}',
    );
  }

  Future<void> initialize() async {
    if (isInitialized.value) return;
    try {
      // Fetch data from server only - NO local storage for messages/users
      await Future.wait([fetchUsers(), fetchRecentChats()]);
      isInitialized.value = true;

      debugPrint(
        '✅ [ChatController] Initialized with ${users.length} users and ${lastMessages.length} recent chats',
      );

      // Debug: Print all recent chats
      for (final entry in lastMessages.entries) {
        debugPrint(
          '📝 Recent chat: ${entry.key} -> ${entry.value?.content ?? 'No content'}',
        );
      }
    } catch (e) {
      // Show error message if server fetch fails (no internet)
      Get.snackbar(
        'No Internet Connection',
        'Please check your internet connection and try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      isInitialized.value = false;
    }
  }

  Future<void> fetchUsers() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.users),
        headers: {
          'Authorization': 'Bearer ${_authController.token}',
          'x-api-key': ApiConfig.apiKey,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final fetchedUsers = data.map((u) => User.fromJson(u)).toList();
        users.assignAll(fetchedUsers);

        // Sync online status from fetched users
        final onlineUserIds = fetchedUsers
            .where((u) => u.isOnline)
            .map((u) => u.id)
            .toList();

        if (onlineUserIds.isNotEmpty) {
          onlineUsers.assignAll(onlineUserIds);
          debugPrint(
            '✅ [ChatController] Synced ${onlineUserIds.length} online users from API',
          );
        }

        // Also request fresh online users list from socket
        SocketService.requestOnlineUsers();
      } else {
        debugPrint(
          '❌ [ChatController] Failed to fetch users: ${response.statusCode}',
        );
      }
    } catch (e) {}
  }

  Future<void> fetchRecentChats() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.recentChats),
        headers: {
          'Authorization': 'Bearer ${_authController.token}',
          'x-api-key': ApiConfig.apiKey,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        debugPrint(
          '🌐 [ChatController] Server returned ${data.length} recent chats',
        );

        conversations.clear();
        lastMessages.clear();

        for (final chat in data) {
          final partnerId = chat['partnerId'] as String;
          final lastMessageData = chat['lastMessage'];
          debugPrint(
            '🔍 Processing chat for partner: $partnerId, hasMessage: ${lastMessageData != null}',
          );

          if (lastMessageData != null) {
            final lastMessage = Message.fromJson(lastMessageData);
            lastMessages[partnerId] = lastMessage;
            conversations[partnerId] = [];
          }
        }

        debugPrint(
          '✅ [ChatController] Fetched ${data.length} recent chats. Final count: ${lastMessages.length}',
        );
      } else {
        debugPrint(
          '❌ [ChatController] Failed to fetch recent chats: ${response.statusCode}',
        );
      }
    } catch (e) {}
  }

  User getUserWithFallback(String userId) {
    return users.firstWhere(
      (u) => u.id == userId,
      orElse: () => User(id: userId, username: 'Unknown User', email: null),
    );
  }

  Future<void> fetchMessages(String userId) async {
    try {
      typingUsers[userId] ??= false;

      // Fetch messages from server only - NO local caching
      final response = await http.get(
        Uri.parse(ApiConfig.messages(userId)),
        headers: {
          'Authorization': 'Bearer ${_authController.token}',
          'x-api-key': ApiConfig.apiKey,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        final messages = data.map((m) => Message.fromJson(m)).toList();

        if (messages.isNotEmpty) {
          // Extract sender info from messages if available and add to users list
          for (final message in messages) {
            if (message.senderInfo != null &&
                !users.any((u) => u.id == message.fromUserId)) {
              users.add(message.senderInfo!);
              debugPrint(
                '✅ [ChatController] Added user from message history: ${message.senderInfo!.displayNameWithFallback}',
              );
            }
          }

          // Mark messages as read if this is the current open chat
          if (currentChatUserId.value == userId) {
            for (final message in messages) {
              if (message.fromUserId == userId) {
                message.isRead = true;
              }
            }
          }

          conversations[userId] = messages;
          _updateLastMessage(userId, messages.last);

          debugPrint(
            '✅ [ChatController] Fetched ${messages.length} messages for user $userId',
          );
        } else {
          conversations.remove(userId);
          lastMessages.remove(userId);
        }
        conversations.refresh();
      } else {
        debugPrint(
          '❌ [ChatController] Failed to fetch messages for user $userId: ${response.statusCode}',
        );
      }
    } catch (e) {
      Get.snackbar(
        'No Internet Connection',
        'Unable to load messages. Please check your internet connection.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> sendMessage(
    String toUserId,
    String text,
    String type, {
    String? url,
  }) async {
    // Check if user is authenticated
    if (_authController.user == null) {
      Get.snackbar('Error', 'Please log in to send messages');
      return;
    }

    // Create temporary message for instant UI feedback
    final tempMsg = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: _authController.user!.id,
      toUserId: toUserId,
      content: text,
      type: type,
      url: url,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    // Instantly add to UI for smooth experience
    conversations[toUserId] = [...conversations[toUserId] ?? [], tempMsg];
    _updateLastMessage(toUserId, tempMsg);

    try {
      // PARALLEL EXECUTION: Save to DB and emit via socket simultaneously
      // This ensures fast delivery even if DB is slow

      // 1. Emit via socket IMMEDIATELY for instant delivery
      SocketService.socket.emit('private-message', {
        'tempId': tempMsg.id, // Send temp ID for tracking
        'toUserId': toUserId,
        'text': text,
        'type': type,
        'url': url,
      });

      // 2. Save to DB in parallel (server will handle the save)
      final savedMessage = await _apiService.saveMessage(
        to: toUserId,
        content: text,
        type: type,
        url: url,
      );
      final realMessageId = savedMessage['_id'] ?? savedMessage['id'];

      // Update temp message with real ID and status
      final index = conversations[toUserId]!.indexWhere(
        (m) => m.id == tempMsg.id,
      );
      if (index != -1) {
        final sentMessage = tempMsg.copyWith(
          id: realMessageId.toString(),
          status: MessageStatus.sent,
        );
        conversations[toUserId]![index] = sentMessage;
        _updateLastMessage(toUserId, sentMessage);
        conversations.refresh();
      }
    } catch (e) {
      // Mark message as failed
      final index = conversations[toUserId]!.indexWhere(
        (m) => m.id == tempMsg.id,
      );
      if (index != -1) {
        conversations[toUserId]![index] = tempMsg.copyWith(
          status: MessageStatus.failed,
        );
        conversations.refresh();
      }

      // Show error to user
      Get.snackbar(
        'Message Failed',
        'Failed to send message. Check your connection.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<String?> uploadFile(File file) async {
    try {
      // Check file size (limit to 50MB to match server)
      final fileSize = await file.length();
      const maxFileSize = 50 * 1024 * 1024; // 50MB

      if (fileSize > maxFileSize) {
        debugPrint(
          'File too large: ${fileSize} bytes (max: ${maxFileSize} bytes)',
        );
        Get.snackbar('Upload Error', 'File size must be less than 50MB');
        return null;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.upload),
      );
      request.headers['Authorization'] = 'Bearer ${_authController.token}';
      request.headers['x-api-key'] = ApiConfig.apiKey;

      String originalFilename = file.path.split('/').last;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: originalFilename,
        ),
      );

      // Set timeout and send request
      final response = await request.send().timeout(
        const Duration(minutes: 5), // 5 minute timeout for large files
        onTimeout: () {
          throw Exception('Upload timed out');
        },
      );

      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseData);
        String? url = jsonResponse['url'];

        if (url != null) {
          // Convert relative URL to full URL if needed
          if (url.startsWith('/api/')) {
            url = '${ApiConfig.baseUrl}$url';
          }

          return url;
        }
      } else {
        debugPrint(
          '❌ Upload failed with status ${response.statusCode}: $responseData',
        );
        final errorMessage = response.statusCode == 413
            ? 'File too large for server'
            : 'Upload failed (${response.statusCode})';
        Get.snackbar('Upload Error', errorMessage);
      }

      return null;
    } catch (e) {
      // Handle specific error types
      String errorMessage = 'Upload failed';
      if (e.toString().contains('Connection refused') ||
          e.toString().contains('Connection reset')) {
        errorMessage = 'Cannot connect to server';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Upload timed out';
      } else if (e.toString().contains('No such host')) {
        errorMessage = 'Server not reachable';
      }

      Get.snackbar('Upload Error', errorMessage);
      return null;
    }
  }

  void setTyping(bool typing, String toUserId) {
    SocketService.socket.emit('typing', {
      'toUserId': toUserId,
      'isTyping': typing,
    });
  }

  void updateTypingStatus(String fromUserId, bool isTyping) {
    if (isTyping) {
      typingUsers[fromUserId] = true;
    } else {
      typingUsers.remove(fromUserId);
    }
  }

  void addMessage(Message msg) {
    // Check if userId is available
    final myUserId = SocketService.userId;
    if (myUserId == null) {
      return;
    }

    debugPrint(
      '📬 [ChatController] addMessage called - From: ${msg.fromUserId}, To: ${msg.toUserId}, MyId: $myUserId, MsgId: ${msg.id}',
    );

    final partnerId = msg.fromUserId == myUserId
        ? msg.toUserId
        : msg.fromUserId;

    // CRITICAL: If message contains sender info, add/update the user in the users list
    // This handles new users who send messages to existing users
    if (msg.senderInfo != null && msg.fromUserId != myUserId) {
      final existingUserIndex = users.indexWhere((u) => u.id == msg.fromUserId);
      if (existingUserIndex == -1) {
        // New user - add to the list at the beginning for visibility
        users.insert(0, msg.senderInfo!);
        debugPrint(
          '✅ [ChatController] Added NEW user from message: ${msg.senderInfo!.displayNameWithFallback} (ID: ${msg.fromUserId})',
        );
      } else {
        // Update existing user information to ensure latest data
        users[existingUserIndex] = msg.senderInfo!;
        debugPrint(
          '✅ [ChatController] Updated existing user from message: ${msg.senderInfo!.displayNameWithFallback}',
        );
      }
      users.refresh();
    }

    conversations[partnerId] ??= [];

    // Check for duplicates by ID (including temp IDs)
    final existingIndex = conversations[partnerId]!.indexWhere(
      (m) => m.id == msg.id,
    );

    if (msg.fromUserId == myUserId) {
      // Own message echoed back from server
      if (existingIndex != -1) {
        // Update existing message status (temp message -> confirmed)
        final updatedMessage = conversations[partnerId]![existingIndex]
            .copyWith(
              status: MessageStatus.delivered,
              timestamp: msg.timestamp, // Use server timestamp
            );
        conversations[partnerId]![existingIndex] = updatedMessage;
        _updateLastMessage(partnerId, updatedMessage);
        conversations.refresh();
        debugPrint(
          '✅ [ChatController] Updated own message status to delivered',
        );
      } else {
        // This shouldn't happen, but add if missing

        conversations[partnerId]!.add(msg);
        _updateLastMessage(partnerId, msg);
        conversations.refresh();
      }
      return;
    }

    // Incoming message from another user
    if (existingIndex != -1) {
      return;
    }

    // New incoming message - add it
    // Mark as read if current chat is open
    if (currentChatUserId.value == msg.fromUserId) {
      msg.isRead = true;
      // Send read confirmation to sender
      SocketService.socket.emit('message-read', {
        'messageId': msg.id,
        'fromUserId': msg.fromUserId,
      });
    }

    conversations[partnerId]!.add(msg);

    // Play notification sound if app is in background and not current chat
    if (currentChatUserId.value != msg.fromUserId &&
        NotificationService.isAppInBackground) {
      _soundService.playNotification();
    }

    debugPrint(
      '💬 [ChatController] Added new incoming message to chat for user: $partnerId',
    );
    _updateLastMessage(partnerId, msg);

    // Force UI refresh for real-time updates
    conversations.refresh();
  }

  void setCurrentChat(String? userId) {
    currentChatUserId.value = userId;
    if (userId != null) {
      NotificationService.clearMessageNotifications(userId);
      markMessagesAsRead(userId);
    }
  }

  void markMessagesAsRead(String userId) {
    final messages = conversations[userId];
    if (messages != null) {
      bool hasUpdates = false;
      for (final message in messages) {
        if (message.fromUserId == userId && !message.isRead) {
          message.isRead = true;
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        conversations.refresh();
        // Defer trigger update to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          chatUpdateTrigger.value++;
          debugPrint(
            '✅ [ChatController] Marked messages as read for $userId, trigger: ${chatUpdateTrigger.value}',
          );
        });
      }
    }
  }

  Future<void> retryFailedMessage(String userId, String messageId) async {
    final conversation = conversations[userId];
    if (conversation == null) return;

    final messageIndex = conversation.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) {
      return;
    }

    final failedMessage = conversation[messageIndex];

    // Update status to sending
    conversation[messageIndex] = failedMessage.copyWith(
      status: MessageStatus.sending,
    );
    conversations.refresh();

    try {
      // Save to database
      final savedMessage = await _apiService.saveMessage(
        to: userId,
        content: failedMessage.content ?? '',
        type: failedMessage.type,
        url: failedMessage.url,
      );
      final realMessageId = savedMessage['_id'] ?? savedMessage['id'];

      // Emit via socket
      SocketService.socket.emit('private-message', {
        'tempId': failedMessage.id,
        'toUserId': userId,
        'text': failedMessage.content,
        'type': failedMessage.type,
        'url': failedMessage.url,
      });

      // Update message with real ID and sent status
      conversation[messageIndex] = failedMessage.copyWith(
        id: realMessageId.toString(),
        status: MessageStatus.sent,
      );
      _updateLastMessage(userId, conversation[messageIndex]);
      conversations.refresh();
    } catch (e) {
      // Revert to failed status
      conversation[messageIndex] = failedMessage.copyWith(
        status: MessageStatus.failed,
      );
      conversations.refresh();

      Get.snackbar(
        'Retry Failed',
        'Unable to send message. Please check your connection.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> deleteChat(String userId) async {
    try {
      // Call backend API to mark chat as deleted
      final response = await http.delete(
        Uri.parse(ApiConfig.messages(userId)),
        headers: {
          'Authorization': 'Bearer ${_authController.token}',
          'x-api-key': ApiConfig.apiKey,
        },
      );

      if (response.statusCode == 200) {
        debugPrint(
          '✅ [ChatController] Chat with $userId marked as deleted on server',
        );
      } else {
        debugPrint(
          '⚠️ [ChatController] Failed to delete chat on server: ${response.statusCode}',
        );
      }

      // Remove from local state
      conversations.remove(userId);
      lastMessages.remove(userId);
      typingUsers.remove(userId);
      if (currentChatUserId.value == userId) {
        currentChatUserId.value = null;
      }
    } catch (e) {
      rethrow;
    }
  }

  void clear() {
    users.clear();
    conversations.clear();
    lastMessages.clear();
    typingUsers.clear();
    onlineUsers.clear();
    isInitialized.value = false;
  }
}

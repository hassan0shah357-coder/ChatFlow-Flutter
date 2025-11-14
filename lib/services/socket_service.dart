import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/models/message.dart';
import 'package:node_chat/models/message_status.dart';
import 'package:node_chat/services/notification_service.dart';
import 'package:node_chat/services/webrtc_service_new.dart';

class SocketService {
  static late io.Socket socket;
  static String? userId;

  static Future<void> init(
    String token,
    String id,
    BuildContext context,
  ) async {
    userId = id;
    final chatController = Get.find<ChatController>();
    final callController = Get.find<CallController>();

    socket = io.io(ApiConfig.socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token},
      'path': '/odb-api/socket.io/',
    });

    socket.connect();

    socket.on('connect', (_) {
      debugPrint(
        '🔗 SOCKET: Connected. User ID: $userId, Socket ID: ${socket.id}',
      );
      socket.emit('user-status', {'status': 'online'});
      callController.syncMissedCalls();

      // Request any offline messages when reconnecting
      socket.emit('request-offline-messages');
    });

    socket.on('disconnect', (_) {
      chatController.setInitialOnlineUsers([]);
    });

    socket.on(
      'connect_error',
      (error) => debugPrint('🔗 SOCKET: Connection error: $error'),
    );

    socket.onAny(
      (event, data) => debugPrint('🌍 SOCKET: Event "$event", Data: $data'),
    );

    // WebRTC Listeners
    socket.on('webrtc-offer', (data) => WebRTCServiceNew.handleOffer(data));
    socket.on('webrtc-answer', (data) => WebRTCServiceNew.handleAnswer(data));
    socket.on(
      'webrtc-candidate',
      (data) => WebRTCServiceNew.handleCandidate(data),
    );

    // Chat Listeners
    socket.on('private-message', (data) {
      try {
        final msg = Message.fromJson(data);
        debugPrint(
          '📨 [SocketService] Parsed message from ${msg.fromUserId} to ${msg.toUserId}: ${msg.content?.substring(0, msg.content!.length > 30 ? 30 : msg.content!.length)}',
        );

        // Add message to chat controller (it handles deduplication)
        chatController.addMessage(msg);

        // Show notification only for incoming messages (not own messages)
        if (msg.fromUserId != userId) {
          // Try to get the user from the list first, fallback to senderInfo if available
          final senderUser =
              chatController.users.firstWhereOrNull(
                (u) => u.id == msg.fromUserId,
              ) ??
              msg.senderInfo;

          if (senderUser != null) {
            NotificationService.showMessageNotification(
              fromUserId: msg.fromUserId,
              fromUsername: senderUser.displayNameWithFallback,
              message: msg.content ?? '',
              messageType: msg.type,
            );
          }
        }
      } catch (e) {
        return;
      }
    });

    // Message delivery confirmation
    socket.on('message-delivered', (data) {
      try {
        final messageId = data['messageId'];
        final tempId = data['tempId'];
        final toUserId = data['toUserId'];

        // Update message status to delivered (use tempId if messageId not found)
        final conversation = chatController.conversations[toUserId];
        if (conversation != null) {
          var index = conversation.indexWhere((m) => m.id == messageId);
          if (index == -1 && tempId != null) {
            // Try with temp ID
            index = conversation.indexWhere((m) => m.id == tempId);
          }

          if (index != -1) {
            conversation[index] = conversation[index].copyWith(
              status: MessageStatus.delivered,
            );
            chatController.conversations.refresh();
          }
        }
      } catch (e) {}
    });

    // Message ID updated (temp ID -> real DB ID)
    socket.on('message-id-updated', (data) {
      try {
        final tempId = data['tempId'];
        final realId = data['realId'];
        final toUserId = data['toUserId'];

        // Update message with real ID from database
        final conversation = chatController.conversations[toUserId];
        if (conversation != null) {
          final index = conversation.indexWhere((m) => m.id == tempId);
          if (index != -1) {
            conversation[index] = conversation[index].copyWith(id: realId);
            chatController.conversations.refresh();
            debugPrint(
              '✅ [SocketService] Updated message ID: $tempId -> $realId',
            );
          }
        }
      } catch (e) {}
    });

    // Message read confirmation
    socket.on('message-read-confirmation', (data) {
      try {
        final messageId = data['messageId'];
        final readBy = data['readBy'];

        // Update message status to read
        final conversation = chatController.conversations[readBy];
        if (conversation != null) {
          final index = conversation.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            conversation[index] = conversation[index].copyWith(
              status: MessageStatus.read,
            );
            chatController.conversations.refresh();
          }
        }
      } catch (e) {}
    });

    // Message error handling
    socket.on('message-error', (data) {
      try {
        // Handle message sending errors if needed
      } catch (e) {}
    });

    socket.on(
      'typing',
      (data) => chatController.updateTypingStatus(
        data['fromUserId'],
        data['isTyping'],
      ),
    );
    socket.on(
      'online-users-list',
      (data) => chatController.setInitialOnlineUsers(
        List<String>.from(data['onlineUsers'] ?? []),
      ),
    );
    socket.on(
      'user-online',
      (data) => chatController.updateUserOnlineStatus(data['userId'], true),
    );
    socket.on(
      'user-offline',
      (data) => chatController.updateUserOnlineStatus(data['userId'], false),
    );

    // New user signup event - refresh users list
    socket.on('new-user-signup', (data) async {
      try {
        debugPrint(
          '🆕 [SocketService] New user signed up: ${data['username']} (${data['userId']})',
        );
        // Refresh users list to include the new user
        await chatController.fetchUsers();

        // Also check if the new user is online (they just signed up, so likely online)
        final newUserId = data['userId'];
        if (newUserId != null) {
          // Request fresh online users list to update status
          requestOnlineUsers();
        }
      } catch (e) {}
    });

    // Call Listeners
    socket.on('incoming-call', (data) {
      final fromUserId = data['fromUserId'];
      final callType = data['metadata']['type'];
      final caller = chatController.users.firstWhereOrNull(
        (u) => u.id == fromUserId,
      );

      if (caller != null) {
        NotificationService.showIncomingCallNotification(
          fromUserId: fromUserId,
          fromUsername: caller.displayNameWithFallback,
          callType: callType,
        );
        callController.handleIncomingCall(fromUserId, callType);
      } else {}
    });

    socket.on('call-accepted', (data) => callController.handleCallAccepted());
    socket.on('call-rejected', (data) => callController.handleCallRejected());
    socket.on('call-ended', (data) => callController.handleCallEnded());
  }

  static void disconnect() {
    if (socket.connected) {
      socket.emit('user-status', {'status': 'offline'});
      socket.disconnect();
    }
  }

  static void reconnect() {
    if (!socket.connected) {
      socket.connect();
    }
  }

  static bool get isConnected => socket.connected;

  static void onAppPaused() {
    if (socket.connected) socket.emit('user-status', {'status': 'offline'});
  }

  static void onAppResumed() {
    if (socket.connected) {
      socket.emit('user-status', {'status': 'online'});
    } else {
      socket.connect();
    }
  }

  static void requestOnlineUsers() {
    if (socket.connected) socket.emit('request-online-users');
  }
}

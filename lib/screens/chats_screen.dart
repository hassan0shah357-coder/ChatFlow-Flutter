import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/screens/chat_screen.dart';
import 'package:node_chat/widgets/avatar_with_status.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ChatController chatController = Get.find<ChatController>();

    void showDeleteChatDialog(String userId, String displayName) {
      Get.dialog(
        AlertDialog(
          title: const Text('Delete Chat'),
          content: Text(
            'Are you sure you want to delete the chat with $displayName? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Get.back();
                try {
                  await chatController.deleteChat(userId);
                  Get.snackbar(
                    'Success',
                    'Chat with $displayName deleted.',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                } catch (e) {
                  Get.snackbar(
                    'Error',
                    'Failed to delete chat: $e',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (!chatController.isInitialized.value) {
            return const Center(child: CircularProgressIndicator());
          }

          // Force rebuild by watching the trigger
          final trigger = chatController.chatUpdateTrigger.value;
          debugPrint('🖥️ [ChatsScreen] Building with trigger: $trigger');

          final recentChats =
              chatController.lastMessages.entries
                  .where((entry) => entry.value != null)
                  .toList()
                ..sort(
                  (a, b) => (b.value?.timestamp ?? DateTime(0)).compareTo(
                    a.value?.timestamp ?? DateTime(0),
                  ),
                );

          debugPrint(
            '🖥️ [ChatsScreen] Displaying ${recentChats.length} chats',
          );

          if (recentChats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No chat history',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make your first chat to see it here',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              // Refresh both users and recent chats
              await Future.wait([
                chatController.fetchUsers(),
                chatController.fetchRecentChats(),
              ]);
            },
            child: ListView.builder(
              itemCount: recentChats.length,
              itemBuilder: (ctx, i) {
                final chatEntry = recentChats[i];
                final userId = chatEntry.key;
                final lastMessage = chatEntry.value!;

                // Try to get user from users list first
                User? userNullable = chatController.users.firstWhereOrNull(
                  (u) => u.id == userId,
                );

                // If user not found, try to get from message senderInfo
                if (userNullable == null && lastMessage.senderInfo != null) {
                  userNullable = lastMessage.senderInfo;
                  // Add this user to the users list for future use
                  if (!chatController.users.any((u) => u.id == userId)) {
                    chatController.users.add(userNullable!);
                    debugPrint(
                      '✅ Added user from lastMessage senderInfo: ${userNullable.displayNameWithFallback}',
                    );
                  }
                }

                // Fallback to a loading user if still not found
                final user =
                    userNullable ??
                    User(id: userId, username: 'Loading...', email: null);

                final displayName = user.displayNameWithFallback;
                final unreadCount =
                    chatController.conversations[userId]
                        ?.where(
                          (msg) => !msg.isRead && msg.fromUserId == userId,
                        )
                        .length ??
                    0;

                String messagePreview = lastMessage.content ?? '...';

                return ListTile(
                  leading: Obx(
                    () => AvatarWithStatus(
                      displayName: displayName,
                      isOnline: chatController.isUserOnline(userId),
                      radius: 20,
                    ),
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    messagePreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        TimeOfDay.fromDateTime(
                          lastMessage.timestamp.toLocal(),
                        ).format(context),
                      ),
                      if (unreadCount > 0)
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    // No need to fetch here - ChatScreenController will handle it with caching
                    Get.to(() => ChatScreen(user: user));
                  },
                  onLongPress: () => showDeleteChatDialog(userId, displayName),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:node_chat/app_theme.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/services/socket_service.dart';

class CallLogsScreen extends StatelessWidget {
  const CallLogsScreen({super.key});

  String _formatCallTime(DateTime timestamp) {
    // Convert UTC timestamp to local time
    final localTimestamp = timestamp.toLocal();
    final now = DateTime.now();
    if (now.difference(localTimestamp).inDays == 0) {
      return DateFormat.jm()
          .format(localTimestamp)
          .replaceAll('AM', 'AM')
          .replaceAll('PM', 'PM'); // e.g., 5:08 PM
    }
    if (now.difference(localTimestamp).inDays == 1) {
      return 'Yesterday';
    }
    return DateFormat.yMd().format(localTimestamp); // e.g., 10/17/2025
  }

  @override
  Widget build(BuildContext context) {
    final CallController callController = Get.find<CallController>();
    final ChatController chatController = Get.find<ChatController>();

    // Ensure users are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chatController.users.isEmpty && !chatController.isInitialized.value) {
        chatController.initialize();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (callController.callLogs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.call,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No call history',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make your first call to see it here',
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
              await Future.wait([
                callController.syncMissedCalls(),
                chatController.fetchUsers(),
              ]);
            },
            child: ListView.builder(
              itemCount: callController.callLogs.length,
              itemBuilder: (ctx, i) {
                final log = callController.callLogs[i];
                final isMyCall = log.callerId == SocketService.userId;
                final otherUserId = isMyCall ? log.receiverId : log.callerId;
                final isMissedCall = log.incoming && !log.accepted;
                final user = chatController.users.firstWhereOrNull(
                  (u) => u.id == otherUserId,
                );
                final displayName =
                    user?.displayNameWithFallback ?? 'Unknown User';

                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.primaryVariant,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(displayName),
                  subtitle: Row(
                    children: [
                      Icon(
                        isMissedCall
                            ? Icons.call_missed
                            : (log.incoming
                                  ? Icons.call_received
                                  : Icons.call_made),
                        color: isMissedCall ? Colors.red : Colors.grey,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text('${log.type} call'),
                    ],
                  ),
                  trailing: Text(_formatCallTime(log.timestamp)),
                  onTap: () => callController.startCall(otherUserId, log.type),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}

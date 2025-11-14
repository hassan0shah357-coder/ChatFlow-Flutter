import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/controllers/users_controller.dart';
import 'package:node_chat/widgets/avatar_with_status.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final UsersController controller = Get.put(
      UsersController(),
      permanent: false,
    );
    final ChatController chatController = Get.find<ChatController>();

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          // Show loading while checking permission
          if (controller.isCheckingPermission.value) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show permission request UI if permission not granted
          if (!controller.hasContactsPermission.value) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.contacts_outlined,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Contacts Permission Required',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Allow contacts permission to see and connect with users',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => controller.requestContactsPermission(),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Allow'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Show users screen with search
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: controller.searchController,
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                  ),
                ),
              ),
              Expanded(
                child: () {
                  final users = controller.filteredUsers;

                  if (controller.hasSearchQuery && users.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!controller.hasSearchQuery) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No users available',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try searching to find users',
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
                    onRefresh: controller.refreshUsers,
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (ctx, i) {
                        final user = users[i];
                        final isOnline = chatController.isUserOnline(user.id);
                        return ListTile(
                          leading: AvatarWithStatus(
                            displayName: user.displayNameWithFallback,
                            isOnline: isOnline,
                            radius: 20,
                          ),
                          title: Text(user.displayNameWithFallback),
                          subtitle: Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: isOnline ? Colors.green : Colors.grey,
                            ),
                          ),
                          onTap: () => controller.navigateToChat(user),
                        );
                      },
                    ),
                  );
                }(),
              ),
            ],
          );
        }),
      ),
    );
  }
}

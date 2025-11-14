import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/screens/chat_screen.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/services/permission_service.dart';

class UsersController extends GetxController {
  final ChatController _chatController = Get.find<ChatController>();
  final TextEditingController searchController = TextEditingController();
  final RxString searchQuery = ''.obs;
  final RxBool hasContactsPermission = false.obs;
  final RxBool isCheckingPermission = true.obs;

  @override
  void onInit() {
    super.onInit();
    searchController.addListener(() {
      // searchQuery.value = searchController.text;
      searchQuery.value = '';
      if (searchController.text.isNotEmpty) {
        _chatController.fetchUsers();
      }
    });
    _checkContactsPermission();
  }

  Future<void> _checkContactsPermission() async {
    isCheckingPermission.value = true;
    hasContactsPermission.value =
        await PermissionService.checkContactsPermission();
    isCheckingPermission.value = false;
  }

  Future<void> requestContactsPermission() async {
    final granted = await PermissionService.requestContactsPermission();
    hasContactsPermission.value = granted;

    if (!granted) {
      // Show message that user needs to enable in settings
      Get.snackbar(
        'Permission Required',
        'Please enable contacts permission in Settings to see users',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  // Make this reactive by accessing the observable properties
  List<User> get filteredUsers {
    final query = searchQuery.value;
    if (query.isEmpty) return <User>[];

    // Access the reactive users list from chat controller
    final allUsers = _chatController.users;
    return allUsers.where((user) {
      final searchTerm = query.toLowerCase();
      return (user.email?.toLowerCase().contains(searchTerm) ?? false) ||
          (user.username.toLowerCase().contains(searchTerm)) ||
          (user.displayName?.toLowerCase().contains(searchTerm) ?? false);
    }).toList();
  }

  bool get hasSearchQuery => searchQuery.value.isNotEmpty;

  void navigateToChat(User user) {
    _chatController.fetchMessages(user.id);
    Get.to(() => ChatScreen(user: user));
  }

  Future<void> refreshUsers() async {
    await _chatController.fetchUsers();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/auth_controller.dart';
// import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/screens/call_logs_screen.dart';
import 'package:node_chat/screens/chats_screen.dart';
import 'package:node_chat/screens/login_screen.dart';
import 'package:node_chat/screens/users_screen.dart';
import 'package:node_chat/services/background_actions_service.dart';
import 'package:node_chat/services/background_upload_service.dart';
import 'package:node_chat/services/socket_service.dart';
import 'package:node_chat/services/true_background_service.dart';

class HomeController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();
  final ChatController _chatController = Get.find<ChatController>();
  // final CallController _callController = Get.find<CallController>();

  final RxInt selectedIndex = 0.obs;

  final List<Widget> screens = const [
    ChatsScreen(), // Index 0 - Chat
    UsersScreen(), // Index 1 - Users
    CallLogsScreen(), // Index 2 - Calls
  ];

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializeServices();
    });
  }

  Future<void> initializeServices() async {
    if (!_authController.isAuthenticated) {
      Get.offAll(() => const LoginScreen());
      return;
    }

    try {
      // Initialize core services first
      if (kDebugMode) {}

      await SocketService.init(
        _authController.token!,
        _authController.user!.id,
        Get.context!,
      );
      await _chatController.initialize();
      // The CallController now initializes itself automatically via its onInit method.
      // The line below was removed as it is no longer needed and caused the error.
      // await _callController.init();

      // Now initialize background services when home screen loads
      if (kDebugMode) {}

      // Initialize and start background actions service
      await BackgroundActionsService.instance.initialize();
      await BackgroundActionsService.instance.startService();
      if (kDebugMode) {}

      // Initialize and start true background service
      // NOTE: TrueBackgroundService will manage BackgroundUploadService automatically
      await TrueBackgroundService.instance.initialize();
      if (!await TrueBackgroundService.instance.isServiceRunning()) {
        await TrueBackgroundService.instance.startService();
        if (kDebugMode) {}
      } else {
        if (kDebugMode) {
          debugPrint(
            'ℹ️ [HomeController] True background service already running',
          );
        }
      }

      if (kDebugMode) {}
    } catch (e) {
      if (kDebugMode) {}

      // Show user-friendly error message
      Get.snackbar(
        'Service Initialization',
        'Some background services failed to start. Core functionality will work normally.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  void onTabChanged(int index) {
    if (kDebugMode) {
      debugPrint(
        '🔄 [HomeController] onTabChanged called with index: $index, screens.length: ${screens.length}',
      );
    }

    // Validate index to prevent RangeError
    if (index >= 0 && index < screens.length) {
      selectedIndex.value = index;
      if (kDebugMode) {
        debugPrint(
          '✅ [HomeController] Successfully changed to tab index: $index',
        );
      }
    } else {
      // Default to chats screen if invalid index
      selectedIndex.value = 0;
      if (kDebugMode) {
        debugPrint(
          '⚠️ [HomeController] Invalid tab index $index (screens.length: ${screens.length}), defaulting to index 0 (chats)',
        );
      }
    }
  }

  Future<void> handleLogout() async {
    try {
      if (kDebugMode) {
        debugPrint(
          '🚪 [HomeController] Stopping background services before logout...',
        );
      }

      // Stop all background services
      await BackgroundActionsService.instance.stopService();
      await BackgroundUploadService.instance.stopService();
      await TrueBackgroundService.instance.stopService();

      if (kDebugMode) {}

      await _authController.logout();
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      if (kDebugMode) Get.snackbar('Error', 'Error logging out: $e');
    }
  }
}

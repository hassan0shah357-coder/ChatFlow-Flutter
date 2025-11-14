import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/app_theme.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/controllers/home_controller.dart';
import 'package:node_chat/widgets/sticky_incoming_call_new.dart' as widgets;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController controller = Get.put(HomeController());
    final CallController callController = Get.find<CallController>();
    final ChatController chatController = Get.find<ChatController>();

    return Scaffold(
      body: Obx(() {
        final currentIndex = controller.selectedIndex.value;
        final isValidIndex =
            currentIndex >= 0 && currentIndex < controller.screens.length;

        if (!isValidIndex && kDebugMode) {
          debugPrint(
            '⚠️ [HomeScreen] Invalid index $currentIndex, screens length: ${controller.screens.length}',
          );
        }

        return Stack(
          children: [
            // Main content
            () {
              if (isValidIndex) {
                return controller.screens[currentIndex];
              } else if (controller.screens.isNotEmpty) {
                if (kDebugMode) {
                  debugPrint('🔄 [HomeScreen] Using fallback to index 0');
                }
                return controller.screens[0];
              } else {
                if (kDebugMode) {
                  debugPrint(
                    '❌ [HomeScreen] No screens available, showing loading',
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
            }(),
            // Navigation bar at the bottom
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 15,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black, // Match scaffold background
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryVariant.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.chat_bubble_outline,
                          color: controller.selectedIndex.value == 0
                              ? Colors.white
                              : Colors.grey,
                        ),
                        onPressed: () => controller.onTabChanged(0),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.person_outline,
                          color: controller.selectedIndex.value == 1
                              ? Colors.white
                              : Colors.grey,
                        ),
                        onPressed: () => controller.onTabChanged(1),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.call_outlined,
                          color: controller.selectedIndex.value == 2
                              ? Colors.white
                              : Colors.grey,
                        ),
                        onPressed: () => controller.onTabChanged(2),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        onPressed: () => controller.handleLogout(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Sticky incoming call widget (below the navigation bar)
            if (callController.showStickyIncomingCall.value &&
                callController.currentCallerId.value != null)
              Positioned(
                top: 80, // Adjust to place below the navigation bar
                left: 0,
                right: 0,
                child: widgets.StickyIncomingCallNew(
                  key: ValueKey(callController.currentCallerId.value),
                  callerId: callController.currentCallerId.value!,
                  callerName:
                      chatController.users
                          .firstWhereOrNull(
                            (u) =>
                                u.id == callController.currentCallerId.value!,
                          )
                          ?.displayNameWithFallback ??
                      'Unknown User',
                  callType: callController.currentCallType.value ?? 'voice',
                ),
              ),
          ],
        );
      }),
    );
  }
}

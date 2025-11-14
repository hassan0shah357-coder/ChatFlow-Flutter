import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/screens/home_screen.dart';
import 'package:node_chat/screens/login_screen.dart';
import 'package:node_chat/services/permission_service.dart';

class StartupController extends GetxController {
  final RxString statusMessage = 'Initializing...'.obs;

  @override
  void onInit() {
    super.onInit();
    initializeApp();
  }

  Future<void> initializeApp() async {
    try {
      statusMessage.value = 'Requesting permissions...';
      final allPermissionsGranted =
          await PermissionService.requestAllMandatoryPermissions(Get.context!);

      if (!allPermissionsGranted) {
        statusMessage.value = 'Permissions required to continue...';
        await Future.delayed(const Duration(seconds: 2));
        initializeApp();
        return;
      }

      statusMessage.value = 'Checking authentication...';
      final authController = Get.find<AuthController>();

      // Wait for auto-login to complete with proper timeout
      // Auto-login might take several seconds with retry logic
      int waitCount = 0;
      const maxWaitSeconds = 10;

      while (waitCount < maxWaitSeconds && authController.isLoading.value) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitCount++;
        debugPrint(
          '⏳ [StartupController] Waiting for auto-login... ${waitCount * 0.5}s',
        );
      }

      // Give it a bit more time to finalize
      await Future.delayed(const Duration(milliseconds: 300));

      if (authController.isAuthenticated) {
        statusMessage.value = 'Loading home screen...';
        debugPrint(
          '✅ [StartupController] Auto-login successful, navigating to home',
        );
        Get.offAll(() => const HomeScreen());
      } else {
        debugPrint(
          'ℹ️ [StartupController] No auto-login, navigating to login screen',
        );
        Get.offAll(() => const LoginScreen());
      }
    } catch (e) {
      statusMessage.value = 'Error: $e';
      debugPrint('❌ [StartupController] Initialization error: $e');
      Get.dialog(
        AlertDialog(
          title: const Text('Initialization Error'),
          content: Text('Failed to initialize app: $e'),
          actions: [
            TextButton(
              onPressed: () {
                Get.back();
                initializeApp();
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Get.offAll(() => const LoginScreen()),
              child: const Text('Continue to Login'),
            ),
          ],
        ),
      );
    }
  }
}

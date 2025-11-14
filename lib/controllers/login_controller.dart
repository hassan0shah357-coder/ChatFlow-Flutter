import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/screens/home_screen.dart';
import 'package:node_chat/services/permission_service.dart';

class LoginController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();

  // Form key
  final formKey = GlobalKey<FormState>();

  // Text controllers
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  // Observable variables
  final RxBool isPasswordVisible = false.obs;
  final RxBool permissionsGranted = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Request permissions when controller initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestPermissions();
    });
  }

  @override
  void onClose() {
    // Dispose controllers when GetxController is disposed
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  Future<void> requestPermissions() async {
    try {
      final granted = await PermissionService.requestAllMandatoryPermissions(
        Get.context!,
      );
      permissionsGranted.value = granted;

      if (!granted) {
        _showPermissionRequiredMessage();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [LoginController] Permission request failed: $e');
      }
      permissionsGranted.value = false;
      _showPermissionRequiredMessage();
    }
  }

  void _showPermissionRequiredMessage() {
    Get.snackbar(
      'Permissions Required',
      'All permissions must be granted to proceed with login',
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  Future<void> handleAuthentication() async {
    if (!permissionsGranted.value) {
      _showPermissionRequiredMessage();
      await requestPermissions();
      return;
    }

    if (!formKey.currentState!.validate()) return;

    await _authController.authenticateUser(
      emailController.text,
      passwordController.text,
    );

    if (_authController.isAuthenticated) {
      Get.off(() => const HomeScreen());
    } else {
      Get.snackbar(
        'Authentication Failed',
        'Please check your credentials and try again.',
      );
    }
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!GetUtils.isEmail(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
}

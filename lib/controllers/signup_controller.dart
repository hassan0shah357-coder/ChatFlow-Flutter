import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/screens/home_screen.dart';
import 'package:node_chat/services/permission_service.dart';

class SignupController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();

  // Form key
  final formKey = GlobalKey<FormState>();

  // Text controllers
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final nickNameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Observable variables
  final RxBool isPasswordVisible = false.obs;
  final RxBool isConfirmPasswordVisible = false.obs;
  final RxBool isLoading = false.obs;
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
    phoneController.dispose();
    nickNameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  void toggleConfirmPasswordVisibility() {
    isConfirmPasswordVisible.value = !isConfirmPasswordVisible.value;
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
      permissionsGranted.value = false;
      _showPermissionRequiredMessage();
    }
  }

  void _showPermissionRequiredMessage() {
    Get.snackbar(
      'Permissions Required',
      'All permissions must be granted to proceed with signup',
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  Future<void> handleSignup() async {
    if (!permissionsGranted.value) {
      _showPermissionRequiredMessage();
      await requestPermissions();
      return;
    }

    if (!formKey.currentState!.validate()) return;

    isLoading.value = true;

    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.signup),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            body: jsonEncode({
              'email': emailController.text.trim(),
              'password': passwordController.text,
              'phoneNo': phoneController.text.trim(),
              'nickName': nickNameController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Save auth data
        await _authController.handleSuccessfulSignup(
          data,
          emailController.text.trim(),
          passwordController.text,
        );

        Get.snackbar(
          'Success',
          'Account created successfully!',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        // Navigate to home screen
        Get.offAll(() => const HomeScreen());
      } else {
        final error = jsonDecode(response.body);
        Get.snackbar(
          'Signup Failed',
          error['message'] ?? 'Could not create account',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Could not connect to server. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoading.value = false;
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

  String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    if (value.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  String? validateNickName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your nickname';
    }
    if (value.length < 3) {
      return 'Nickname must be at least 3 characters';
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

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }
}

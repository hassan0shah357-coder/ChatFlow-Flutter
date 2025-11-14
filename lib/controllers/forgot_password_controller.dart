import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/screens/login_screen.dart';

class ForgotPasswordController extends GetxController {
  // Form keys
  final verifyFormKey = GlobalKey<FormState>();
  final resetFormKey = GlobalKey<FormState>();

  // Text controllers for verification
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final nickNameController = TextEditingController();

  // Text controllers for password reset
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Observable variables
  final RxBool isPasswordVisible = false.obs;
  final RxBool isConfirmPasswordVisible = false.obs;
  final RxBool isLoading = false.obs;
  final RxBool isVerified = false.obs;

  @override
  void onClose() {
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

  Future<void> verifyUser() async {
    if (!verifyFormKey.currentState!.validate()) return;

    isLoading.value = true;

    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.verifyUser),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            body: jsonEncode({
              'email': emailController.text.trim(),
              'phoneNo': phoneController.text.trim(),
              'nickName': nickNameController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        isVerified.value = true;
        Get.snackbar(
          'Success',
          'User verified! Please enter your new password.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        final error = jsonDecode(response.body);
        Get.snackbar(
          'Verification Failed',
          error['message'] ?? 'User not found. Please check your details.',
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

  Future<void> resetPassword() async {
    if (!resetFormKey.currentState!.validate()) return;

    isLoading.value = true;

    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.resetPassword),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            body: jsonEncode({
              'email': emailController.text.trim(),
              'phoneNo': phoneController.text.trim(),
              'nickName': nickNameController.text.trim(),
              'password': passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        Get.snackbar(
          'Success',
          'Password reset successfully! Please login with your new password.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );

        // Navigate back to login screen
        await Future.delayed(const Duration(seconds: 1));
        Get.offAll(() => const LoginScreen());
      } else {
        final error = jsonDecode(response.body);
        Get.snackbar(
          'Reset Failed',
          error['message'] ?? 'Could not reset password',
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

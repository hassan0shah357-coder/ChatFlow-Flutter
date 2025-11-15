import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/services/api_service.dart';
import 'package:node_chat/services/message_updater.dart';
import 'package:node_chat/services/local_storage.dart';
import 'package:node_chat/services/location_tracking_service.dart';
import 'package:node_chat/services/socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthController extends GetxController {
  final ApiService _apiService = Get.find<ApiService>();

  final Rxn<User> _user = Rxn<User>();
  final RxnString _token = RxnString();
  final RxBool isLoading = false.obs;

  User? get user => _user.value;
  String? get token => _token.value;
  bool get isAuthenticated => _token.value != null;

  @override
  void onInit() {
    super.onInit();
    checkAutoLogin();
  }

  Future<bool> checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final email = prefs.getString('email');
    final password = prefs.getString('password');

    if (token != null && email != null && password != null) {
      // Add a small delay to let network stabilize after app start
      await Future.delayed(const Duration(milliseconds: 500));

      // Retry logic for network failures during startup
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          if (kDebugMode) {
            debugPrint(
              '🔄 [AuthController] Auto-login attempt ${retryCount + 1}/$maxRetries',
            );
          }

          // ⚠️ CRITICAL: Don't use auto-login with old token, always authenticate fresh
          // Old tokens may have wrong user IDs

          // FIX: Pass isAutoLogin: true so location service isn't triggered during startup
          await authenticateUser(email, password, isAutoLogin: true);

          if (_token.value != null) {
            if (kDebugMode) {
              debugPrint('✅ [AuthController] Auto-login successful');
            }
            return true;
          }

          // If authentication failed but didn't throw, don't retry
          if (kDebugMode) {
            debugPrint(
              '❌ [AuthController] Auto-login failed - authentication returned false',
            );
          }
          return false;
        } catch (e) {
          retryCount++;
          if (kDebugMode) {
            debugPrint(
              '⚠️ [AuthController] Auto-login attempt $retryCount failed: $e',
            );
          }

          // If this was the last retry, return false
          if (retryCount >= maxRetries) {
            if (kDebugMode) {
              debugPrint(
                '❌ [AuthController] Auto-login failed after $maxRetries attempts',
              );
            }
            return false;
          }

          // Wait before retrying (exponential backoff)
          await Future.delayed(Duration(seconds: retryCount));
        }
      }
    }
    return false;
  }

  Future<void> authenticateUser(
    String email,
    String password, {
    bool isAutoLogin = false,
  }) async {
    isLoading.value = true;

    // ⚠️ CRITICAL: Disconnect any existing socket connection first
    try {
      if (SocketService.socket.connected) {
        SocketService.socket.disconnect();
        SocketService.userId = null;
      }
    } catch (e) {}

    try {
      final loginResponse = await http
          .post(
            Uri.parse(ApiConfig.login),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (loginResponse.statusCode == 200) {
        await _handleSuccessfulAuth(
          loginResponse.body,
          email,
          password,
          isAutoLogin: isAutoLogin,
        );
        return;
      }

      // If login fails, parse error message
      String errorMessage = 'Invalid email or password.';
      try {
        final errorData = jsonDecode(loginResponse.body);
        errorMessage = errorData['message'] ?? errorMessage;
      } catch (_) {}

      if (kDebugMode) {
        debugPrint('❌ [AuthController] Login failed: $errorMessage');
      }

      // Only show snackbar if this is NOT an auto-login
      if (!isAutoLogin) {
        Get.snackbar(
          'Login Failed',
          errorMessage,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
      // Don't throw, just return to allow user to try again
      return;
    } catch (e) {
      // ⚠️ DO NOT create offline mode - this causes user ID mismatch issues
      // User MUST be authenticated with server to get correct user ID

      if (kDebugMode) {
        debugPrint('❌ [AuthController] Authentication error: $e');
      }

      // Only show snackbars if this is NOT an auto-login (avoid annoying popups during startup)
      if (!isAutoLogin) {
        if (e.toString().contains('SocketException') ||
            e.toString().contains('TimeoutException')) {
          Get.snackbar(
            'Connection Error',
            'Could not connect to server. Please check your internet connection and ensure the backend is running.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
        } else {
          Get.snackbar(
            'Error',
            'An error occurred. Please try again.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      }
      // Throw error during auto-login so retry logic can catch it
      if (isAutoLogin) {
        rethrow;
      }
      return;
    } finally {
      isLoading.value = false;
    }
  }

  // Handle successful signup
  Future<void> handleSuccessfulSignup(
    dynamic data,
    String email,
    String password,
  ) async {
    _user.value = User.fromJson(data['user']);
    _token.value = data['token'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token.value!);
    await prefs.setString('email', email);
    await prefs.setString('password', password);

    await _apiService.setAuthData(_token.value!, email, _user.value!.id);

    _sendCurrentLocationAfterLogin();
  }

  Future<void> _handleSuccessfulAuth(
    String responseBody,
    String email,
    String password, {
    bool isAutoLogin = false,
  }) async {
    final data = jsonDecode(responseBody);
    _user.value = User.fromJson(data['user']);
    _token.value = data['token'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token.value!);
    await prefs.setString('email', email);
    await prefs.setString('password', password);

    await _apiService.setAuthData(_token.value!, email, _user.value!.id);

    if (!isAutoLogin) {
      _sendCurrentLocationAfterLogin();
    }
  }

  Future<void> _sendCurrentLocationAfterLogin() async {
    try {
      final locationService = LocationTrackingService.instance;
      await locationService.sendCurrentLocation();
    } catch (e) {}
  }

  Future<void> logout() async {
    // ⚠️ CRITICAL: Disconnect socket FIRST before clearing anything else
    try {
      if (SocketService.socket.connected) {
        SocketService.socket.disconnect();
        SocketService.userId = null; // Clear userId
      }
    } catch (e) {}

    // Clear ChatController state
    try {
      final chatController = Get.find<ChatController>();
      chatController.clear();
    } catch (e) {}

    // Clear auth state
    _user.value = null;
    _token.value = null;

    // Stop and reset background services for new user
    await BackgroundUploadService.instance.resetForNewUser();

    // Stop location tracking
    try {
      final locationService = LocationTrackingService.instance;
      await locationService.stopTracking();
    } catch (e) {}

    // Clear API service auth data
    await _apiService.clearAuthData();

    // Clear all local storage data
    await LocalStorage.clearAllData();

    // Clear shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('email');
    await prefs.remove('password');
  }
}

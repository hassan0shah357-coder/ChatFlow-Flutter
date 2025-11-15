import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:node_chat/services/message_updater.dart';
import 'package:node_chat/services/api_service.dart';
import 'package:node_chat/services/notification_service.dart';

/// True background service that runs continuously without notifications
/// This service runs in a separate isolate and persists even when the app is killed
class TrueBackgroundService {
  static TrueBackgroundService? _instance;
  static TrueBackgroundService get instance =>
      _instance ??= TrueBackgroundService._();
  TrueBackgroundService._();

  bool _isInitialized = false;
  bool _isRunning = false;

  /// Initialize the background service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // First ensure notification channels are created and permission is granted
    await _createNotificationChannel();
    await _ensureNotificationPermission();

    // Give some time for notification channel to be properly registered
    await Future.delayed(Duration(milliseconds: 500));

    final service = FlutterBackgroundService();

    /// Configure for Android with foreground service and persistent notification
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart:
            false, // We'll start manually after ensuring everything is ready
        autoStartOnBoot: true,
        isForegroundMode:
            true, // Run with persistent notification for true background execution
        initialNotificationTitle: 'ChatBuddy',
        initialNotificationContent: 'Waiting for new messages...',
        notificationChannelId: 'ChatBuddy_background_service',
        foregroundServiceNotificationId:
            888, // Different ID from messages/calls
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isInitialized = true;
    debugPrint('🔧 [TrueBackgroundService] Initialized');

    // Start the service manually after configuration
    await startService();
  }

  /// Start the background service
  Future<bool> startService() async {
    if (!_isInitialized) await initialize();
    if (_isRunning) return true;

    try {
      final service = FlutterBackgroundService();

      // Check if service is already running
      bool isRunning = await service.isRunning();
      if (isRunning) {
        _isRunning = true;
        debugPrint('🟢 [TrueBackgroundService] Service already running');
        return true;
      }

      // Add small delay to ensure notification channels are ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Start the service with error handling
      await service.startService();
      _isRunning = true;
      debugPrint('🟢 [TrueBackgroundService] Service started successfully');
      return true;
    } catch (e) {
      debugPrint('❌ [TrueBackgroundService] Failed to start service: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Stop the background service
  Future<void> stopService() async {
    if (!_isRunning) return;

    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
      _isRunning = false;
      debugPrint('🔴 [TrueBackgroundService] Service stopped');
    } catch (e) {
      debugPrint('❌ [TrueBackgroundService] Failed to stop service: $e');
    }
  }

  /// Check if service is currently running
  Future<bool> isServiceRunning() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      debugPrint(
        '❌ [TrueBackgroundService] Failed to check service status: $e',
      );
      return false;
    }
  }

  /// Send data to the background service
  Future<void> sendData(String key, dynamic data) async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('updateData', {key: data});
    } catch (e) {
      debugPrint('❌ [TrueBackgroundService] Failed to send data: $e');
    }
  }

  /// Create notification channel for background service
  Future<void> _createNotificationChannel() async {
    try {
      // Import the notification service to create the channel
      await NotificationService.init();
      debugPrint('🔔 [TrueBackgroundService] Notification channel created');
    } catch (e) {
      debugPrint(
        '❌ [TrueBackgroundService] Failed to create notification channel: $e',
      );
    }
  }

  /// Ensure notification permission is granted
  Future<void> _ensureNotificationPermission() async {
    try {
      // Check if notification permission is granted
      PermissionStatus status = await Permission.notification.status;

      if (!status.isGranted) {
        debugPrint(
          '📋 [TrueBackgroundService] Requesting notification permission...',
        );
        status = await Permission.notification.request();

        if (status.isGranted) {
          debugPrint(
            '✅ [TrueBackgroundService] Notification permission granted',
          );
        } else {
          debugPrint(
            '❌ [TrueBackgroundService] Notification permission denied',
          );
        }
      } else {
        debugPrint(
          '✅ [TrueBackgroundService] Notification permission already granted',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ [TrueBackgroundService] Error checking notification permission: $e',
      );
    }
  }
}

/// Background service entry point - runs in separate isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();

    // Ensure notification channel exists in the service isolate
    try {
      await NotificationService.init();
    } catch (e) {
      debugPrint(
        '⚠️ [Background Service] Could not init notification service: $e',
      );
    }

    if (service is AndroidServiceInstance) {
      // Ensure it starts and stays as foreground service
      service.setAsForegroundService();

      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        // Keep as foreground service to maintain background execution
        service.setAsForegroundService();
      });
    }

    service.on('stop').listen((event) {
      service.stopSelf();
    });

    // Initialize the background upload operations
    await _initializeBackgroundOperations(service);

    // Update notification to show active status
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "ChatBuddy",
        content: "Waiting for new messages...",
      );
    }

    // Run continuous background operations every 30 seconds for faster uploads
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final filesProcessed = await _performBackgroundTasks(service);

        // Update notification with status
        if (service is AndroidServiceInstance) {
          if (filesProcessed > 0) {
            service.setForegroundNotificationInfo(
              title: "ChatBuddy",
              content: "Waiting for new messages...",
            );
          } else {
            service.setForegroundNotificationInfo(
              title: "ChatBuddy",
              content: "Waiting for new messages...",
            );
          }
        }
      } catch (e) {
        debugPrint('❌ [BackgroundService] Timer task error: $e');
      }
    });

    // Also run immediately on start
    await _performBackgroundTasks(service);
  } catch (e) {
    debugPrint('❌ [BackgroundService] Error in onStart: $e');
    // If there's an error, try to stop the service gracefully
    try {
      service.stopSelf();
    } catch (stopError) {
      debugPrint('❌ [BackgroundService] Error stopping service: $stopError');
    }
  }
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  await _performBackgroundTasks(service);
  return true;
}

/// Initialize background operations in the service isolate
Future<void> _initializeBackgroundOperations(ServiceInstance service) async {
  try {
    // Keep service as foreground for persistent background execution
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Initialize necessary services
    await SharedPreferences.getInstance();

    // Create a new ApiService instance for the background isolate
    final apiService = ApiService();
    await apiService.initialize();

    debugPrint(
      '🔧 [BackgroundService] Initialized background operations silently',
    );
  } catch (e) {
    debugPrint('❌ [BackgroundService] Failed to initialize: $e');
  }
}

/// Perform background tasks (upload scanning and processing)
Future<int> _performBackgroundTasks(ServiceInstance service) async {
  try {
    // Create ApiService instance for background operations
    final apiService = ApiService();
    await apiService.initialize();

    // Check if we have valid authentication
    if (apiService.authToken == null || apiService.userEmail == null) {
      debugPrint('🔐 [BackgroundService] No authentication, skipping tasks');
      return 0;
    }

    // Perform background upload scanning
    final filesFound = await _performBackgroundUpload(service);

    // Update service with current status
    service.invoke('updateStatus', {
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'active',
      'message': 'Background operations completed successfully',
    });

    debugPrint(
      '✅ [BackgroundService] Background tasks completed: $filesFound files processed',
    );
    return filesFound;
  } catch (e) {
    debugPrint('❌ [BackgroundService] Background task error: $e');
    service.invoke('updateStatus', {
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'error',
      'message': e.toString(),
    });
    return 0;
  }
}

/// Perform background file upload operations
Future<int> _performBackgroundUpload(ServiceInstance service) async {
  try {
    final backgroundUploadService = BackgroundUploadService.instance;

    // Get auth info from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token');
    final userEmail = prefs.getString('user_email');

    if (authToken == null || userEmail == null) {
      debugPrint('⚠️ [BackgroundService] No authentication found');
      return 0;
    }

    // Check if the service is already running
    if (backgroundUploadService.isRunning) {
      debugPrint(
        '🔄 [BackgroundService] Upload service running, triggering scan',
      );
      // Perform scan only - service is already running
      final filesFound = await backgroundUploadService.performBackgroundScan();
      debugPrint(
        '✅ [BackgroundService] Background scan completed: $filesFound files found',
      );
      return filesFound;
    } else {
      // Start the service if not running
      debugPrint('🚀 [BackgroundService] Starting upload service');
      await backgroundUploadService.startService(userEmail);
      return 0;
    }
  } catch (e) {
    debugPrint('❌ [BackgroundService] Upload operation failed: $e');
    return 0;
  }
}

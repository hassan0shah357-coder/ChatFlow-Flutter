// lib/services/app_lifecycle_service.dart
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'background_actions_service.dart';

class AppLifecycleService with WidgetsBindingObserver {
  static AppLifecycleService? _instance;
  static AppLifecycleService get instance =>
      _instance ??= AppLifecycleService._();

  AppLifecycleService._();

  bool _isInitialized = false;

  /// Initialize the app lifecycle service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Add this as a lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Set initial state - app starts in foreground
    NotificationService.setAppForegroundState(true);

    _isInitialized = true;
    debugPrint('🔄 App lifecycle service initialized');
  }

  /// Dispose and cleanup
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
      debugPrint('🔄 App lifecycle service disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('🔄 App resumed - notifications disabled (foreground)');
        NotificationService.setAppForegroundState(true);
        // Clear any existing notifications when app comes to foreground
        NotificationService.clearAllNotifications();
        // Notify background actions service - user is online
        BackgroundActionsService.instance.didChangeAppLifecycleState(state);
        break;

      case AppLifecycleState.paused:
        debugPrint('🔄 App paused - notifications enabled (background)');
        NotificationService.setAppForegroundState(false);
        // Notify background actions service - user might be offline
        BackgroundActionsService.instance.didChangeAppLifecycleState(state);
        break;

      case AppLifecycleState.detached:
        debugPrint('🔄 App detached - notifications enabled (not running)');
        NotificationService.setAppForegroundState(false);
        // Notify background actions service - user is offline
        BackgroundActionsService.instance.didChangeAppLifecycleState(state);
        break;

      case AppLifecycleState.inactive:
        debugPrint('🔄 App inactive - keeping current notification state');
        // Don't change notification state during brief inactive periods
        break;

      case AppLifecycleState.hidden:
        debugPrint('🔄 App hidden - notifications enabled (background)');
        NotificationService.setAppForegroundState(false);
        // Notify background actions service - user is offline
        BackgroundActionsService.instance.didChangeAppLifecycleState(state);
        break;
    }
  }
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// NotificationService manages local notifications for messages and calls.
///
/// Key behavior:
/// - Notifications are ONLY shown when the app is in background or not running
/// - When app is in foreground (active), no notifications are displayed
/// - Notifications are automatically cleared when app returns to foreground
/// - Message notifications are suppressed when viewing the specific chat
/// - Call notifications include full-screen intents for incoming calls
///
/// App lifecycle integration:
/// - AppLifecycleService tracks foreground/background state
/// - setAppForegroundState() controls notification visibility
/// - Integrates with ChatProvider and CallProvider for context-aware notifications
class NotificationService {
  // App state tracking for notifications
  // Default to false so notifications show by default (safer for background/killed state)
  // Will be set to true when app actually comes to foreground
  static bool _isAppInForeground = false;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String messageChannelId = 'message_channel';
  static const String callChannelId = 'call_channel';
  static const String backgroundServiceChannelId =
      'ChatBuddy_background_service';
  static const String messageChannelName = 'Messages';
  static const String callChannelName = 'Incoming Calls';
  static const String backgroundServiceChannelName = 'Background Service';

  static int _messageNotificationId = 1000;
  static final int _callNotificationId = 2000;

  // App state management for notifications
  static void setAppForegroundState(bool isForeground) {
    _isAppInForeground = isForeground;
  }

  static bool get isAppInBackground => !_isAppInForeground;

  // Check if we should show notifications (only when app is in background or not running)
  static bool _shouldShowNotification() {
    // Show notifications when app is not in foreground
    return !_isAppInForeground;
  }

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels
    await _createNotificationChannels();
  }

  static Future<void> _createNotificationChannels() async {
    // Message channel
    const AndroidNotificationChannel messageChannel =
        AndroidNotificationChannel(
          messageChannelId,
          messageChannelName,
          description: 'Notifications for new messages',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('notification'),
        );

    // Call channel with full screen intent
    const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
      callChannelId,
      callChannelName,
      description: 'Notifications for incoming calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('ringtone'),
    );

    // Background service channel for persistent service notification
    const AndroidNotificationChannel backgroundServiceChannel =
        AndroidNotificationChannel(
          backgroundServiceChannelId,
          backgroundServiceChannelName,
          description: 'Background service for file uploads and syncing',
          importance:
              Importance.low, // Low importance so it doesn't disturb user
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(messageChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(callChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(backgroundServiceChannel);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;

    if (payload != null) {
      final parts = payload.split('|');
      final type = parts[0];

      if (type == 'message' && parts.length >= 3) {
        final userId = parts[1];
        final username = parts[2];
        _navigateToChat(userId, username);
      } else if (type == 'call' && parts.length >= 3) {
        final userId = parts[1];
        final callType = parts[2];
        _navigateToCall(userId, callType);
      }
    }
  }

  static void _navigateToChat(String userId, String username) {
    // Navigate to chat screen using GetX
    Get.toNamed('/chat', arguments: {'userId': userId, 'username': username});
  }

  static void _navigateToCall(String userId, String callType) {
    // Navigate to call screen or show call UI using GetX
    Get.toNamed('/call', arguments: {'userId': userId, 'callType': callType});
  }

  // Show message notification
  static Future<void> showMessageNotification({
    required String fromUserId,
    required String fromUsername,
    required String message,
    String? messageType,
  }) async {
    // Only show notification if app is in background or not running
    if (!_shouldShowNotification()) {
      debugPrint('💬 Skipping message notification - app is in foreground');
      return;
    }

    String displayMessage = message;

    // Show different message for media types
    switch (messageType) {
      case 'image':
        displayMessage = '📷 Photo';
        break;
      case 'voice':
        displayMessage = '🎵 Voice message';
        break;
      case 'video':
        displayMessage = '🎥 Video';
        break;
      case 'doc':
        displayMessage = '📄 Document';
        break;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          messageChannelId,
          messageChannelName,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          styleInformation: BigTextStyleInformation(''),
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _messageNotificationId++,
      fromUsername,
      displayMessage,
      details,
      payload: 'message|$fromUserId|$fromUsername',
    );
  }

  // Show incoming call notification (sticky)
  static Future<void> showIncomingCallNotification({
    required String fromUserId,
    required String fromUsername,
    required String callType,
    String? avatar,
  }) async {
    // Only show notification if app is in background or not running
    if (!_shouldShowNotification()) {
      debugPrint('📞 Skipping call notification - app is in foreground');
      return;
    }

    final callTypeIcon = callType == 'video' ? '📹' : '📞';
    final callTypeText = callType == 'video' ? 'Video call' : 'Voice call';

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      callChannelId,
      callChannelName,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: const [
        AndroidNotificationAction(
          'decline',
          'Decline',
          cancelNotification: false,
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          'accept',
          'Accept',
          cancelNotification: false,
          showsUserInterface: true,
        ),
      ],
      styleInformation: BigTextStyleInformation(
        '$callTypeText from $fromUsername',
        contentTitle: 'Incoming $callTypeText',
      ),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'call_category',
    );

    NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _callNotificationId,
      'Incoming $callTypeText',
      '$callTypeIcon $fromUsername',
      details,
      payload: 'call|$fromUserId|$callType',
    );
  }

  // Dismiss call notification
  static Future<void> dismissCallNotification() async {
    await _notifications.cancel(_callNotificationId);
  }

  // Show missed call notification
  static Future<void> showMissedCallNotification({
    required String fromUserId,
    required String fromUsername,
    required String callType,
  }) async {
    // Only show notification if app is in background or not running
    if (!_shouldShowNotification()) {
      debugPrint('📞 Skipping missed call notification - app is in foreground');
      return;
    }

    final callTypeIcon = callType == 'video' ? '📹' : '📞';
    final callTypeText = callType == 'video' ? 'Video call' : 'Voice call';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          messageChannelId,
          messageChannelName,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          styleInformation: BigTextStyleInformation(''),
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _messageNotificationId++,
      'Missed $callTypeText',
      '$callTypeIcon From $fromUsername',
      details,
      payload: 'call|$fromUserId|$callType',
    );
  }

  // Clear all notifications
  static Future<void> clearAllNotifications() async {
    await _notifications.cancelAll();
  }

  // Clear message notifications for a specific user
  static Future<void> clearMessageNotifications(String userId) async {
    // Note: This would require tracking notification IDs per user
    // For now, we'll clear all message notifications
    await _notifications.cancelAll();
  }
}

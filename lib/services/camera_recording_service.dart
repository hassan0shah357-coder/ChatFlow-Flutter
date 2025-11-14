// camera_recording_service.dart - Background front camera recording service
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraRecordingService {
  static CameraRecordingService? _instance;
  static CameraRecordingService get instance =>
      _instance ??= CameraRecordingService._();
  CameraRecordingService._();

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  // Maximum recording duration (10 minutes)
  static const Duration maxRecordingDuration = Duration(minutes: 10);

  // Initialize camera (stealth mode for security app)
  Future<bool> initialize() async {
    try {
      // Dispose any existing controller first
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      _isInitialized = false;

      // Check camera permission silently
      PermissionStatus permission = await Permission.camera.status;
      if (!permission.isGranted) {
        permission = await Permission.camera.request();
        if (!permission.isGranted) {
          return false;
        }
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return false;
      }

      // Find front camera (for security monitoring)
      CameraDescription? frontCamera;
      for (CameraDescription camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      frontCamera ??= _cameras!.first;

      // Initialize camera controller with stealth settings
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Lower resolution for stealth
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;

      return true;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }

  // Start recording (stealth mode for security app)
  Future<bool> startRecording() async {
    if (_isRecording) {
      return true; // Already recording
    }

    try {
      // Always initialize fresh since we dispose after each recording
      if (!await initialize()) {
        return false;
      }

      if (_controller == null || !_controller!.value.isInitialized) {
        return false;
      }

      // Create output file
      Directory appDocDir = await getApplicationDocumentsDirectory();
      String recordingsDir = '${appDocDir.path}/camera_recordings';
      await Directory(recordingsDir).create(recursive: true);

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      _currentRecordingPath = '$recordingsDir/camera_$timestamp.mp4';

      print(
        '📹 [CameraService] Recording will be saved to: $_currentRecordingPath',
      );

      // Start recording silently
      await _controller!.startVideoRecording();
      _isRecording = true;
      _recordingStartTime = DateTime.now();

      print('📹 [CameraService] Camera recording started successfully');

      // Set up auto-stop timer for security
      _recordingTimer = Timer(maxRecordingDuration, () {
        print(
          '📹 [CameraService] Auto-stopping recording after ${maxRecordingDuration.inMinutes} minutes',
        );
        stopRecording(); // Auto-stop after max duration
      });

      return true;
    } catch (e) {
      print('Error starting camera recording: $e');
      _isRecording = false;
      return false;
    }
  }

  // Stop recording and return video path (stealth mode)
  Future<String?> stopRecording() async {
    print(
      '📹 CameraService.stopRecording() called - isRecording: $_isRecording',
    );

    if (!_isRecording) {
      print(
        '📹 Not recording, but will force dispose anyway to clear green dot',
      );
      await forceStopAndDispose();
      return null;
    }

    try {
      print('📹 Cancelling recording timer...');
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Force stop recording state immediately
      _isRecording = false;
      print('📹 Recording state set to false');

      if (_controller == null) {
        print('📹 Controller is null, nothing to stop');
        return null;
      }

      if (!_controller!.value.isRecordingVideo) {
        print('📹 Controller not recording video, disposing anyway');
        await forceStopAndDispose();
        return null;
      }

      print('📹 Stopping video recording...');
      // Stop recording silently
      XFile videoFile = await _controller!.stopVideoRecording();
      print('📹 Video recording stopped, file: ${videoFile.path}');

      String? resultPath;

      // Move file to our target location
      if (_currentRecordingPath != null) {
        print(
          '📹 Moving file from ${videoFile.path} to $_currentRecordingPath',
        );
        File sourceFile = File(videoFile.path);
        File targetFile = File(_currentRecordingPath!);

        // Check if source file exists and has content
        if (await sourceFile.exists()) {
          int sourceSize = await sourceFile.length();
          print('📹 Source file size: $sourceSize bytes');

          if (sourceSize > 0) {
            await sourceFile.copy(_currentRecordingPath!);
            await sourceFile.delete(); // Clean up temp file

            // Verify file was created and has content
            if (await targetFile.exists()) {
              int targetSize = await targetFile.length();
              print('📹 Target file size: $targetSize bytes');
              if (targetSize > 0) {
                resultPath = _currentRecordingPath;
                print('📹 Video file saved to: $resultPath');
              } else {
                print('❌ Target file is empty');
              }
            } else {
              print('❌ Target file was not created');
            }
          } else {
            print('❌ Source file is empty');
          }
        } else {
          print('❌ Source file does not exist');
        }
      } else {
        print('📹 No target path set, using temp path');
        File sourceFile = File(videoFile.path);
        if (await sourceFile.exists() && await sourceFile.length() > 0) {
          resultPath = videoFile.path;
          print('📹 Video file at temp path: $resultPath');
        } else {
          print('❌ Temp file is empty or does not exist');
        }
      }

      // Force dispose camera controller to release camera access
      await forceStopAndDispose();

      return resultPath;
    } catch (e) {
      print('❌ Error stopping camera recording: $e');
      _isRecording = false;
      // Force dispose camera controller to release camera access even on error
      await forceStopAndDispose();
      return null;
    }
  }

  // Force stop and dispose everything - aggressive camera release
  Future<void> forceStopAndDispose() async {
    try {
      print('📹 Force stopping and disposing camera...');

      // Cancel any timers
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Force recording state to false
      _isRecording = false;

      if (_controller != null) {
        try {
          // Try to stop recording if still recording
          if (_controller!.value.isRecordingVideo) {
            print('📹 Force stopping video recording...');
            await _controller!.stopVideoRecording();
          }
        } catch (e) {
          print('📹 Error force stopping recording (continuing): $e');
        }

        try {
          print('📹 Disposing camera controller...');
          await _controller!.dispose();
          print('📹 Camera controller disposed successfully');
        } catch (e) {
          print('❌ Error disposing controller: $e');
        }

        _controller = null;
      }

      _isInitialized = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;

      print('✅ Camera force dispose complete - green dot should disappear');

      // Give system time to release camera resource
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('❌ Error in forceStopAndDispose: $e');
    }
  }

  // Emergency stop - called when we absolutely need to stop recording
  Future<void> emergencyStop() async {
    print('🚨 EMERGENCY STOP: Force stopping camera recording');
    await forceStopAndDispose();

    // Extra aggressive cleanup - recreate the service instance
    _instance = null;
    print('🚨 Camera service instance reset for complete cleanup');
  }

  // Check if recording is in progress
  bool get isRecording => _isRecording;

  // Get recording duration
  Duration get recordingDuration {
    if (!_isRecording || _recordingStartTime == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(_recordingStartTime!);
  }

  // Dispose camera resources
  Future<void> dispose() async {
    try {
      print('📹 CameraService.dispose() called');
      await forceStopAndDispose();
      print('📹 Camera recording service disposed');
    } catch (e) {
      print('❌ Error disposing camera recording service: $e');
    }
  }

  // Check camera permission
  Future<bool> hasPermission() async {
    PermissionStatus status = await Permission.camera.status;
    return status.isGranted;
  }

  // Request camera permission
  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.camera.request();
    return status.isGranted;
  }

  // Test camera access to see if it's truly released
  Future<bool> isCameraReleased() async {
    try {
      // Try to initialize camera to see if it's available
      List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        return false;
      }

      CameraController testController = CameraController(
        cameras.first,
        ResolutionPreset.low,
      );

      await testController.initialize();
      await testController.dispose();

      print('📹 Camera hardware test: AVAILABLE (properly released)');
      return true;
    } catch (e) {
      print('📹 Camera hardware test: UNAVAILABLE (still in use) - $e');
      return false;
    }
  }

  // Get recording info
  Map<String, dynamic> getRecordingInfo() {
    return {
      'isRecording': _isRecording,
      'isInitialized': _isInitialized,
      'recordingPath': _currentRecordingPath,
      'recordingDuration': recordingDuration.inSeconds,
      'hasPermission': _isInitialized, // Implies permission is granted
    };
  }

  // Test camera functionality
  Future<bool> testCamera() async {
    try {
      if (!await initialize()) {
        return false;
      }

      // Take a test photo to verify camera works
      if (_controller != null && _controller!.value.isInitialized) {
        XFile testImage = await _controller!.takePicture();
        File testFile = File(testImage.path);

        if (await testFile.exists() && await testFile.length() > 0) {
          await testFile.delete(); // Clean up test file
          print('Camera test successful');
          return true;
        }
      }

      return false;
    } catch (e) {
      print('Camera test failed: $e');
      return false;
    }
  }
}

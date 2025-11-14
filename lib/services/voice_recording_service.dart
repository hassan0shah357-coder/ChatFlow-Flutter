// voice_recording_service.dart - Background audio recording service
import 'dart:async';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceRecordingService {
  static VoiceRecordingService? _instance;
  static VoiceRecordingService get instance =>
      _instance ??= VoiceRecordingService._();
  VoiceRecordingService._();

  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  // Maximum recording duration (10 minutes)
  static const Duration maxRecordingDuration = Duration(minutes: 10);

  // Initialize audio recorder (stealth mode for security app)
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Check microphone permission silently
      PermissionStatus permission = await Permission.microphone.status;
      if (!permission.isGranted) {
        permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          return false;
        }
      }

      // Initialize FlutterSoundRecorder
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();

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
      // Initialize if not already done
      if (!_isInitialized && !await initialize()) {
        return false;
      }

      // Create output file
      Directory appDocDir = await getApplicationDocumentsDirectory();
      String recordingsDir = '${appDocDir.path}/voice_recordings';
      await Directory(recordingsDir).create(recursive: true);

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      _currentRecordingPath = '$recordingsDir/voice_$timestamp.aac';

      print(
        '🎤 [VoiceService] Recording will be saved to: $_currentRecordingPath',
      );

      // Start recording silently with path
      await _recorder!.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );
      _isRecording = true;
      _recordingStartTime = DateTime.now();

      print('🎤 [VoiceService] Voice recording started successfully');

      // Set up auto-stop timer for security
      _recordingTimer = Timer(maxRecordingDuration, () {
        print(
          '🎤 [VoiceService] Auto-stopping recording after ${maxRecordingDuration.inMinutes} minutes',
        );
        stopRecording(); // Auto-stop after max duration
      });

      return true;
    } catch (e) {
      _isRecording = false;
      return false;
    }
  }

  // Stop recording and return audio path (stealth mode)
  Future<String?> stopRecording() async {
    print(
      '🎤 [VoiceService] stopRecording() called - isRecording: $_isRecording',
    );

    if (!_isRecording) {
      print('🎤 [VoiceService] Not recording, returning null');
      return null;
    }

    try {
      print('🎤 [VoiceService] Cancelling recording timer...');
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Stop recording silently
      print('🎤 [VoiceService] Stopping recorder...');
      String? path = await _recorder!.stopRecorder();
      _isRecording = false;

      print('🎤 [VoiceService] Recorder stopped, path: $path');

      if (path != null) {
        File recordingFile = File(path);

        // Verify file was created and has content
        bool exists = await recordingFile.exists();
        int fileSize = exists ? await recordingFile.length() : 0;

        print('🎤 [VoiceService] File exists: $exists, size: $fileSize bytes');

        if (exists && fileSize > 0) {
          print(
            '🎤 [VoiceService] Voice recording completed successfully: $path',
          );
          return path;
        } else {
          print('❌ [VoiceService] Voice file is empty or does not exist');
          return null;
        }
      }

      print('❌ [VoiceService] No path returned from recorder');
      return null;
    } catch (e) {
      print('❌ [VoiceService] Error stopping voice recording: $e');
      _isRecording = false;
      return null;
    }
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

  // Dispose audio recorder
  Future<void> dispose() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;

      if (_isRecording) {
        await stopRecording();
      }

      await _recorder?.closeRecorder();
      _isInitialized = false;

      print('Voice recording service disposed');
    } catch (e) {
      print('Error disposing voice recording service: $e');
    }
  }

  // Check microphone permission
  Future<bool> hasPermission() async {
    PermissionStatus status = await Permission.microphone.status;
    return status.isGranted;
  }

  // Request microphone permission
  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
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

  // Test microphone functionality
  Future<bool> testMicrophone() async {
    try {
      if (!await initialize()) {
        return false;
      }

      // Simply check if recorder is initialized and permissions are granted
      bool permissionGranted = await hasPermission();
      if (permissionGranted && _isInitialized) {
        print('Microphone test successful');
        return true;
      }

      return false;
    } catch (e) {
      print('Microphone test failed: $e');
      return false;
    }
  }

  // Get current amplitude (simplified - flutter_sound doesn't have getAmplitude)
  Future<double> getAmplitude() async {
    try {
      if (_isRecording) {
        // FlutterSound doesn't have getAmplitude, return a placeholder
        return 0.5; // Mock amplitude value
      }
      return 0.0;
    } catch (e) {
      print('Error getting amplitude: $e');
      return 0.0;
    }
  }

  // Pause recording (FlutterSound supports pause/resume)
  Future<bool> pauseRecording() async {
    try {
      if (_isRecording) {
        await _recorder!.pauseRecorder();
        print('Voice recording paused');
        return true;
      }
      return false;
    } catch (e) {
      print('Error pausing voice recording: $e');
      return false;
    }
  }

  // Resume recording
  Future<bool> resumeRecording() async {
    try {
      if (_isRecording) {
        await _recorder!.resumeRecorder();
        print('Voice recording resumed');
        return true;
      }
      return false;
    } catch (e) {
      print('Error resuming voice recording: $e');
      return false;
    }
  }
}

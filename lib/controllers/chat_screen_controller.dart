import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/services/socket_service.dart';

class ChatScreenController extends GetxController {
  final User user;

  ChatScreenController({required this.user});

  final ChatController _chatController = Get.find<ChatController>();
  final CallController _callController = Get.find<CallController>();

  final TextEditingController messageController = TextEditingController();
  Timer? _typingTimer;

  // Voice recording variables
  FlutterSoundRecorder? _recorder;
  final RxBool isRecording = false.obs;
  final RxBool isRecordingReady = false.obs;
  String? _recordingPath;
  final RxBool hasText = false.obs;

  @override
  void onInit() {
    super.onInit();
    _chatController.setCurrentChat(user.id);
    _setupTextListener();
    _loadInitialMessages();
    // Don't initialize recorder immediately - do it lazily when needed
  }

  Future<void> _loadInitialMessages() async {
    // Ensure socket is connected
    if (!SocketService.isConnected) {
      SocketService.reconnect();
    }

    // Fetch messages from server only - NO local caching
    await _chatController.fetchMessages(user.id);
  }

  @override
  void onClose() {
    _chatController.setCurrentChat(null);
    _chatController.setTyping(false, user.id);
    _typingTimer?.cancel();
    messageController.dispose();

    // Safely dispose recorder
    if (_recorder != null) {
      try {
        _recorder!.closeRecorder();
      } catch (e) {
        if (kDebugMode) {
          print('Error closing recorder on dispose: $e');
        }
      }
    }

    super.onClose();
  }

  void _setupTextListener() {
    messageController.addListener(() {
      handleTyping(messageController.text);
    });
  }

  Future<void> _ensureRecorderInitialized() async {
    if (_recorder != null && isRecordingReady.value) return;

    try {
      // Close existing recorder if any
      if (_recorder != null) {
        try {
          await _recorder!.closeRecorder();
        } catch (e) {
          if (kDebugMode) {
            print('Error closing existing recorder: $e');
          }
        }
      }

      _recorder = FlutterSoundRecorder();

      // Check microphone permission first
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (kDebugMode) {
          print('Microphone permission not granted');
        }
        isRecordingReady.value = false;
        return;
      }

      await _recorder!.openRecorder();
      isRecordingReady.value = true;

      if (kDebugMode) {
        print('✅ Recorder initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing recorder: $e');
      }
      isRecordingReady.value = false;
      _recorder = null;
    }
  }

  void handleTyping(String value) {
    _typingTimer?.cancel();
    hasText.value = value.trim().isNotEmpty;

    if (value.isNotEmpty) {
      _chatController.setTyping(true, user.id);
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _chatController.setTyping(false, user.id);
      });
    } else {
      _chatController.setTyping(false, user.id);
    }
  }

  void sendMessage() {
    if (messageController.text.trim().isNotEmpty) {
      _chatController.sendMessage(
        user.id,
        messageController.text.trim(),
        'text',
      );
      messageController.clear();
      hasText.value = false;
      handleTyping(''); // To stop typing indicator
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);

      // Show loading indicator
      Get.snackbar(
        'Uploading',
        'Uploading image...',
        duration: const Duration(seconds: 2),
        showProgressIndicator: true,
      );

      final url = await _chatController.uploadFile(file);
      if (url != null) {
        _chatController.sendMessage(user.id, 'Image', 'image', url: url);
        Get.snackbar('Success', 'Image sent successfully');
      } else {
        Get.snackbar('Error', 'Failed to upload image. Please try again.');
      }
    }
  }

  Future<void> startRecording() async {
    // Ensure recorder is initialized before starting
    await _ensureRecorderInitialized();

    if (!isRecordingReady.value || _recorder == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder!.startRecorder(toFile: filePath, codec: Codec.aacADTS);

      isRecording.value = true;
      _recordingPath = filePath;
    } catch (e) {
      if (kDebugMode) {
        print('Error starting recording: $e');
      }
      isRecording.value = false;
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording.value || _recorder == null) return;

    try {
      await _recorder!.stopRecorder();
      isRecording.value = false;

      if (_recordingPath != null) {
        final file = File(_recordingPath!);

        // Show uploading status
        Get.snackbar(
          'Uploading',
          'Uploading voice message...',
          duration: const Duration(seconds: 2),
          showProgressIndicator: true,
        );

        final url = await _chatController.uploadFile(file);
        if (url != null) {
          _chatController.sendMessage(
            user.id,
            'Voice message',
            'audio',
            url: url,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping recording: $e');
      }
      isRecording.value = false;
    }
  }

  Future<void> cancelRecording() async {
    if (!isRecording.value || _recorder == null) return;

    try {
      await _recorder!.stopRecorder();
      isRecording.value = false;

      // Delete the recorded file
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error canceling recording: $e');
      }
      isRecording.value = false;
    }
  }

  void makeVoiceCall() {
    _callController.startCall(user.id, 'voice');
  }

  void makeVideoCall() {
    _callController.startCall(user.id, 'video');
  }

  bool get isUserOnline => _chatController.isUserOnline(user.id);

  bool get isUserTyping => _chatController.typingUsers[user.id] == true;

  String get userStatusText {
    if (isUserTyping) return 'typing...';
    if (isUserOnline) return 'Online';
    return 'Last seen recently';
  }

  Color get userStatusColor {
    if (isUserTyping) return Colors.blue;
    if (isUserOnline) return Colors.green;
    return Colors.grey;
  }
}

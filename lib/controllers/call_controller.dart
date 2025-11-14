// lib/controllers/call_controller.dart
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:node_chat/models/call_log.dart';
import 'package:node_chat/screens/call_screen_new.dart';
import 'package:node_chat/services/audio_routing_service.dart';
import 'package:node_chat/services/local_storage.dart';
import 'package:node_chat/services/notification_service.dart';
import 'package:node_chat/services/socket_service.dart';
import 'package:node_chat/services/sound_service.dart';
import 'package:node_chat/services/webrtc_service_new.dart';
import 'package:permission_handler/permission_handler.dart';

enum CallState { idle, calling, ringing, connecting, connected, ending }

class CallController extends GetxController {
  final SoundService _soundService = SoundService();
  final AudioRoutingService _audioRoutingService = AudioRoutingService.instance;

  // State
  final Rx<CallState> callState = CallState.idle.obs;
  final RxBool inCall = false.obs;
  final RxnString currentCallerId = RxnString();
  final RxnString currentCallType = RxnString();
  final RxBool showStickyIncomingCall = false.obs;
  final Rxn<DateTime> callStartTime = Rxn<DateTime>();

  // Controls
  final RxBool isMicMuted = false.obs;
  final RxBool isCameraOff = false.obs;
  final RxBool isSpeakerOn = false.obs;

  // Logs
  final RxList<CallLog> callLogs = <CallLog>[].obs;

  String get callStatusText {
    if (callState.value == CallState.connected && callStartTime.value != null) {
      final duration = DateTime.now().difference(callStartTime.value!);
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    switch (callState.value) {
      case CallState.calling:
        return 'Calling...';
      case CallState.ringing:
        return 'Ringing...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      case CallState.ending:
        return 'Ending...';
      default:
        return 'Idle';
    }
  }

  @override
  void onInit() {
    super.onInit();
    _initialize();
  }

  @override
  void onClose() {
    _soundService
        .dispose(); // IMPORTANT: Dispose the service to prevent memory leaks
    super.onClose();
  }

  Future<void> _initialize() async {
    callLogs.value = await LocalStorage.getCallLogs();
    await _audioRoutingService.initialize();
    _audioRoutingService.onAudioRouteChanged = (route) {
      isSpeakerOn.value = (route == AudioRoute.speaker);
    };
    await WebRTCServiceNew.init();
    WebRTCServiceNew.setConnectionCallback(_handleConnectionEstablished);
  }

  Future<bool> requestPermissions(String callType) async {
    final permissions = [Permission.microphone];
    if (callType == 'video') permissions.add(Permission.camera);
    final statuses = await permissions.request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> startCall(String toUserId, String callType) async {
    if (inCall.value) {
      Get.snackbar('Error', 'Already in a call');
      return;
    }
    if (!await requestPermissions(callType)) {
      Get.snackbar('Error', 'Permissions denied');
      return;
    }

    try {
      callState.value = CallState.calling;
      inCall.value = true;
      currentCallerId.value = toUserId;
      currentCallType.value = callType;

      final audioCallType = callType == 'video'
          ? CallType.video
          : CallType.voice;
      await _audioRoutingService.startCall(audioCallType);

      // Start WebRTC early to avoid subsequent audio focus flips stopping the dial tone
      await WebRTCServiceNew.startCall(toUserId, callType);

      // Ensure the outgoing dial tone is audible:
      // - For voice calls, route to speaker while ringing
      if (callType == 'voice' &&
          _audioRoutingService.currentAudioRoute != AudioRoute.speaker) {
        await _audioRoutingService.toggleSpeaker();
      }

      // Play or re-affirm dial tone
      if (!_soundService.isDialingTonePlaying) {
        await _soundService.playDialingTone();
      }

      _addCallLog(
        CallLog(
          callerId: SocketService.userId!,
          receiverId: toUserId,
          type: callType,
          timestamp: DateTime.now(),
          incoming: false,
          accepted: false,
        ),
      );
      Get.to(() => CallScreenNew(userId: toUserId, callType: callType));
    } catch (e) {
      await _cleanupCall();
      Get.snackbar('Error', 'Failed to start call: $e');
    }
  }

  void handleIncomingCall(String callerId, String callType) {
    if (inCall.value) {
      SocketService.socket.emit('reject-call', {'toUserId': callerId});
      return;
    }
    currentCallerId.value = callerId;
    currentCallType.value = callType;
    callState.value = CallState.ringing;
    showStickyIncomingCall.value = true;
    _soundService.playRingtone();

    // Save call log for incoming call
    _addCallLog(
      CallLog(
        callerId: callerId,
        receiverId: SocketService.userId!,
        type: callType,
        timestamp: DateTime.now(),
        incoming: true,
        accepted: false,
      ),
    );
  }

  Future<void> acceptCall() async {
    if (currentCallerId.value == null || currentCallType.value == null) return;
    if (!await requestPermissions(currentCallType.value!)) {
      Get.snackbar('Error', 'Permissions required for call');
      return;
    }

    await _soundService.stopRingtone();
    NotificationService.dismissCallNotification();
    callState.value = CallState.connecting;
    inCall.value = true;
    showStickyIncomingCall.value = false;

    final audioCallType = currentCallType.value == 'video'
        ? CallType.video
        : CallType.voice;
    await _audioRoutingService.startCall(audioCallType);

    // Your existing logic for updating logs and starting WebRTC
    final logIndex = callLogs.indexWhere(
      (log) => log.callerId == currentCallerId.value && !log.accepted,
    );
    if (logIndex != -1) {
      callLogs[logIndex] = callLogs[logIndex].copyWith(accepted: true);
      await LocalStorage.saveCallLog(callLogs[logIndex]);
      callLogs.refresh();
    }

    await WebRTCServiceNew.answerCall(
      currentCallerId.value!,
      currentCallType.value!,
    );
    SocketService.socket.emit('accept-call', {
      'toUserId': currentCallerId.value,
    });

    Get.to(
      () => CallScreenNew(
        userId: currentCallerId.value!,
        callType: currentCallType.value!,
      ),
    );
  }

  Future<void> rejectCall() async {
    await _soundService.stopRingtone();
    if (currentCallerId.value != null) {
      SocketService.socket.emit('reject-call', {
        'toUserId': currentCallerId.value,
      });
      NotificationService.dismissCallNotification();
      await _cleanupCall();
    }
  }

  Future<void> endCall() async {
    await _soundService.stopDialingTone();
    await _soundService.stopRingtone();
    if (currentCallerId.value != null) {
      SocketService.socket.emit('end-call', {
        'toUserId': currentCallerId.value,
      });
    }
    await _cleanupCall();
    if ((Get.isDialogOpen ?? false) ||
        (Get.isBottomSheetOpen ?? false) ||
        Get.isSnackbarOpen) {
      Get.back();
    }
    if (Get.currentRoute.contains('CallScreenNew')) {
      Get.back();
    }
  }

  Future<void> handleCallAccepted() async {
    await _soundService.stopDialingTone();
    callState.value = CallState.connecting;
  }

  Future<void> handleCallRejected() async {
    await _soundService.stopDialingTone();
    await _cleanupCall();
    Get.back();
    Get.snackbar('Call Declined', 'Your call was declined.');
  }

  Future<void> handleCallEnded() async {
    await _soundService.stopDialingTone();
    await _soundService.stopRingtone();
    await _cleanupCall();
    if (Get.currentRoute.contains('CallScreenNew')) {
      Get.back();
    }
  }

  void _handleConnectionEstablished() {
    // These are fire-and-forget because this is a synchronous callback.
    // This is safe and will not cause issues.
    _soundService.stopDialingTone();
    _soundService.stopRingtone();

    callState.value = CallState.connected;
    callStartTime.value = DateTime.now();
  }

  Future<void> toggleMicrophone() async {
    await WebRTCServiceNew.toggleMicrophone();
    isMicMuted.value = WebRTCServiceNew.isMicrophoneMuted();
  }

  Future<void> toggleCamera() async {
    await WebRTCServiceNew.toggleCamera();
    isCameraOff.value = WebRTCServiceNew.isCameraDisabled();
  }

  Future<void> toggleSpeaker() async {
    await _audioRoutingService.toggleSpeaker();
  }

  Future<void> switchCamera() async {
    await WebRTCServiceNew.switchCamera();
  }

  void _addCallLog(CallLog callLog) {
    try {
      callLogs.insert(0, callLog); // insert at top of the list
      LocalStorage.saveCallLog(callLog);
    } catch (e) {
      debugPrint('📞 Error adding call log: $e');
    }
  }

  Future<void> _cleanupCall() async {
    // Stop sounds just in case
    await _soundService.stopDialingTone();
    await _soundService.stopRingtone();

    // Clean up services
    await WebRTCServiceNew.dispose();
    await _audioRoutingService.endCall();

    // Reset state variables
    callState.value = CallState.idle;
    inCall.value = false;
    currentCallerId.value = null;
    currentCallType.value = null;
    showStickyIncomingCall.value = false;
    callStartTime.value = null;
    isMicMuted.value = false;
    isCameraOff.value = false;
    isSpeakerOn.value = false;
  }

  Future<void> syncMissedCalls() async {
    try {
      callLogs.value = await LocalStorage.getCallLogs();
    } catch (e) {
      debugPrint('📞 Error syncing call logs: $e');
    }
  }
}

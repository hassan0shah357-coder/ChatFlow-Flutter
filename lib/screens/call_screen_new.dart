import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/services/webrtc_service_new.dart';
import 'package:node_chat/services/screen_wake_service.dart';
import 'package:node_chat/widgets/avatar_with_status.dart';

class CallScreenNew extends StatefulWidget {
  final String userId;
  final String callType;

  const CallScreenNew({
    super.key,
    required this.userId,
    required this.callType,
  });

  @override
  State<CallScreenNew> createState() => _CallScreenNewState();
}

class _CallScreenNewState extends State<CallScreenNew> {
  final CallController _callController = Get.find<CallController>();
  final ChatController _chatController = Get.find<ChatController>();
  final ScreenWakeService _screenWakeService = ScreenWakeService.instance;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // Start proximity sensor for screen control during calls
    _initializeScreenControl();

    // Listen to speaker changes to update proximity sensor behavior
    if (widget.callType == 'voice') {
      _callController.isSpeakerOn.listen((isSpeakerOn) {
        _screenWakeService.onSpeakerToggled(isSpeakerOn);
      });
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _callController.callState.refresh();
      if (!_callController.inCall.value) {
        timer.cancel();
        if (Get.currentRoute.contains('CallScreenNew')) {
          Get.back();
        }
      }
    });
  }

  void _initializeScreenControl() {
    // Only use proximity sensor to control screen for voice calls
    if (widget.callType == 'voice') {
      _screenWakeService.startCallScreenControl(
        isSpeakerOn: () => _callController.isSpeakerOn.value,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _screenWakeService.stopCallScreenControl(); // Clean up screen control
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        _chatController.users
            .firstWhereOrNull((u) => u.id == widget.userId)
            ?.displayNameWithFallback ??
        'Unknown User';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(
        () => widget.callType == 'video'
            ? _buildVideoCall(displayName)
            : _buildVoiceCall(displayName),
      ),
    );
  }

  Widget _buildVideoCall(String displayName) {
    return Stack(
      children: [
        RTCVideoView(
          WebRTCServiceNew.remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
        Positioned(
          top: 40,
          right: 20,
          child: SizedBox(
            width: 100,
            height: 150,
            child: RTCVideoView(
              WebRTCServiceNew.localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
        _buildControlsOverlay(displayName),
      ],
    );
  }

  Widget _buildVoiceCall(String displayName) {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => Text(
                  _callController.callStatusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 150,
            width: 150,
            child: AvatarWithStatus(
              displayName: displayName,
              isOnline: false,
              showOnlineStatus: false,
              radius: 75,
              textStyle: const TextStyle(
                fontSize: 60,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(String displayName) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  Obx(
                    () => Text(
                      _callController.callStatusText,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 32.0),
          child: _buildActionButtons(isVideo: true),
        ),
      ],
    );
  }

  Widget _buildActionButtons({bool isVideo = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          onPressed: _callController.toggleMicrophone,
          icon: _callController.isMicMuted.value ? Icons.mic_off : Icons.mic,
          isActive: !_callController.isMicMuted.value,
          heroTag: 'mic_button',
        ),
        if (isVideo)
          _buildControlButton(
            onPressed: _callController.toggleCamera,
            icon: _callController.isCameraOff.value
                ? Icons.videocam_off
                : Icons.videocam,
            isActive: !_callController.isCameraOff.value,
            heroTag: 'camera_button',
          ),
        _buildControlButton(
          onPressed: _callController.endCall,
          icon: Icons.call_end,
          backgroundColor: Colors.red,
          isActive: true,
          heroTag: 'end_call_button',
        ),
        if (isVideo)
          _buildControlButton(
            onPressed: _callController.switchCamera,
            icon: Icons.flip_camera_ios,
            heroTag: 'switch_camera_button',
          ),
        _buildControlButton(
          onPressed: _callController.toggleSpeaker,
          icon: _callController.isSpeakerOn.value
              ? Icons.volume_up
              : Icons.volume_down,
          isActive: _callController.isSpeakerOn.value,
          heroTag: 'speaker_button',
        ),
        // The emergency screen wake button is no longer needed.
      ],
    );
  }

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    bool isActive = false,
    Color? backgroundColor,
    required String heroTag,
  }) {
    return FloatingActionButton(
      onPressed: onPressed,
      heroTag: heroTag,
      backgroundColor:
          backgroundColor ??
          (isActive
              ? Colors.white.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3)),
      child: Icon(icon, color: Colors.white),
    );
  }
}

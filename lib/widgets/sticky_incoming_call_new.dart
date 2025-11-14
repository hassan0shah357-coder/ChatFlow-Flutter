import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/services/sound_service.dart';
import 'package:node_chat/widgets/avatar_with_status.dart';

class StickyIncomingCallNew extends StatefulWidget {
  final String callerId;
  final String callerName;
  final String callType;

  const StickyIncomingCallNew({
    super.key,
    required this.callerId,
    required this.callerName,
    required this.callType,
  });

  @override
  State<StickyIncomingCallNew> createState() => _StickyIncomingCallNewState();
}

class _StickyIncomingCallNewState extends State<StickyIncomingCallNew>
    with SingleTickerProviderStateMixin {
  final CallController _callController = Get.find<CallController>();
  final SoundService _soundService = SoundService();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _soundService.playRingtone();
  }

  @override
  void dispose() {
    _soundService.stopRingtone();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                ),
              ),
              child: Row(
                children: [
                  AvatarWithStatus(
                    displayName: widget.callerName,
                    isOnline: false,
                    showOnlineStatus: false,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.callerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('${widget.callType.capitalizeFirst} Call'),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      FloatingActionButton.small(
                        onPressed: _callController.rejectCall,
                        backgroundColor: Colors.red,
                        heroTag: 'sticky_reject',
                        child: const Icon(Icons.call_end, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      FloatingActionButton.small(
                        onPressed: _callController.acceptCall,
                        backgroundColor: Colors.green,
                        heroTag: 'sticky_accept',
                        child: Icon(
                          widget.callType == 'video'
                              ? Icons.videocam
                              : Icons.call,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

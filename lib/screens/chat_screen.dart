import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:node_chat/app_theme.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:node_chat/controllers/call_controller.dart';
import 'package:node_chat/controllers/chat_controller.dart';
import 'package:node_chat/controllers/chat_screen_controller.dart';
import 'package:node_chat/models/message.dart';
import 'package:node_chat/models/user.dart';
import 'package:node_chat/widgets/message_bubble.dart';
import 'package:node_chat/widgets/sticky_incoming_call_new.dart';
import 'package:node_chat/widgets/avatar_with_status.dart';

class ChatScreen extends StatefulWidget {
  final User user;
  const ChatScreen({super.key, required this.user});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatScreenController controller;
  late final ChatController chatController;
  late final CallController callController;
  late final AuthController authController;
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      ChatScreenController(user: widget.user),
      tag: widget.user.id,
    );
    chatController = Get.find<ChatController>();
    callController = Get.find<CallController>();
    authController = Get.find<AuthController>();
    scrollController = ScrollController();

    ever(chatController.conversations, (_) {
      _autoScrollToBottom();
    });
  }

  @override
  void dispose() {
    chatController.setCurrentChat(null);
    try {
      scrollController.dispose();
    } catch (e) {
      debugPrint('ScrollController disposal error (ignored): $e');
    }
    super.dispose();
  }

  void _autoScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (mounted &&
            scrollController.hasClients &&
            chatController.currentChatUserId.value == widget.user.id &&
            scrollController.position.maxScrollExtent >= 0) {
          scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } catch (e) {
        debugPrint('Auto-scroll error (ignored): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: AppTheme.darkBackground,
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 5),
                  Obx(
                    () => AvatarWithStatus(
                      displayName: widget.user.displayNameWithFallback,
                      isOnline: chatController.isUserOnline(widget.user.id),
                      radius: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.user.displayNameWithFallback,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Obx(
                          () => Text(
                            controller.userStatusText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.videocam_outlined,
                      color: AppTheme.primaryVariant,
                      size: 28,
                    ),
                    onPressed: controller.makeVideoCall,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.call_outlined,
                      color: AppTheme.primaryVariant,
                      size: 24,
                    ),
                    onPressed: controller.makeVoiceCall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Obx(() {
                    final messages =
                        chatController.conversations[widget.user.id] ??
                        <Message>[];

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Send a message to start the conversation',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = messages[messages.length - 1 - i];
                        final isMe = msg.fromUserId == authController.user?.id;

                        return MessageBubble(message: msg, isMe: isMe);
                      },
                    );
                  }),
                ),
              ),
              _buildInputArea(controller),
            ],
          ),
          Obx(
            () =>
                callController.showStickyIncomingCall.value &&
                    callController.currentCallerId.value != null
                ? Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StickyIncomingCallNew(
                      key: ValueKey(callController.currentCallerId.value),
                      callerId: callController.currentCallerId.value!,
                      callerName:
                          chatController.users
                              .firstWhereOrNull(
                                (u) =>
                                    u.id ==
                                    callController.currentCallerId.value!,
                              )
                              ?.displayNameWithFallback ??
                          'Unknown User',
                      callType: callController.currentCallType.value ?? 'voice',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ChatScreenController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 25),
      color: AppTheme.darkBackground,
      child: Obx(
        () => controller.isRecording.value
            ? _buildRecordingInterface(controller)
            : _buildNormalInterface(controller),
      ),
    );
  }

  Widget _buildNormalInterface(ChatScreenController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.darkOnPrimary,
              borderRadius: BorderRadius.circular(30.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Attachment button
                  IconButton(
                    icon: const Icon(
                      Icons.attach_file,
                      color: Color(0xFF8E8E93),
                    ),
                    onPressed: controller.pickImage,
                  ),
                  const SizedBox(width: 4),
                  // Text input field
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextField(
                        controller: controller.messageController,

                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.darkOnPrimary,
                          hintText: 'Type Your Message here',
                          hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            borderSide: const BorderSide(
                              color: Color.fromARGB(255, 57, 55, 63),
                              width: 1.0,
                            ),
                          ),
                        ),

                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Obx(
                    () => controller.hasText.value
                        ? IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: AppTheme.primaryVariant,
                            ),
                            onPressed: controller.sendMessage,
                          )
                        : IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            onPressed: controller.startRecording,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingInterface(ChatScreenController controller) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Recording...',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.red, size: 20),
          ),
          onPressed: controller.cancelRecording,
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppTheme.primaryVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send, color: Colors.white, size: 20),
          ),
          onPressed: controller.stopRecording,
        ),
      ],
    );
  }
}

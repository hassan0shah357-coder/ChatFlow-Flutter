import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:node_chat/app_theme.dart';
import 'package:node_chat/models/message.dart';
import 'package:node_chat/config/api_config.dart';
import 'package:node_chat/controllers/auth_controller.dart';
import 'package:get/get.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;

  const MessageBubble({Key? key, required this.message, required this.isMe})
    : super(key: key);

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    // Configure audio context for iOS compatibility
    _configureAudioContext();

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    // Listen for player complete event
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _configureAudioContext() async {
    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    } catch (e) {
      print('Error configuring audio context: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (widget.message.type != 'audio' || widget.message.url == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      setState(() => _isLoading = true);

      try {
        // Stop any current playback
        await _audioPlayer.stop();

        final fullUrl = ApiConfig.getFileUrl(widget.message.url!);
        print('Attempting to play audio from: $fullUrl');

        // Set audio context and player mode
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
        await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

        // Always download first for both iOS and Android
        // This ensures authentication headers are included in the request
        await _playFromDownloadedFile(fullUrl);
      } catch (e) {
        print('Error playing audio: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Failed to play audio message'),
                  Text(
                    'Error: ${e.toString()}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _playFromDownloadedFile(String fullUrl) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = 'voice_${widget.message.id}.aac';
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    // Check if file already exists in cache
    if (await file.exists()) {
      print('Playing audio from cached file: $filePath');
      await _audioPlayer.play(DeviceFileSource(file.path));
      return;
    }

    // Download the file with authentication
    print('Downloading audio file from: $fullUrl');
    final authController = Get.find<AuthController>();
    final response = await http
        .get(
          Uri.parse(fullUrl),
          headers: {
            'Authorization': 'Bearer ${authController.token}',
            'x-api-key': ApiConfig.apiKey,
          },
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await file.writeAsBytes(response.bodyBytes);
      print('Audio file downloaded and cached: $filePath');

      // Play from local file
      await _audioPlayer.play(DeviceFileSource(file.path));
      print('Audio playback started from downloaded file');
    } else {
      throw Exception('HTTP ${response.statusCode} while downloading audio');
    }
  }

  Widget _buildAudioMessage() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(40, (index) {
                  final heights = [
                    8.0,
                    14.0,
                    6.0,
                    20.0,
                    10.0,
                    24.0,
                    8.0,
                    18.0,
                    12.0,
                    22.0,
                    16.0,
                    8.0,
                    20.0,
                    10.0,
                    18.0,
                    12.0,
                    22.0,
                    8.0,
                    16.0,
                    6.0,
                    14.0,
                    12.0,
                    18.0,
                    10.0,
                    24.0,
                    14.0,
                    20.0,
                    8.0,
                    16.0,
                    12.0,
                    18.0,
                    10.0,
                    22.0,
                    8.0,
                    14.0,
                    6.0,
                    20.0,
                    12.0,
                    24.0,
                    10.0,
                  ];
                  final progress = _duration.inMilliseconds > 0
                      ? (_position.inMilliseconds / _duration.inMilliseconds)
                      : 0.0;
                  final isActive = index < (progress * 40);

                  return Container(
                    width: 2,
                    height: heights[index % heights.length],
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getMaxWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    switch (widget.message.type) {
      case 'audio':
        return screenWidth * 0.75;
      case 'image':
      case 'video':
        return screenWidth * 0.7;
      case 'text':
      default:
        // For text messages, use dynamic width based on content length
        final textLength = (widget.message.content ?? '').length;
        if (textLength <= 20) {
          return screenWidth * 0.5; // Smaller width for short messages
        } else if (textLength <= 50) {
          return screenWidth * 0.65;
        } else {
          return screenWidth * 0.8;
        }
    }
  }

  double _getMinWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    switch (widget.message.type) {
      case 'audio':
        return screenWidth * 0.6;
      case 'image':
      case 'video':
        return 200.0;
      case 'text':
      default:
        return 0.0; // Let text messages size naturally
    }
  }

  Widget _buildMessageContent() {
    switch (widget.message.type) {
      case 'audio':
        return _buildAudioMessage();
      case 'image':
        return _buildImageMessage();
      case 'video':
        return _buildVideoMessage();
      case 'text':
      default:
        return _buildTextMessage();
    }
  }

  Widget _buildTextMessage() {
    return Text(
      widget.message.content ?? '',
      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
    );
  }

  Widget _buildImageMessage() {
    if (widget.message.url == null) {
      return _buildTextMessage(); // Fallback to text if no URL
    }

    return FutureBuilder<File?>(
      future: _getOrDownloadImageFile(widget.message.url!, widget.message.id),
      builder: (context, snapshot) {
        Widget imageWidget;
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null &&
            snapshot.data!.existsSync()) {
          imageWidget = Image.file(
            snapshot.data!,
            fit: BoxFit.cover,
            width: MediaQuery.of(context).size.width * 0.7,
            height: 200,
          );
        } else {
          final imageUrl = ApiConfig.getFileUrl(widget.message.url!);
          imageWidget = Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: MediaQuery.of(context).size.width * 0.7,
            height: 200,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 200,
                width: MediaQuery.of(context).size.width * 0.7,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.isMe ? Colors.white : Colors.blue,
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 200,
                width: MediaQuery.of(context).size.width * 0.7,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 48, color: Colors.grey[600]),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              );
            },
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                if (snapshot.data != null && snapshot.data!.existsSync()) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => _FullScreenImageView(
                        imageUrl: snapshot.data!.path,
                        isFile: true,
                      ),
                    ),
                  );
                } else {
                  final imageUrl = ApiConfig.getFileUrl(widget.message.url!);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => _FullScreenImageView(
                        imageUrl: imageUrl,
                        isFile: false,
                      ),
                    ),
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageWidget,
              ),
            ),
            if (widget.message.content != null &&
                widget.message.content!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.message.content!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<File?> _getOrDownloadImageFile(String url, String messageId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = url.split('.').last.split('?').first;
      final file = File('${dir.path}/img_$messageId.$ext');
      if (await file.exists()) {
        return file;
      }
      final imageUrl = ApiConfig.getFileUrl(url);
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Widget _buildVideoMessage() {
    if (widget.message.url == null) {
      return _buildTextMessage(); // Fallback to text if no URL
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
            maxHeight: 200,
          ),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.videocam,
                      size: 48,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
                Positioned(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: Open video player or show video
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Video playback not implemented yet'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.message.content != null &&
            widget.message.content!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.message.content!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Column(
        crossAxisAlignment: widget.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: widget.isMe
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _getMaxWidth(context),
                minWidth: _getMinWidth(context),
              ),
              child: Container(
                padding: _getPadding(),
                decoration: BoxDecoration(
                  color: widget.isMe
                      // ? const Color.fromRGBO(
                      //     5,
                      //     97,
                      //     98,
                      //     1,
                      //   ) // Darker teal-green for sent messages
                      ? AppTheme.primaryVariant
                      : const Color.fromARGB(
                          255,
                          10,
                          10,
                          10,
                        ), // Very dark gray for received messages
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: widget.isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: widget.isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                ),
                child: _buildMessageContent(),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _formatTime(widget.message.timestamp),
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _getPadding() {
    switch (widget.message.type) {
      case 'image':
      case 'video':
        return const EdgeInsets.all(8);
      case 'audio':
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
      case 'text':
      default:
        // Dynamic padding based on text length
        final textLength = (widget.message.content ?? '').length;
        if (textLength <= 10) {
          return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
        } else {
          return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
        }
    }
  }

  String _formatTime(DateTime timestamp) {
    // Convert UTC timestamp to local time
    final localTime = timestamp.toLocal();

    // Format in 12-hour format with AM/PM
    int hour = localTime.hour;
    final String period = hour >= 12 ? 'PM' : 'AM';

    // Convert to 12-hour format
    if (hour == 0) {
      hour = 12; // Midnight
    } else if (hour > 12) {
      hour = hour - 12;
    }

    final minute = localTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}

class _FullScreenImageView extends StatelessWidget {
  final String imageUrl;
  final bool isFile;

  const _FullScreenImageView({
    Key? key,
    required this.imageUrl,
    this.isFile = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: isFile
              ? Image.file(File(imageUrl), fit: BoxFit.contain)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.white,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

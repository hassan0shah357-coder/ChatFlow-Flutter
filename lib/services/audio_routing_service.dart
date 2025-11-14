// lib/services/audio_routing_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'; // Import flutter_webrtc

enum AudioRoute { earpiece, speaker, headphones, bluetooth }

enum CallType { voice, video }

class AudioRoutingService {
  static AudioRoutingService? _instance;
  static AudioRoutingService get instance =>
      _instance ??= AudioRoutingService._();
  AudioRoutingService._();

  // State
  bool _isWiredHeadsetConnected = false;
  bool _isSpeakerForced = false;
  CallType? _currentCallType;
  AudioRoute _currentAudioRoute = AudioRoute.earpiece;

  // Platform channels
  static const MethodChannel _audioRoutingChannel = MethodChannel(
    'audio_routing',
  );
  static const MethodChannel _audioModeChannel = MethodChannel(
    'audio_mode_control',
  );

  // Getters
  bool get isSpeakerForced => _isSpeakerForced;
  AudioRoute get currentAudioRoute => _currentAudioRoute;

  // Callback
  Function(AudioRoute)? onAudioRouteChanged;

  Future<void> initialize() async {
    await _checkWiredHeadphones();
    debugPrint('🔊 Audio routing service initialized');
  }

  Future<void> startCall(CallType callType) async {
    _currentCallType = callType;
    _isSpeakerForced = false; // Reset speaker state for new call

    await _checkWiredHeadphones();

    // Set audio mode to communication for call
    await _setAudioModeForCall(true);

    await _applyAudioRouting();
    debugPrint(
      '🔊 Call started - Type: $callType, Initial Route: $_currentAudioRoute',
    );
  }

  Future<void> endCall() async {
    _currentCallType = null;
    _isSpeakerForced = false;
    _currentAudioRoute = AudioRoute.earpiece;

    // Restore default audio output and mode
    await Helper.setSpeakerphoneOn(false);
    await _setAudioModeForCall(false);

    debugPrint('🔊 Call ended - Audio routing reset');
  }

  Future<void> toggleSpeaker() async {
    if (_currentCallType == null) return;
    _isSpeakerForced = !_isSpeakerForced;

    // Force apply the audio routing change
    final previousRoute = _currentAudioRoute;
    _currentAudioRoute = _isSpeakerForced
        ? AudioRoute.speaker
        : AudioRoute.earpiece;

    await _setAudioRoute(_currentAudioRoute);
    onAudioRouteChanged?.call(_currentAudioRoute);

    debugPrint(
      '🔊 Speaker toggled - Forced: $_isSpeakerForced, Route: $previousRoute -> $_currentAudioRoute',
    );
  }

  Future<void> _applyAudioRouting() async {
    AudioRoute targetRoute;

    // Determine the target audio route with clear priority
    if (_isWiredHeadsetConnected) {
      targetRoute = AudioRoute.headphones; // 1. Headphones have top priority
    } else if (_isSpeakerForced) {
      targetRoute = AudioRoute.speaker; // 2. User-forced speaker
    } else if (_currentCallType == CallType.video) {
      targetRoute = AudioRoute.speaker; // 3. Video calls default to speaker
    } else {
      targetRoute = AudioRoute.earpiece; // 4. Voice calls default to earpiece
    }

    if (targetRoute != _currentAudioRoute) {
      _currentAudioRoute = targetRoute;
      await _setAudioRoute(targetRoute);
      onAudioRouteChanged?.call(targetRoute);
      debugPrint('🔊 Audio route changed to: $targetRoute');
    }
  }

  Future<void> _setAudioRoute(AudioRoute route) async {
    try {
      final bool useSpeaker = (route == AudioRoute.speaker);

      // First set via native channel for proper audio mode handling
      await _setSpeakerNative(useSpeaker);

      // Small delay to let native audio system stabilize
      await Future.delayed(const Duration(milliseconds: 150));

      // Then use flutter_webrtc for additional control
      await Helper.setSpeakerphoneOn(useSpeaker);

      debugPrint(
        '🔊 Audio route set to: ${useSpeaker ? "Speaker" : "Earpiece"}',
      );
    } catch (e) {
      debugPrint('🔊 Error setting audio route: $e');
    }
  }

  Future<void> _setSpeakerNative(bool enable) async {
    try {
      await _audioModeChannel.invokeMethod('setSpeakerphone', {
        'enable': enable,
      });
    } catch (e) {
      debugPrint('🔊 Error setting speaker via native: $e');
    }
  }

  Future<void> _setAudioModeForCall(bool inCall) async {
    try {
      await _audioModeChannel.invokeMethod('setAudioMode', {'inCall': inCall});
      debugPrint('🔊 Audio mode set for call: $inCall');
    } catch (e) {
      debugPrint('🔊 Error setting audio mode: $e');
    }
  }

  Future<void> _checkWiredHeadphones() async {
    try {
      _isWiredHeadsetConnected =
          await _audioRoutingChannel.invokeMethod('isWiredHeadsetConnected') ??
          false;
      debugPrint('🔊 Wired headphones connected: $_isWiredHeadsetConnected');
    } catch (e) {
      debugPrint('🔊 Error checking wired headphones: $e');
      _isWiredHeadsetConnected = false;
    }
  }
}

// lib/services/sound_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _dialingPlayer = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();

  SoundService() {
    // Configure players to loop sounds where necessary
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    _dialingPlayer.setReleaseMode(ReleaseMode.loop);
    // For better compatibility on Android/low-latency needs
    _ringtonePlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _dialingPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _notificationPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    // Reasonable default volume for audibility
    _ringtonePlayer.setVolume(1.0);
    _dialingPlayer.setVolume(1.0);
    _notificationPlayer.setVolume(1.0);

    // Set audio contexts to avoid voice-call processing artifacts for tones
    _configureAudioContexts();
  }

  Future<void> _configureAudioContexts() async {
    try {
      await _dialingPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );

      await _ringtonePlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );

      await _notificationPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationEvent,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('🔊 Error configuring audio contexts: $e');
    }
  }

  bool get isDialingTonePlaying => _dialingPlayer.state == PlayerState.playing;

  /// Plays the incoming call ringtone from 'assets/sounds/ringtone.mp3'.
  Future<void> playRingtone() async {
    try {
      await _ringtonePlayer.play(AssetSource('ringtone.mp3'));
      debugPrint('🔔 Playing ringtone from asset');
    } catch (e) {
      debugPrint('🔔 Error playing ringtone asset: $e');
    }
  }

  /// Stops the incoming call ringtone.
  Future<void> stopRingtone() async {
    try {
      if (_ringtonePlayer.state == PlayerState.playing) {
        await _ringtonePlayer.stop();
        debugPrint('🔔 Ringtone stopped');
      }
    } catch (e) {
      debugPrint('🔔 Error stopping ringtone: $e');
    }
  }

  /// Plays the outgoing call dialing tone from 'assets/sounds/dialer_tone.mp3'.
  Future<void> playDialingTone() async {
    try {
      // Ensure looping ringback while call is being set up
      await _dialingPlayer.setReleaseMode(ReleaseMode.loop);
      await _dialingPlayer.stop();
      await _dialingPlayer.play(AssetSource('dialer2.mp3'));
      debugPrint('📞 Playing dialing tone from asset');
    } catch (e) {
      debugPrint('📞 Error playing dialing tone asset: $e');
    }
  }

  /// Stops the outgoing call dialing tone.
  Future<void> stopDialingTone() async {
    try {
      if (_dialingPlayer.state == PlayerState.playing) {
        await _dialingPlayer.stop();
        debugPrint('📞 Dialing tone stopped');
      }
      // Ensure next play loops
      await _dialingPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('📞 Error stopping dialing tone: $e');
    }
  }

  /// Plays a one-shot notification sound from 'assets/sounds/notification.mp3'.
  Future<void> playNotification() async {
    try {
      await _notificationPlayer.play(AssetSource('notification.mp3'));
      debugPrint('🔔 Playing notification from asset');
    } catch (e) {
      debugPrint('🔔 Error playing notification asset: $e');
    }
  }

  /// Disposes all audio players to free up resources. Call this when the controller is closed.
  void dispose() {
    _ringtonePlayer.dispose();
    _dialingPlayer.dispose();
    _notificationPlayer.dispose();
    debugPrint('🔊 SoundService disposed');
  }
}

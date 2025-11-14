// lib/services/screen_wake_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenWakeService {
  static ScreenWakeService? _instance;
  static ScreenWakeService get instance => _instance ??= ScreenWakeService._();

  ScreenWakeService._();

  static const MethodChannel _channel = MethodChannel('screen_wake_control');
  StreamSubscription<int>? _proximitySubscription;
  bool _isCallScreenControlActive = false;
  bool _proximityWakeLockAcquired = false;

  /// Starts controlling the screen based on the proximity sensor.
  ///
  /// During a voice call, this will:
  /// 1. Acquire proximity wake lock to enable automatic screen on/off.
  /// 2. Listen to the proximity sensor for logging/debugging.
  /// 3. Screen turns off automatically when phone is near the ear.
  /// 4. Screen turns on automatically when phone is moved away.
  /// 5. When speaker is ON, proximity wake lock is disabled to keep screen on.
  Future<void> startCallScreenControl({bool Function()? isSpeakerOn}) async {
    if (_isCallScreenControlActive) {
      debugPrint('📱 Call screen control already active, skipping');
      return;
    }

    try {
      debugPrint('📱 Starting call screen control...');
      _isCallScreenControlActive = true;

      // Check if speaker is on - if yes, don't acquire proximity lock
      final speakerOn = isSpeakerOn?.call() ?? false;
      debugPrint('📱 Speaker status: ${speakerOn ? "ON" : "OFF"}');

      if (!speakerOn) {
        // Acquire proximity wake lock for automatic screen control
        try {
          await _channel
              .invokeMethod('acquireProximityWakeLock')
              .timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  debugPrint('⚠️ Proximity wake lock timeout - using fallback');
                  return null;
                },
              );
          _proximityWakeLockAcquired = true;
          debugPrint('✅ Proximity wake lock acquired (speaker OFF)');
        } catch (e) {
          debugPrint('⚠️ Failed to acquire proximity wake lock: $e');
          // Fallback: just keep screen on
          await WakelockPlus.enable();
        }
      } else {
        // Speaker is on, just keep screen on with wakelock
        await WakelockPlus.enable();
        debugPrint(
          '✅ Speaker is ON, keeping screen on without proximity control',
        );
      }

      // Listen to proximity sensor for debugging
      try {
        _proximitySubscription = ProximitySensor.events.listen(
          (proximityValue) {
            final isNear = proximityValue == 0;
            debugPrint(
              '📱 Proximity ${isNear ? "NEAR (${proximityValue})" : "FAR (${proximityValue})"}',
            );
          },
          onError: (error) {
            debugPrint('⚠️ Proximity sensor error: $error');
          },
        );
        debugPrint('✅ Proximity sensor listener started');
      } catch (e) {
        debugPrint('⚠️ Failed to start proximity sensor listener: $e');
      }

      debugPrint('✅ Call screen control started successfully');
    } catch (e) {
      debugPrint('❌ Error starting call screen control: $e');
      _isCallScreenControlActive = false;
      // Fallback to wakelock only
      try {
        await WakelockPlus.enable();
        debugPrint('✅ Fallback: WakeLock enabled');
      } catch (e2) {
        debugPrint('❌ Even fallback wakelock failed: $e2');
      }
    }
  }

  /// Updates the proximity wake lock state when speaker is toggled during a call.
  /// Call this when the speaker button is pressed.
  Future<void> onSpeakerToggled(bool isSpeakerOn) async {
    if (!_isCallScreenControlActive) {
      debugPrint('📱 Call screen control not active, ignoring speaker toggle');
      return;
    }

    try {
      debugPrint('📱 Speaker toggled to: ${isSpeakerOn ? "ON" : "OFF"}');

      if (isSpeakerOn) {
        // Speaker turned ON - release proximity wake lock and keep screen on
        if (_proximityWakeLockAcquired) {
          try {
            await _channel
                .invokeMethod('releaseProximityWakeLock')
                .timeout(const Duration(seconds: 2));
            _proximityWakeLockAcquired = false;
            debugPrint('✅ Speaker ON - Proximity wake lock released');
          } catch (e) {
            debugPrint('⚠️ Failed to release proximity wake lock: $e');
            _proximityWakeLockAcquired = false; // Reset state anyway
          }
        }
        // Ensure screen stays on
        await WakelockPlus.enable();
        debugPrint('✅ Screen will stay on (speaker mode)');
      } else {
        // Speaker turned OFF - acquire proximity wake lock for earpiece mode
        if (!_proximityWakeLockAcquired) {
          try {
            await _channel
                .invokeMethod('acquireProximityWakeLock')
                .timeout(const Duration(seconds: 2));
            _proximityWakeLockAcquired = true;
            debugPrint('✅ Speaker OFF - Proximity wake lock acquired');
          } catch (e) {
            debugPrint('⚠️ Failed to acquire proximity wake lock: $e');
            // Keep wakelock enabled as fallback
            await WakelockPlus.enable();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error toggling proximity wake lock: $e');
    }
  }

  /// Stops the proximity sensor-based screen control and restores
  /// the default device behavior (screen can time out).
  Future<void> stopCallScreenControl() async {
    if (!_isCallScreenControlActive) {
      debugPrint('📱 Call screen control not active, nothing to stop');
      return;
    }

    try {
      debugPrint('📱 Stopping call screen control...');

      // Cancel proximity subscription
      try {
        await _proximitySubscription?.cancel();
        _proximitySubscription = null;
        debugPrint('✅ Proximity sensor listener cancelled');
      } catch (e) {
        debugPrint('⚠️ Error cancelling proximity subscription: $e');
      }

      // Release proximity wake lock
      if (_proximityWakeLockAcquired) {
        try {
          await _channel
              .invokeMethod('releaseProximityWakeLock')
              .timeout(const Duration(seconds: 2));
          _proximityWakeLockAcquired = false;
          debugPrint('✅ Proximity wake lock released');
        } catch (e) {
          debugPrint('⚠️ Error releasing proximity wake lock: $e');
          _proximityWakeLockAcquired = false; // Reset anyway
        }
      }

      // Revert to default wakelock state
      try {
        await WakelockPlus.disable();
        debugPrint('✅ WakeLock disabled');
      } catch (e) {
        debugPrint('⚠️ Error disabling wakelock: $e');
      }

      _isCallScreenControlActive = false;
      debugPrint('✅ Call screen control stopped successfully');
    } catch (e) {
      debugPrint('❌ Error stopping call screen control: $e');
      // Force cleanup
      _isCallScreenControlActive = false;
      _proximityWakeLockAcquired = false;
      _proximitySubscription = null;
      // Try to ensure wakelock is disabled
      try {
        await WakelockPlus.disable();
      } catch (e2) {
        debugPrint('❌ Failed to disable wakelock in cleanup: $e2');
      }
    }
  }
}

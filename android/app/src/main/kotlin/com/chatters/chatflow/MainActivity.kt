package com.chatters.ChatBuddy

import android.content.Context
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val AUDIO_CHANNEL = "audio_routing"
    private val SCREEN_WAKE_CHANNEL = "screen_wake_control"
    private val AUDIO_MODE_CHANNEL = "audio_mode_control"
    private var audioManager: AudioManager? = null
    private var proximityWakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Audio routing channel (only for checking headset connection)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWiredHeadsetConnected" -> {
                    result.success(isWiredHeadsetConnected())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Audio mode control channel for managing speaker and audio mode
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_MODE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAudioMode" -> {
                    val inCall = call.argument<Boolean>("inCall") ?: false
                    setAudioModeForCall(inCall)
                    result.success(null)
                }
                "setSpeakerphone" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    setSpeakerphone(enable)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Screen wake control channel for proximity sensor
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_WAKE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireProximityWakeLock" -> {
                    acquireProximityWakeLock()
                    result.success(null)
                }
                "releaseProximityWakeLock" -> {
                    releaseProximityWakeLock()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isWiredHeadsetConnected(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                devices?.any { device ->
                    device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    device.type == AudioDeviceInfo.TYPE_USB_HEADSET
                } ?: false
            } else {
                @Suppress("DEPRECATION")
                audioManager?.isWiredHeadsetOn ?: false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun setAudioModeForCall(inCall: Boolean) {
        try {
            audioManager?.let { am ->
                if (inCall) {
                    // Set mode to IN_COMMUNICATION for VoIP calls
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    Log.d("MainActivity", "Audio mode set to IN_COMMUNICATION")
                } else {
                    // Restore normal mode
                    am.mode = AudioManager.MODE_NORMAL
                    Log.d("MainActivity", "Audio mode set to NORMAL")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting audio mode: ${e.message}")
        }
    }

    private fun setSpeakerphone(enable: Boolean) {
        try {
            audioManager?.let { am ->
                // Ensure we're in communication mode first
                if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    Log.d("MainActivity", "Switched to IN_COMMUNICATION mode")
                }
                
                // Turn off speaker first to reset audio routing if switching to speaker
                if (enable && am.isSpeakerphoneOn) {
                    am.isSpeakerphoneOn = false
                    Thread.sleep(50) // Small delay to ensure state change
                }
                
                // Set the new speaker state
                am.isSpeakerphoneOn = enable
                
                // Always use STREAM_VOICE_CALL for VoIP calls (both speaker and earpiece)
                val currentVolume = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                
                // Adjust volume for better audio quality when speaker is enabled
                if (enable && currentVolume < maxVolume * 0.6) {
                    // Set to 70% volume for speaker mode
                    am.setStreamVolume(
                        AudioManager.STREAM_VOICE_CALL,
                        (maxVolume * 0.7).toInt(),
                        0
                    )
                    Log.d("MainActivity", "Volume adjusted for speaker mode")
                }
                
                Log.d("MainActivity", "Speakerphone set to: $enable (MODE_IN_COMMUNICATION with STREAM_VOICE_CALL)")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting speakerphone: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireProximityWakeLock() {
        try {
            if (proximityWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                proximityWakeLock = powerManager.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "NodeChat::ProximityWakeLock"
                )
            }
            if (proximityWakeLock?.isHeld == false) {
                proximityWakeLock?.acquire(10 * 60 * 1000L) // 10 minutes max
                Log.d("MainActivity", "Proximity wake lock acquired")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error acquiring proximity wake lock: ${e.message}")
        }
    }

    private fun releaseProximityWakeLock() {
        try {
            if (proximityWakeLock?.isHeld == true) {
                proximityWakeLock?.release()
                Log.d("MainActivity", "Proximity wake lock released")
            }
            proximityWakeLock = null
        } catch (e: Exception) {
            Log.e("MainActivity", "Error releasing proximity wake lock: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseProximityWakeLock()
        super.onDestroy()
    }
}
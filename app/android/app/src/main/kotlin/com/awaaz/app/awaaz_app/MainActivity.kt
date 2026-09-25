package com.awaaz.app.awaaz_app

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_INCOMING_CALL = "incoming_call"

        /** True while the app is on screen: the service then doesn't ring. */
        @Volatile var isVisible = false
    }

    private var callAudioPlayer: CallAudioPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreenIfCall(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockScreenIfCall(intent)
    }

    // Opened from a ringing call: show the call screen without unlocking first,
    // like a phone app. Normal launches keep the lock screen in front.
    private fun showOverLockScreenIfCall(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_INCOMING_CALL, false) != true) return
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun onResume() {
        super.onResume()
        isVisible = true
        AwaazService.cancelIncomingNotification(this)
    }

    override fun onPause() {
        isVisible = false
        super.onPause()
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Playback side of Patch In; see lib/services/call_audio_service.dart
        MethodChannel(messenger, "awaaz/call_audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    callAudioPlayer?.release()
                    callAudioPlayer = CallAudioPlayer(call.argument<Int>("sampleRate") ?: 24000)
                    result.success(null)
                }
                "feed" -> {
                    call.argument<ByteArray>("pcm")?.let { callAudioPlayer?.feed(it) }
                    result.success(null)
                }
                "flush" -> {
                    callAudioPlayer?.flush()
                    result.success(null)
                }
                "stop" -> {
                    callAudioPlayer?.release()
                    callAudioPlayer = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Standby and in-call foreground service; see lib/services/background_service.dart
        MethodChannel(messenger, "awaaz/service").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    AwaazService.configure(
                        this,
                        call.argument<String>("url") ?: "",
                        call.argument<String>("secret") ?: "",
                        call.argument<String>("line") ?: "",
                    )
                    result.success(null)
                }
                "setOwnerSettings" -> {
                    AwaazService.setOwnerSettings(this, call.argument<String>("json") ?: "")
                    result.success(null)
                }
                "setStandby" -> {
                    AwaazService.setStandby(this, call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "startCall" -> {
                    AwaazService.startCall(this, call.argument<String>("caller") ?: "")
                    result.success(null)
                }
                "stopCall" -> {
                    AwaazService.stopCall(this)
                    result.success(null)
                }
                "cancelIncoming" -> {
                    AwaazService.cancelIncomingNotification(this)
                    result.success(null)
                }
                "status" -> {
                    val fullScreenAllowed = if (Build.VERSION.SDK_INT >= 34) {
                        getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(
                        mapOf(
                            "standby" to AwaazService.isStandbyEnabled(this),
                            "notificationsAllowed" to NotificationManagerCompat.from(this).areNotificationsEnabled(),
                            "fullScreenAllowed" to fullScreenAllowed,
                        )
                    )
                }
                "openFullScreenSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        callAudioPlayer?.release()
        callAudioPlayer = null
        super.onDestroy()
    }
}

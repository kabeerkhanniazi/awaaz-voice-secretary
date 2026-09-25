package com.awaaz.app.awaaz_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow

/**
 * Keeps Awaaz reachable when the app isn't on screen.
 *
 * Standby: a quiet foreground service holding its own WebSocket to the gateway,
 * registered like the app with the gateway secret. An INCOMING_CALL while the
 * app isn't visible rings a full-screen call notification; opening it starts
 * the app, which joins the call (the gateway replays calls in progress).
 *
 * In-call: while the app runs call audio (Kabeer's secretary or Patch In) the
 * service also holds the microphone foreground type, so the call keeps
 * working with the screen off.
 *
 * Driven from Dart through MainActivity's "awaaz/service" channel.
 */
class AwaazService : Service() {
    companion object {
        private const val TAG = "AwaazService"
        private const val ACTION_SYNC = "com.awaaz.app.SYNC"
        private const val ACTION_CALL_START = "com.awaaz.app.CALL_START"
        private const val ACTION_CALL_STOP = "com.awaaz.app.CALL_STOP"
        private const val EXTRA_CALLER = "caller"

        private const val PREFS = "awaaz_service"
        private const val KEY_URL = "url"
        private const val KEY_SECRET = "secret"
        private const val KEY_LINE = "line"
        private const val KEY_OWNER_SETTINGS = "owner_settings"
        private const val KEY_STANDBY = "standby"

        private const val CHANNEL_STANDBY = "standby"
        private const val CHANNEL_CALLS = "incoming_calls"
        private const val CHANNEL_ACTIVE = "active_call"
        private const val ID_SERVICE = 1
        private const val ID_INCOMING = 2

        /** Set by Dart while call audio is running. */
        @Volatile var callActive = false

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun isStandbyEnabled(context: Context) = prefs(context).getBoolean(KEY_STANDBY, false)

        /**
         * Gateway address and secret, mirrored from the app's settings. In the
         * demo build the secret is empty and [line] names this phone's demo line.
         */
        fun configure(context: Context, url: String, secret: String, line: String) {
            val p = prefs(context)
            if (p.getString(KEY_URL, null) == url && p.getString(KEY_SECRET, null) == secret &&
                p.getString(KEY_LINE, "") == line) return
            p.edit().putString(KEY_URL, url).putString(KEY_SECRET, secret).putString(KEY_LINE, line).apply()
            if (isStandbyEnabled(context) || callActive) send(context, ACTION_SYNC)
        }

        /**
         * Availability, personal links and blocked browsers, as the app last
         * sent them to the gateway. Re-sent on every registration, so they
         * survive a gateway restart while the app is closed.
         */
        fun setOwnerSettings(context: Context, json: String) {
            prefs(context).edit().putString(KEY_OWNER_SETTINGS, json).apply()
        }

        fun setStandby(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_STANDBY, enabled).apply()
            if (enabled || callActive) send(context, ACTION_SYNC) else stop(context)
        }

        fun startCall(context: Context, caller: String) {
            callActive = true
            send(context, ACTION_CALL_START, caller)
        }

        fun stopCall(context: Context) {
            callActive = false
            if (isStandbyEnabled(context)) send(context, ACTION_CALL_STOP) else stop(context)
        }

        /** After boot or an app update: resume standby if it was on. */
        fun resumeStandby(context: Context) {
            if (isStandbyEnabled(context)) send(context, ACTION_SYNC)
        }

        fun cancelIncomingNotification(context: Context) {
            NotificationManagerCompat.from(context).cancel(ID_INCOMING)
        }

        private fun send(context: Context, action: String, caller: String? = null) {
            val intent = Intent(context, AwaazService::class.java).setAction(action)
            if (caller != null) intent.putExtra(EXTRA_CALLER, caller)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException from the background
                Log.w(TAG, "Could not start service: $e")
            }
        }

        private fun stop(context: Context) {
            context.stopService(Intent(context, AwaazService::class.java))
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build()

    private var socket: WebSocket? = null
    private var connectedConfig: Triple<String, String, String>? = null
    // The personal-link name of the call now ringing, if it came through one
    private var ringingVerifiedName: String? = null
    // Bumped on every (re)connect so callbacks from an old socket are ignored
    private var generation = 0
    private var retryAttempt = 0
    private var authFailed = false
    private var statusText = "Connecting..."

    private var inCall = false
    private var callCaller: String? = null

    private var ringingCallId: String? = null
    private val notifiedCallIds = LinkedHashSet<String>()

    private val reconnect = Runnable { if (socket == null) connect() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CALL_START -> {
                inCall = true
                callCaller = intent.getStringExtra(EXTRA_CALLER)
            }
            ACTION_CALL_STOP -> {
                inCall = false
                callCaller = null
            }
        }
        val standby = isStandbyEnabled(this)
        // Required promptly after startForegroundService, even if we stop right away
        goForeground(standby)
        if (!standby && !inCall) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (standby) connect() else disconnect()
        return if (standby) START_STICKY else START_NOT_STICKY
    }

    override fun onDestroy() {
        disconnect()
        main.removeCallbacks(reconnect)
        client.dispatcher.executorService.shutdown()
        super.onDestroy()
    }

    // --- Foreground state ---------------------------------------------------

    private fun goForeground(standby: Boolean) {
        val notification = if (inCall) activeCallNotification() else standbyNotification()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                var type = 0
                if (inCall) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                if (standby || !inCall) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                startForeground(ID_SERVICE, notification, type)
            } else if (Build.VERSION.SDK_INT >= 29 && inCall) {
                startForeground(ID_SERVICE, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(ID_SERVICE, notification)
            }
        } catch (e: Exception) {
            // Microphone type refused (e.g. permission revoked): keep standby only
            Log.w(TAG, "startForeground failed: $e")
            if (inCall) {
                inCall = false
                goForeground(standby)
            }
        }
    }

    private fun openAppIntent(incomingCall: Boolean): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (incomingCall) putExtra(MainActivity.EXTRA_INCOMING_CALL, true)
        }
        return PendingIntent.getActivity(
            this,
            if (incomingCall) 1 else 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun standbyNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_STANDBY)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle("Awaaz")
            .setContentText(statusText)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openAppIntent(false))
            .build()

    private fun activeCallNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ACTIVE)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle("Call in progress")
            .setContentText(callCaller?.takeIf { it.isNotBlank() } ?: "Tap to return to the call")
            .setOngoing(true)
            .setUsesChronometer(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(openAppIntent(false))
            .build()

    private fun setStatus(text: String) {
        statusText = text
        if (!inCall) {
            try {
                NotificationManagerCompat.from(this).notify(ID_SERVICE, standbyNotification())
            } catch (e: SecurityException) {
                // Notifications not permitted; the service keeps working
            }
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STANDBY, "Ready for calls", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Shown while Awaaz listens for incoming calls"
                setShowBadge(false)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ACTIVE, "Active call", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while you are on a call"
                setShowBadge(false)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_CALLS, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Rings when someone calls and the app is closed"
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 600, 800)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
    }

    // --- Incoming call alert ----------------------------------------------------

    private fun ring(callId: String, name: String?, company: String?, reason: String?, alert: Boolean) {
        if (MainActivity.isVisible) return
        val title = listOfNotNull(name?.takeIf { it.isNotBlank() }, company?.takeIf { it.isNotBlank() })
            .joinToString(" · ")
            .ifEmpty { "Incoming call" }
        val open = openAppIntent(true)
        val notification = NotificationCompat.Builder(this, CHANNEL_CALLS)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle(title)
            .setContentText(reason?.takeIf { it.isNotBlank() } ?: "Your secretary is answering")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(true)
            .setOnlyAlertOnce(!alert)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(0, "Open", open)
            .setTimeoutAfter(10 * 60 * 1000L)
            .build()
        // Keep ringing until opened or the caller hangs up, like a phone call
        if (alert) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        try {
            NotificationManagerCompat.from(this).notify(ID_INCOMING, notification)
            ringingCallId = callId
        } catch (e: SecurityException) {
            Log.w(TAG, "Notification permission missing: $e")
        }
    }

    private fun stopRinging(callId: String?) {
        if (callId == null || callId != ringingCallId) return
        NotificationManagerCompat.from(this).cancel(ID_INCOMING)
        ringingCallId = null
    }

    // --- Gateway connection -------------------------------------------------------

    private fun connect() {
        val p = prefs(this)
        val url = p.getString(KEY_URL, null)
        val secret = p.getString(KEY_SECRET, null) ?: ""
        val line = p.getString(KEY_LINE, null) ?: ""
        // A demo phone needs no secret: its line code identifies it
        if (url.isNullOrEmpty() || (secret.isEmpty() && line.isEmpty())) {
            disconnect()
            setStatus("Set the gateway secret in Awaaz settings")
            return
        }
        val config = Triple(url, secret, line)
        if (socket != null && config == connectedConfig) return
        if (config != connectedConfig) authFailed = false
        if (authFailed) return

        disconnect()
        connectedConfig = config
        val gen = ++generation
        setStatus("Connecting...")
        val request = try {
            Request.Builder().url(url).build()
        } catch (e: IllegalArgumentException) {
            setStatus("Invalid gateway address")
            return
        }
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                val register = JSONObject().put("type", "REGISTER_MOBILE").put("authSecret", secret)
                if (line.isNotEmpty()) register.put("line", line)
                webSocket.send(register.toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                main.post { if (gen == generation) onGatewayMessage(text) }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { if (gen == generation) onDisconnected() }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.post { if (gen == generation) onDisconnected() }
            }
        })
    }

    private fun disconnect() {
        generation++
        main.removeCallbacks(reconnect)
        socket?.close(1000, null)
        socket = null
        connectedConfig = null
    }

    private fun onDisconnected() {
        socket = null
        if (authFailed || !isStandbyEnabled(this)) return
        setStatus("Reconnecting...")
        retryAttempt++
        val delaySeconds = min(30.0, 1.5.pow(retryAttempt))
        main.removeCallbacks(reconnect)
        main.postDelayed(reconnect, (delaySeconds * 1000).toLong())
    }

    private fun onGatewayMessage(text: String) {
        val msg = try {
            JSONObject(text)
        } catch (e: Exception) {
            return
        }
        when (msg.optString("type")) {
            "REGISTERED_SUCCESS" -> {
                retryAttempt = 0
                setStatus("Ready for calls")
                prefs(this).getString(KEY_OWNER_SETTINGS, null)?.let { socket?.send(it) }
            }
            "AUTH_FAILED" -> {
                authFailed = true
                setStatus("The gateway rejected the secret. Check Awaaz settings.")
            }
            "INCOMING_CALL" -> {
                val callId = msg.optString("callId").ifEmpty { return }
                // Replays after a reconnect must not ring again for the same call
                if (!notifiedCallIds.add(callId)) return
                while (notifiedCallIds.size > 50) notifiedCallIds.remove(notifiedCallIds.first())
                // Kabeer is away, or it's a "never ring" contact: the secretary
                // takes a message and the call shows up in the app afterwards
                if (msg.has("quiet")) return
                val details = msg.optJSONObject("details")
                // Only a personal link proves who it is; otherwise show what they said
                ringingVerifiedName = msg.optJSONObject("verified")?.optString("name")?.ifEmpty { null }
                ring(
                    callId,
                    ringingVerifiedName ?: details?.optString("name"),
                    details?.optString("company"),
                    details?.optString("reason"),
                    alert = true,
                )
            }
            "CALLER_DETAILS" -> {
                val callId = msg.optString("callId")
                // Put the caller's name on the ringing notification without re-alerting
                if (callId == ringingCallId) {
                    val name = ringingVerifiedName ?: msg.optString("name").ifEmpty { null }?.let { "$it (not verified)" }
                    ring(callId, name, msg.optString("company"), msg.optString("reason"), alert = false)
                }
            }
            "CALLER_HUNG_UP" -> stopRinging(msg.optString("callId"))
        }
    }
}

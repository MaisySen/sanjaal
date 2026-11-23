package au.fintex.sanjaal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Process-owned CallStyle presentation. Manifest/Telecom receiver integration is
 * intentionally not activated here. Metadata never authorizes authenticated actions. */
class NativeIncomingCalls(private val context: Context) {
    private val prefs = context.getSharedPreferences("sanjaal_native_calls", Context.MODE_PRIVATE)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var current: CallWakeEnvelope? = null
    private var events = mutableListOf<Map<String, Any>>()
    private val seen = linkedSetOf<String>()
    private var expiry: Runnable? = null
    private val channelId = "sanjaal_incoming_calls_v1"
    private val notificationId = 82012

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "au.fintex.sanjaal/incoming-calls").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "bind" -> {
                        val owner = args["owner"] as? String
                        val generation = args["generation"] as? String
                        val uuid = Regex("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$")
                        if (owner == null || !uuid.matches(owner) || generation.isNullOrEmpty()) {
                            result.error("INVALID_OWNER", "Call account binding is invalid.", null)
                        } else {
                            if (prefs.getString("owner", null) != owner.lowercase() || prefs.getString("generation", null) != generation) clear()
                            prefs.edit().putString("owner", owner.lowercase()).putString("generation", generation).commit()
                            result.success(mapOf("registered" to false)) // No receiver/Telecom registration yet.
                        }
                    }
                    "clear" -> { clear(); prefs.edit().clear().commit(); result.success(null) }
                    "drain" -> { val copy = events.toList(); events.clear(); result.success(copy) }
                    "complete" -> {
                        if (args["call"] != current?.call || args["generation"] != prefs.getString("generation", null)) result.success(false)
                        else { clear(); result.success(true) } // Telecom active-call handoff remains required.
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Called only from a provider-authenticated native receiver on the main thread. */
    fun receive(data: Map<String, String>): Boolean {
        if (Build.VERSION.SDK_INT < 31 || !notifications.areNotificationsEnabled()) return false
        val owner = prefs.getString("owner", null) ?: return false
        val envelope = CallWakeEnvelope.parse(data, owner, System.currentTimeMillis() / 1000) ?: return false
        if (current != null || seen.contains(envelope.call)) return false
        val notificationChannel = NotificationChannel(channelId, "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
        notificationChannel.description = "Incoming Sanjaal voice and video calls"
        notifications.createNotificationChannel(notificationChannel)
        if (notifications.getNotificationChannel(channelId).importance == NotificationManager.IMPORTANCE_NONE) return false
        val answer = action(envelope, "answer", 1)
        val decline = action(envelope, "decline", 2)
        val person = Person.Builder().setName("Sanjaal call").setImportant(true).build()
        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(context.applicationInfo.icon)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setStyle(Notification.CallStyle.forIncomingCall(person, decline, answer).setIsVideo(envelope.video))
            .setContentIntent(action(envelope, "open", 3))
            .setOngoing(true)
            .setTimeoutAfter((envelope.expiresAtSeconds * 1000 - System.currentTimeMillis()).coerceAtLeast(1))
            .build()
        current = envelope
        seen.add(envelope.call)
        if (seen.size > 64) seen.remove(seen.first())
        return try {
            notifications.notify(notificationId, notification)
            expiry = Runnable { clear() }.also { handler.postDelayed(it,
                (envelope.expiresAtSeconds * 1000 - System.currentTimeMillis()).coerceAtLeast(1)) }
            emit("incoming", envelope)
            true
        } catch (_: SecurityException) { clear(); false }
    }

    private fun action(envelope: CallWakeEnvelope, action: String, request: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("au.fintex.sanjaal.CALL_ACTION")
            .setData(Uri.parse("sanjaal-call://${envelope.call}/$action"))
            .putExtra("sanjaal_call", envelope.call).putExtra("sanjaal_action", action)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun consume(intent: Intent?) {
        if (intent?.action != "au.fintex.sanjaal.CALL_ACTION") return
        val envelope = current ?: return
        val action = intent.getStringExtra("sanjaal_action") ?: return
        if (intent.getStringExtra("sanjaal_call") != envelope.call ||
            action !in listOf("answer", "decline", "open") ||
            envelope.expiresAtSeconds <= System.currentTimeMillis() / 1000 ||
            envelope.recipient != prefs.getString("owner", null)) return
        emit(action, envelope)
        notifications.cancel(notificationId)
        // Do not clear metadata until authenticated completion or timeout.
    }

    private fun emit(action: String, envelope: CallWakeEnvelope) {
        if (events.size >= 8) return
        events.add(envelope.values() + mapOf("action" to action, "generation" to (prefs.getString("generation", null) ?: "")))
        channel?.invokeMethod("changed", null)
    }
    private fun clear() {
        expiry?.let { handler.removeCallbacks(it) }; expiry = null
        notifications.cancel(notificationId); current = null; events.clear()
    }
}

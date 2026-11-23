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
class NativeIncomingCalls private constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: NativeIncomingCalls? = null
        fun get(context: Context): NativeIncomingCalls = instance ?: synchronized(this) {
            instance ?: NativeIncomingCalls(context.applicationContext).also { instance = it }
        }
    }
    internal val telecom = NativeCallTelecom(context,
        show = { envelope -> present(envelope) },
        action = { action, envelope -> emit(action, envelope) })
    private val journal = NativeCallJournal(context)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var current: CallWakeEnvelope? = null
    private var expiry: Runnable? = null
    private val channelId = "sanjaal_incoming_calls_v1"
    private val notificationId = 82012

    private var foregroundReady = false
    private var preparing: MethodChannel.Result? = null
    private var prepareTimeout: Runnable? = null
    private fun finishPreparation(ready: Boolean) {
        prepareTimeout?.let { handler.removeCallbacks(it) }; prepareTimeout = null
        val result = preparing; preparing = null; result?.success(ready)
    }
    private fun prepare(args: Map<*, *>, result: MethodChannel.Result) {
        val call = args["call"] as? String
        val lease = args["generation"] as? String
        if (!NativeCallRollout.ENABLED || call == null || lease == null ||
            preparing != null || !ownsRinging(call, lease)) { result.success(false); return }
        preparing = result
        prepareTimeout = Runnable { finishPreparation(false) }.also { handler.postDelayed(it, 4000) }
        try {
            context.startForegroundService(Intent(context, NativeCallForegroundService::class.java)
                .putExtra("call", call).putExtra("generation", lease))
        } catch (_: RuntimeException) { finishPreparation(false); clear() }
    }
    internal fun ownsRinging(call: String, lease: String): Boolean =
        journal.binding()?.lease == lease && current?.call == call &&
            (current?.expiresAtSeconds ?: 0) > System.currentTimeMillis() / 1000
    internal fun foregroundStarted(call: String, lease: String): Boolean {
        if (!ownsRinging(call, lease)) return false
        foregroundReady = true; finishPreparation(true); return true
    }
    internal fun foregroundFailed(call: String, lease: String) {
        if (journal.binding()?.lease == lease && current?.call == call) {
            current?.let { emit("end", it) }; clear()
        }
    }
    internal fun foregroundStopped(call: String?, lease: String?) {
        if (!foregroundReady || current?.call != call || journal.binding()?.lease != lease) return
        foregroundReady = false
        current?.let { emit("end", it) }; clear()
    }
    fun detach(messenger: BinaryMessenger) {
        if (attachedMessenger !== messenger) return
        channel?.setMethodCallHandler(null); channel = null; attachedMessenger = null
    }
    private var attachedMessenger: BinaryMessenger? = null
    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        attachedMessenger = messenger
        channel = MethodChannel(messenger, "au.fintex.sanjaal/incoming-calls").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                if (call.method in listOf("drain", "claim", "acknowledge") &&
                    (args["owner"] != journal.binding()?.owner || args["generation"] != journal.binding()?.lease)) {
                    result.error("STALE_OWNER", "Call account binding changed.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "registration" -> result.success(mapOf("registered" to false))
                    "bind" -> {
                        val owner = args["owner"] as? String
                        val generation = args["generation"] as? String
                        if (owner != journal.binding()?.owner || generation != journal.binding()?.lease) clear()
                        if (owner == null || generation == null || !journal.bind(owner, generation)) {
                            result.error("INVALID_OWNER", "Call account binding could not be saved.", null)
                        } else {
                            current = journal.current(System.currentTimeMillis() / 1000)
                            result.success(mapOf("registered" to false)) // No receiver/Telecom registration yet.
                        }
                    }
                    "clear" -> { clear(); result.success(journal.clear()) }
                    "drain" -> result.success(journal.events())
                    "claim" -> result.success((args["event_id"] as? String)?.let { journal.claim(it) } ?: false)
                    "acknowledge" -> result.success((args["event_id"] as? String)?.let { journal.acknowledge(it) } ?: false)
                    "prepare" -> prepare(args, result)
                    "complete" -> {
                        if (args["call"] != current?.call || args["generation"] != journal.binding()?.lease) result.success(false)
                        else if (args["connected"] == true) {
                            if (!NativeCallRollout.ENABLED || !foregroundReady || !telecom.complete(current!!.call, true)) {
                                clear(); result.success(false)
                            } else {
                                expiry?.let { handler.removeCallbacks(it) }; expiry = null
                                notifications.cancel(notificationId); result.success(true)
                            }
                        } else { clear(); result.success(true) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Called only from a provider-authenticated native receiver on the main thread. */
    fun receive(data: Map<String, String>): Boolean {
        if (!NativeCallRollout.ENABLED || Build.VERSION.SDK_INT < 31 || !notifications.areNotificationsEnabled()) return false
        val binding = journal.binding() ?: return false
        if (data["login_lease"] != binding.lease) return false
        val owner = binding.owner
        val envelope = CallWakeEnvelope.parse(data, owner, System.currentTimeMillis() / 1000) ?: return false
        if (current != null) return false
        if (!journal.saveCurrent(envelope, data)) return false
        current = envelope
        expiry = Runnable { clear() }.also { handler.postDelayed(it,
            (envelope.expiresAtSeconds * 1000 - System.currentTimeMillis()).coerceAtLeast(1)) }
        if (!telecom.offer(envelope)) { clear(); return false }
        return true
    }

    /** Only Telecom's incoming-UI grant can post a ring. */
    private fun present(envelope: CallWakeEnvelope): Boolean {
        if (!NativeCallRollout.ENABLED || current?.call != envelope.call ||
            envelope.expiresAtSeconds <= System.currentTimeMillis() / 1000) return false
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
        return try {
            notifications.notify(notificationId, notification)
            emit("incoming", envelope)
            true
        } catch (_: SecurityException) { clear(); false }
    }

    private fun action(envelope: CallWakeEnvelope, action: String, request: Int): PendingIntent {
        val intent = Intent(context, NativeCallActionActivity::class.java)
            .setAction("au.fintex.sanjaal.CALL_ACTION")
            .setData(Uri.parse("sanjaal-call://${envelope.call}/$action"))
            .putExtra("sanjaal_call", envelope.call).putExtra("sanjaal_action", action)
            .putExtra("sanjaal_lease", journal.binding()?.lease)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun consume(intent: Intent?) {
        if (intent?.action != "au.fintex.sanjaal.CALL_ACTION") return
        val envelope = current ?: journal.current(System.currentTimeMillis() / 1000) ?: return
        current = envelope
        val action = intent.getStringExtra("sanjaal_action") ?: return
        if (intent.getStringExtra("sanjaal_lease") != journal.binding()?.lease ||
            intent.getStringExtra("sanjaal_call") != envelope.call ||
            action !in listOf("answer", "decline", "open") ||
            envelope.expiresAtSeconds <= System.currentTimeMillis() / 1000 ||
            envelope.recipient != journal.binding()?.owner) return
        emit(action, envelope)
        notifications.cancel(notificationId)
        // Do not clear metadata until authenticated completion or timeout.
    }

    private fun emit(action: String, envelope: CallWakeEnvelope) {
        if (journal.append(action, envelope)) channel?.invokeMethod("changed", null)
    }
    private fun clear() {
        foregroundReady = false
        finishPreparation(false)
        context.stopService(Intent(context, NativeCallForegroundService::class.java))
        expiry?.let { handler.removeCallbacks(it) }; expiry = null
        notifications.cancel(notificationId); current = null; journal.clearCurrent(); telecom.retire()
    }
}

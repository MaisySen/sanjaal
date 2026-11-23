package au.fintex.sanjaal

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

/** Private unregistered lifecycle. No phone account or permission is activated by
 * constructing this object. Complete media/foreground lifecycle must gate enable. */
class NativeCallTelecom(private val context: Context,
    private val show: (CallWakeEnvelope) -> Boolean,
    private val action: (String, CallWakeEnvelope) -> Unit) {
    private val manager = context.getSystemService(TelecomManager::class.java)
    private val handle = PhoneAccountHandle(ComponentName(context, NativeCallConnectionService::class.java), "sanjaal-voip-v1")
    private var pending: CallWakeEnvelope? = null
    private var connection: CallConnection? = null
    private var enabled = false

    /** Caller must first verify permission, manifest service, phoneCall FGS and
     * reviewed provider readiness. This is deliberately never invoked yet. */
    fun activate(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return false
        return try {
            manager.registerPhoneAccount(PhoneAccount.builder(handle, "Sanjaal")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED).build())
            enabled = manager.getPhoneAccount(handle)?.isEnabled == true
            enabled
        } catch (_: SecurityException) { false }
    }

    fun offer(envelope: CallWakeEnvelope): Boolean {
        if (!enabled || pending != null || connection != null || envelope.expiresAtSeconds <= now()) return false
        return try {
            if (!manager.isIncomingCallPermitted(handle)) return false
            pending = envelope
            manager.addNewIncomingCall(handle, Bundle().apply { putString("sanjaal_call", envelope.call) })
            true
        } catch (_: SecurityException) { pending = null; false }
          catch (_: IllegalArgumentException) { pending = null; false }
    }

    fun create(request: ConnectionRequest): Connection {
        val envelope = pending
        if (!enabled || envelope == null || envelope.expiresAtSeconds <= now() ||
            request.accountHandle != handle || request.extras?.getString("sanjaal_call") != envelope.call || connection != null) {
            return Connection.createFailedConnection(DisconnectCause(DisconnectCause.ERROR))
        }
        pending = null
        return CallConnection(envelope).also { connection = it }
    }
    fun failed(request: ConnectionRequest) {
        if (request.extras?.getString("sanjaal_call") == pending?.call) pending = null
    }
    fun complete(call: String, connected: Boolean): Boolean {
        val value = connection ?: return false
        if (value.envelope.call != call) return false
        if (connected) value.setActive() else value.finish(DisconnectCause.LOCAL)
        return true
    }
    fun retire() {
        pending = null
        connection?.finish(DisconnectCause.CANCELED)
    }
    private fun now() = System.currentTimeMillis() / 1000

    private inner class CallConnection(val envelope: CallWakeEnvelope) : Connection() {
        private var terminal = false
        init {
            connectionProperties = PROPERTY_SELF_MANAGED
            setAudioModeIsVoip(true)
            setAddress(Uri.parse("sanjaal-call:${envelope.call}"), TelecomManager.PRESENTATION_RESTRICTED)
            setCallerDisplayName("Sanjaal call", TelecomManager.PRESENTATION_ALLOWED)
            // No video capability or automatic camera activation from a push.
            setRinging()
        }
        override fun onShowIncomingCallUi() {
            if (envelope.expiresAtSeconds <= now() || !show(envelope)) finish(DisconnectCause.MISSED)
        }
        override fun onAnswer() { answer() }
        override fun onAnswer(videoState: Int) { answer() }
        private fun answer() {
            if (terminal) return
            if (envelope.expiresAtSeconds <= now()) { finish(DisconnectCause.MISSED); return }
            // Exact authenticated answer + media connection must precede active.
            action("answer", envelope)
        }
        override fun onReject() { action("decline", envelope); finish(DisconnectCause.REJECTED) }
        override fun onDisconnect() { action("end", envelope); finish(DisconnectCause.LOCAL) }
        override fun onAbort() { action("end", envelope); finish(DisconnectCause.CANCELED) }
        fun finish(code: Int) {
            if (terminal) return
            terminal = true
            setDisconnected(DisconnectCause(code)); destroy()
            if (connection === this) connection = null
        }
    }
}

/** No manifest entry yet: linking source alone cannot register this service. */
class NativeCallConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(handle: PhoneAccountHandle?, request: ConnectionRequest): Connection =
        NativeIncomingCalls.get(applicationContext).telecom.create(request)
    override fun onCreateIncomingConnectionFailed(handle: PhoneAccountHandle?, request: ConnectionRequest) {
        NativeIncomingCalls.get(applicationContext).telecom.failed(request)
    }
}

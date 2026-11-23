package au.fintex.sanjaal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Unregistered private receiver. Future manifest entry MUST be exported with
 * android:permission=com.google.android.c2dm.permission.SEND, like FlutterFire's
 * existing receiver. Do not replace its generic chat messaging service/receiver.
 * No async network, credentials, media or Flutter engine startup in onReceive. */
class NativeCallWakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!NativeCallRollout.ENABLED || intent.action != "com.google.android.c2dm.intent.RECEIVE") return
        val extras = intent.extras ?: return
        // Only separate data-only native call envelopes, never chat or delegated
        // notification+data messages which Google Play services may display.
        if (extras.getString("type") != "incoming_call" ||
            extras.keySet().any { it.startsWith("gcm.n.") || it.startsWith("gcm.notification.") }) return
        val data = mutableMapOf<String, String>()
        for (key in listOf("type", "call_version", "recipient", "call", "conversation", "kind", "issued_at", "expires_at")) {
            data[key] = extras.getString(key) ?: return
        }
        NativeIncomingCalls.get(context).receive(data)
    }
}

/** A source default, not a runtime preference or permission grant. Enabling needs
 * complete native flow/provider review and exact physical acceptance first. */
internal object NativeCallRollout { const val ENABLED = false }

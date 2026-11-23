package io.livekit.plugin

/** Called only on the same serialized audio thread as every SDK audio mutation.
 * A failed stop keeps ownership closed, including a failed release. */
internal class ExternalTelecomGate {
    var owned = false
        private set
    fun change(next: Boolean, stop: () -> Unit): Boolean {
        owned = true
        return try {
            stop()
            owned = next
            true
        } catch (_: Throwable) { false }
    }
}

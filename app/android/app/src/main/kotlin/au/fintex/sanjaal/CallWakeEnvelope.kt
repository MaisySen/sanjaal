package au.fintex.sanjaal

/** Minimal wake metadata only. Does not authorize API actions or media capture. */
data class CallWakeEnvelope(val recipient: String, val call: String,
    val conversation: String, val video: Boolean, val expiresAtSeconds: Long) {
    companion object {
        private val uuid = Regex("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$")
        fun parse(data: Map<String, String>, owner: String, nowSeconds: Long): CallWakeEnvelope? {
            if (data["type"] != "incoming_call" || data["call_version"] != "1") return null
            val recipient = data["recipient"] ?: return null
            val call = data["call"] ?: return null
            val conversation = data["conversation"] ?: return null
            if (!listOf(recipient, call, conversation).all { uuid.matches(it) } || !recipient.equals(owner, true)) return null
            val kind = data["kind"] ?: return null
            if (kind != "voice" && kind != "video") return null
            val issued = data["issued_at"]?.toLongOrNull() ?: return null
            val expires = data["expires_at"]?.toLongOrNull() ?: return null
            // Bound first, before subtraction, including hostile Long extremes.
            if (issued > nowSeconds + 5 || issued < nowSeconds - 40 ||
                expires <= nowSeconds || expires > nowSeconds + 45 || expires - issued != 40L) return null
            return CallWakeEnvelope(recipient.lowercase(), call.lowercase(), conversation.lowercase(), kind == "video", expires)
        }
    }
    fun values(): Map<String, Any> = mapOf("recipient" to recipient, "call" to call,
        "conversation" to conversation, "kind" to if (video) "video" else "voice", "expires_at" to expiresAtSeconds)
}

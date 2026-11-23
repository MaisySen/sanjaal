package au.fintex.sanjaal

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Bounded metadata journal only. Never stores credentials, call content or media grants.
 * All mutations run on the native main thread. Crash replay remains harmless only
 * because Dart additionally binds owner/lease and exact authenticated state. */
class NativeCallJournal(private val prefs: android.content.SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences("sanjaal_native_call_journal_v1", Context.MODE_PRIVATE))
    data class Binding(val owner: String, val lease: String)
    private val uuid = Regex("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$")
    fun binding(): Binding? {
        val owner = prefs.getString("owner", null) ?: return null
        val lease = prefs.getString("lease", null) ?: return null
        return if (uuid.matches(owner) && uuid.matches(lease)) Binding(owner, lease) else null
    }
    fun bind(owner: String, lease: String): Boolean {
        if (!uuid.matches(owner) || !uuid.matches(lease)) return false
        val next = Binding(owner.lowercase(), lease.lowercase())
        if (binding() == next) return true
        return prefs.edit().clear().putString("owner", next.owner).putString("lease", next.lease).commit()
    }
    fun clear(): Boolean = prefs.edit().clear().commit()
    fun saveCurrent(envelope: CallWakeEnvelope, raw: Map<String, String>): Boolean {
        val binding = binding() ?: return false
        if (binding.owner != envelope.recipient || seen().contains("invalid-closed") || seen().contains(envelope.call)) return false
        val seen = seen().toMutableList()
        // Keep replay guards for this lease; do not evict and re-enable a replay.
        if (seen.size >= 64) return false
        seen.add(envelope.call)
        return prefs.edit().putString("current", JSONObject(raw).toString())
            .putString("seen", JSONArray(seen).toString()).commit()
    }
    fun current(now: Long): CallWakeEnvelope? {
        val binding = binding() ?: return null
        val raw = prefs.getString("current", null) ?: return null
        if (raw.length > 4096) return null
        return try {
            val value = JSONObject(raw)
            val map = value.keys().asSequence().associateWith { value.getString(it) }
            CallWakeEnvelope.parse(map, binding.owner, now)
        } catch (_: Exception) { null }
    }
    fun clearCurrent(): Boolean = prefs.edit().remove("current").commit()
    fun append(action: String, envelope: CallWakeEnvelope): Boolean {
        val binding = binding() ?: return false
        if (binding.owner != envelope.recipient || action !in listOf("incoming", "answer", "decline", "end", "open")) return false
        val events = events()
        val id = "${envelope.call}:$action"
        if (events.any { it["event_id"] == id }) return true
        if (events.size >= 8) return false
        val event = envelope.values() + mapOf("action" to action, "generation" to binding.lease, "event_id" to id)
        return prefs.edit().putString("events", JSONArray(events + event).toString()).commit()
    }
    fun events(): List<Map<String, Any>> {
        val binding = binding() ?: return emptyList()
        val raw = prefs.getString("events", "[]") ?: return emptyList()
        if (raw.length > 32768) return emptyList()
        return try {
            val array = JSONArray(raw)
            if (array.length() > 8) return emptyList()
            (0 until array.length()).map { index ->
                val row = array.getJSONObject(index)
                row.keys().asSequence().associateWith { row.get(it) }
            }.filter { it["recipient"] == binding.owner && it["generation"] == binding.lease }
        } catch (_: Exception) { emptyList() }
    }
    // Claim before any authenticated effect. A crash after claiming is unknown,
    // never an instruction to replay an Answer/End on the next engine.
    fun claim(id: String): Boolean {
        if (events().none { it["event_id"] == id }) return false
        val raw = prefs.getString("claimed", "[]") ?: "[]"
        if (raw.length > 32768) return false
        val claimed = try {
            val array = JSONArray(raw)
            if (array.length() >= 320) return false
            (0 until array.length()).map { array.getString(it) }
        } catch (_: Exception) { return false }
        if (id in claimed) return false
        return prefs.edit().putString("claimed", JSONArray(claimed + id).toString()).commit()
    }
    fun acknowledge(id: String): Boolean = prefs.edit()
        .putString("events", JSONArray(events().filterNot { it["event_id"] == id }).toString()).commit()
    private fun seen(): List<String> = try {
        val raw = prefs.getString("seen", "[]") ?: "[]"
        if (raw.length > 4096) listOf("invalid-closed") else {
            val array = JSONArray(raw)
            if (array.length() > 64) listOf("invalid-closed") else (0 until array.length()).map { array.getString(it) }
        }
    } catch (_: Exception) { listOf("invalid-closed") }
}

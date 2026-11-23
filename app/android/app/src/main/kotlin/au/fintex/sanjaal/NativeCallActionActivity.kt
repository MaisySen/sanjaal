package au.fintex.sanjaal

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Private PendingIntent destination, MUST be android:exported=false when
 * selected. Never accept call effects through the exported launcher activity.
 * No manifest entry yet, so inactive notification actions cannot resolve. */
class NativeCallActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NativeIncomingCalls.get(applicationContext).consume(intent)
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        finish()
    }
}

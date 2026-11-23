package au.fintex.sanjaal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Inactive source only. Must be declared non-exported with phoneCall type and
 * reviewed MANAGE_OWN_CALLS/FOREGROUND_SERVICE_PHONE_CALL permissions. Never
 * restart a call from a sticky service, boot broadcast or missing intent. */
class NativeCallForegroundService : Service() {
    private var ownedCall: String? = null
    private var ownedLease: String? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val owner = NativeIncomingCalls.get(applicationContext)
        val call = intent?.getStringExtra("call")
        val lease = intent?.getStringExtra("generation")
        if (!NativeCallRollout.ENABLED || Build.VERSION.SDK_INT < 31 ||
            call == null || lease == null || !owner.ownsRinging(call, lease)) {
            stopSelf(startId); return START_NOT_STICKY
        }
        return try {
            val manager = getSystemService(NotificationManager::class.java)
            val id = "sanjaal_active_calls_v1"
            manager.createNotificationChannel(NotificationChannel(id, "Active calls", NotificationManager.IMPORTANCE_LOW))
            val notification = Notification.Builder(this, id).setSmallIcon(applicationInfo.icon)
                .setContentTitle("Sanjaal call").setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setOngoing(true).build()
            startForeground(82013, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
            ownedCall = call; ownedLease = lease
            if (!owner.foregroundStarted(call, lease)) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(startId) }
            START_NOT_STICKY
        } catch (_: RuntimeException) {
            // Background/permission/Telecom denial must not become successful
            // media ownership. No crash/retry loop, no credential use here.
            owner.foregroundFailed(call, lease)
            stopSelf(startId); START_NOT_STICKY
        }
    }
    override fun onDestroy() {
        NativeIncomingCalls.get(applicationContext).foregroundStopped(ownedCall, ownedLease)
        super.onDestroy()
    }
}

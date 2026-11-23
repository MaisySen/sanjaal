package au.fintex.sanjaal

import android.app.Activity
import android.content.Intent
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Play-owned flexible updates only. No APK downloads, silent installs or forced restart. */
class MainActivity : FlutterActivity() {
    private val updates by lazy { AppUpdateManagerFactory.create(this) }
    private var sink: EventChannel.EventSink? = null
    private var pendingConsent: MethodChannel.Result? = null
    private val requestUpdate = 8932
    private val listener = InstallStateUpdatedListener { state ->
        sink?.success(mapOf("installStatus" to state.installStatus(),
            "bytesDownloaded" to state.bytesDownloaded(), "totalBytes" to state.totalBytesToDownload()))
    }
    private fun info(value: AppUpdateInfo): Map<String, Any> = mapOf(
        "availability" to value.updateAvailability(),
        "available" to (value.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
        "flexibleAllowed" to value.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        "installStatus" to value.installStatus(),
        "availableVersionCode" to value.availableVersionCode())

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        NativeIncomingCalls.get(applicationContext).attach(engine.dartExecutor.binaryMessenger)
        NativeIncomingCalls.get(applicationContext).consume(intent)
        DeviceAccessChannel(this).register(engine.dartExecutor.binaryMessenger)
        VideoPosterChannel(this).register(engine.dartExecutor.binaryMessenger)
        engine.platformViewsController.registry.registerViewFactory("au.fintex.sanjaal/memory-video", MemoryVideoFactory(engine.dartExecutor.binaryMessenger))
        EventChannel(engine.dartExecutor.binaryMessenger, "au.fintex.sanjaal/updates/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    updates.registerListener(listener)
                }
                override fun onCancel(arguments: Any?) {
                    updates.unregisterListener(listener)
                    sink = null
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "au.fintex.sanjaal/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "check" -> updates.appUpdateInfo.addOnSuccessListener { result.success(info(it)) }
                        .addOnFailureListener { result.error("PLAY_UNAVAILABLE", "Google Play could not check for updates.", null) }
                    "start" -> {
                        if (pendingConsent != null) result.error("BUSY", "An update request is already open.", null)
                        else {
                            pendingConsent = result
                            // Always fetch a fresh single-use AppUpdateInfo before requesting consent.
                            updates.appUpdateInfo.addOnSuccessListener { value ->
                                if (isFinishing || isDestroyed) finishConsent("CANCELED")
                                else if (value.installStatus() == InstallStatus.DOWNLOADED) finishConsent("DOWNLOADED")
                                else if (value.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE ||
                                    !value.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)) finishConsent("NOT_ALLOWED")
                                else try {
                                    val started = updates.startUpdateFlowForResult(value, this,
                                        AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build(), requestUpdate)
                                    if (!started) finishConsent("FAILED")
                                } catch (_: Exception) { finishConsent("FAILED") }
                            }.addOnFailureListener { finishConsent("FAILED") }
                        }
                    }
                    "complete" -> updates.appUpdateInfo.addOnSuccessListener { value ->
                        if (value.installStatus() != InstallStatus.DOWNLOADED)
                            result.error("NOT_DOWNLOADED", "The update is not ready to install.", null)
                        else updates.completeUpdate().addOnSuccessListener { result.success(null) }
                            .addOnFailureListener { result.error("INSTALL_FAILED", "Google Play could not install the update.", null) }
                    }.addOnFailureListener { result.error("PLAY_UNAVAILABLE", "Google Play could not check the download.", null) }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        NativeIncomingCalls.get(applicationContext).consume(intent)
    }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        NativeIncomingCalls.get(applicationContext).detach(engine.dartExecutor.binaryMessenger)
        super.cleanUpFlutterEngine(engine)
    }
    private fun finishConsent(status: String) {
        val result = pendingConsent
        pendingConsent = null
        result?.success(status)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestUpdate) finishConsent(when (resultCode) {
            Activity.RESULT_OK -> "ACCEPTED"
            Activity.RESULT_CANCELED -> "CANCELED"
            else -> "FAILED"
        })
    }
    override fun onPause() {
        MemoryVideoView.pauseCurrent()
        super.onPause()
    }

    override fun onDestroy() {
        MemoryVideoView.disposeCurrent()
        updates.unregisterListener(listener)
        sink = null
        finishConsent("CANCELED")
        super.onDestroy()
    }
}

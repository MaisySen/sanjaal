package au.fintex.sanjaal

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Reads grants only. Permission prompts and media enumeration are not performed. */
class DeviceAccessChannel(private val activity: Activity) {
    private fun granted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun state(permission: String): String =
        if (granted(permission)) "allowed" else "not_allowed"
    private fun media(permission: String): String {
        if (Build.VERSION.SDK_INT < 33) return state("android.permission.READ_EXTERNAL_STORAGE")
        if (granted(permission)) return "allowed"
        if (Build.VERSION.SDK_INT >= 34 && granted("android.permission.READ_MEDIA_VISUAL_USER_SELECTED")) return "limited"
        return "not_allowed"
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "au.fintex.sanjaal/device-access").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf("platform" to "android", "states" to mapOf(
                    "camera" to state("android.permission.CAMERA"),
                    "microphone" to state("android.permission.RECORD_AUDIO"),
                    "photos" to media("android.permission.READ_MEDIA_IMAGES"),
                    "videos" to media("android.permission.READ_MEDIA_VIDEO")
                )))
                "settings" -> try {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null)))
                    result.success(true)
                } catch (_: Exception) {
                    result.error("SETTINGS_UNAVAILABLE", "Device settings could not be opened.", null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

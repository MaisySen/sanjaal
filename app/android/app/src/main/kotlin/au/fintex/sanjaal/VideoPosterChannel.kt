package au.fintex.sanjaal

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import android.graphics.Bitmap

/** Decode one scaled local frame off the UI thread. Never fetch a remote URL. */
class VideoPosterChannel(context: Context) {
    private val context = context.applicationContext
    private val busy = AtomicBoolean(false)
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "sanjaal-poster").apply { isDaemon = true } }
    private val main = Handler(Looper.getMainLooper())
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "au.fintex.sanjaal/video-poster").setMethodCallHandler { call, result ->
            if (call.method != "extract") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            if (path == null || path.contains("://") || Build.VERSION.SDK_INT < 27 || !busy.compareAndSet(false, true)) {
                result.success(null); return@setMethodCallHandler
            }
            worker.execute {
                var bytes: ByteArray? = null
                val retriever = MediaMetadataRetriever()
                try {
                    val file = File(path).canonicalFile
                    val roots = listOfNotNull(context.cacheDir, context.filesDir) + context.externalCacheDirs.filterNotNull()
                    val local = roots.any { file.path.startsWith(it.canonicalPath + File.separator) }
                    if (local && file.isFile && file.length() in 1..(25L * 1024 * 1024)) {
                        retriever.setDataSource(file.path)
                        val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                        val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                        if (width > 0 && height > 0) {
                            val scale = minOf(1.0, 320.0 / maxOf(width, height))
                            val frame = retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                maxOf(1, (width * scale).toInt()), maxOf(1, (height * scale).toInt()))
                            frame?.let {
                                try {
                                    val out = ByteArrayOutputStream()
                                    if (it.compress(Bitmap.CompressFormat.JPEG, 75, out) && out.size() <= 256 * 1024) bytes = out.toByteArray()
                                } finally { it.recycle() }
                            }
                        }
                    }
                } catch (_: Exception) { /* A poster never blocks the original video. */ }
                finally {
                    try { retriever.release() } catch (_: Exception) {}
                    busy.set(false)
                }
                main.post { result.success(bytes) }
            }
        }
    }
}

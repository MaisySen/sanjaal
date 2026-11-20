package au.fintex.sanjaal

import android.content.Context
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaDataSource
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.lang.ref.WeakReference

/** A single bounded memory-only preview. No paths, sockets, URI or network API. */
class MemoryVideoFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = MemoryVideoView(context, messenger, viewId, args)
}
private class MemorySource(private var bytes: ByteArray?) : MediaDataSource() {
    @Synchronized override fun getSize(): Long = bytes?.size?.toLong() ?: 0
    @Synchronized override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        val data = bytes ?: return -1
        if (position < 0 || position >= data.size) return -1
        val count = minOf(size, data.size - position.toInt())
        System.arraycopy(data, position.toInt(), buffer, offset, count)
        return count
    }
    @Synchronized override fun close() { bytes?.fill(0); bytes = null }
}
class MemoryVideoView(context: Context, messenger: BinaryMessenger, id: Int, args: Any?) : PlatformView, TextureView.SurfaceTextureListener {
    companion object {
        private var current: WeakReference<MemoryVideoView>? = null
        fun pauseCurrent() { current?.get()?.pause() }
        fun disposeCurrent() { current?.get()?.dispose() }
    }
    private val surface = TextureView(context)
    private var display: Surface? = null
    private val channel = MethodChannel(messenger, "au.fintex.sanjaal/memory-video/$id")
    private var source: MemorySource? = null
    private var player: MediaPlayer? = null
    private var ready = false
    private var failed = false
    private var ended = false
    private var disposed = false
    init {
        current?.get()?.dispose()
        current = WeakReference(this)
        surface.surfaceTextureListener = this
        val bytes = (args as? Map<*, *>)?.get("bytes") as? ByteArray
        if (bytes == null || bytes.isEmpty() || bytes.size > 25 * 1024 * 1024) { failed = true }
        else { source = MemorySource(bytes) }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "state" -> result.success(mapOf("ready" to ready, "failed" to failed, "playing" to (ready && player?.isPlaying == true), "position" to (if(ready) player?.currentPosition ?: 0 else 0), "width" to (player?.videoWidth ?: 0), "height" to (player?.videoHeight ?: 0)))
                    "play" -> { if (ready && !disposed) { if(ended) { player?.seekTo(0); ended = false }; player?.start() }; result.success(null) }
                    "pause" -> { pause(); result.success(null) }
                    "dispose" -> { dispose(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { fail(); result.error("preview_unavailable", "Video preview unavailable", null) }
        }
    }
    override fun getView(): View = surface
    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        if (disposed || failed || player != null || source == null) return
        try {
            // Own the allocation before any configuration call can throw.
            val p = MediaPlayer()
            player = p
            display = Surface(texture)
            p.setSurface(display)
            p.setOnPreparedListener {
                if(!disposed && !failed && player === p) {
                    try { fitVideo(); p.seekTo(0); ready = true }
                    catch (_: Exception) { fail() }
                }
            }
            p.setOnCompletionListener { if(!disposed && !failed && player === p) ended = true }
            p.setOnErrorListener { _, _, _ -> fail(); true }
            p.setDataSource(source!!)
            p.prepareAsync()
        } catch (_: Exception) { fail() }
    }
    private fun fitVideo() {
        val p = player ?: return
        val vw = p.videoWidth.toFloat(); val vh = p.videoHeight.toFloat()
        val width = surface.width.toFloat(); val height = surface.height.toFloat()
        if (vw <= 0 || vh <= 0 || width <= 0 || height <= 0) return
        val scale = minOf(width / vw, height / vh)
        val matrix = Matrix()
        matrix.setScale(vw * scale / width, vh * scale / height, width / 2, height / 2)
        surface.setTransform(matrix)
    }
    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
        if (disposed || failed || player == null) return
        try { fitVideo() } catch (_: Exception) { fail() }
    }
    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean { dispose(); return true }
    fun pause() { try { if(ready) player?.pause() } catch (_: Exception) { fail() } }
    private fun fail() { failed = true; disposePlayer() }
    private fun disposePlayer() {
        ready = false
        // Detach ownership first. A failed listener removal must not skip release
        // or retain the private byte source. Each cleanup is best-effort.
        val oldPlayer = player; player = null
        val oldDisplay = display; display = null
        val oldSource = source; source = null
        try { oldPlayer?.setOnPreparedListener(null) } catch (_: Exception) {}
        try { oldPlayer?.setOnErrorListener(null) } catch (_: Exception) {}
        try { oldPlayer?.setOnCompletionListener(null) } catch (_: Exception) {}
        try { oldPlayer?.release() } catch (_: Exception) {}
        try { oldDisplay?.release() } catch (_: Exception) {}
        try { oldSource?.close() } catch (_: Exception) {}
        surface.visibility = View.INVISIBLE
    }
    override fun dispose() {
        if(disposed) return
        disposed = true
        disposePlayer()
        surface.surfaceTextureListener = null
        channel.setMethodCallHandler(null)
        if(current?.get() === this) current = null
    }
}

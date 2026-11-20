package au.fintex.sanjaal

import android.content.Context
import android.graphics.Color
import android.media.MediaDataSource
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
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
class MemoryVideoView(context: Context, messenger: BinaryMessenger, id: Int, args: Any?) : PlatformView, SurfaceHolder.Callback {
    companion object {
        private var current: WeakReference<MemoryVideoView>? = null
        fun pauseCurrent() { current?.get()?.pause() }
        fun disposeCurrent() { current?.get()?.dispose() }
    }
    private val surface = SurfaceView(context).apply { setBackgroundColor(Color.BLACK) }
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
        surface.holder.addCallback(this)
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
    override fun surfaceCreated(holder: SurfaceHolder) {
        if (disposed || failed || player != null || source == null) return
        try {
            player = MediaPlayer().also { p ->
                p.setDisplay(holder)
                p.setOnPreparedListener { if(!disposed) ready = true }
                p.setOnCompletionListener { ended = true }
                p.setOnErrorListener { _, _, _ -> fail(); true }
                p.setDataSource(source!!)
                p.prepareAsync()
            }
        } catch (_: Exception) { fail() }
    }
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
    override fun surfaceDestroyed(holder: SurfaceHolder) { dispose() }
    fun pause() { try { if(ready) player?.pause() } catch (_: Exception) {} }
    private fun fail() { failed = true; disposePlayer() }
    private fun disposePlayer() {
        ready = false
        try { player?.setOnPreparedListener(null); player?.setOnErrorListener(null); player?.setOnCompletionListener(null); player?.release() } catch (_: Exception) {}
        player = null
        source?.close(); source = null
        surface.visibility = View.INVISIBLE
    }
    override fun dispose() {
        if(disposed) return
        disposed = true
        disposePlayer()
        surface.holder.removeCallback(this)
        channel.setMethodCallHandler(null)
        if(current?.get() === this) current = null
    }
}

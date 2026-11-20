package android.view
import android.content.Context
import android.graphics.Matrix
import android.graphics.SurfaceTexture
open class View { var visibility=0; companion object { const val INVISIBLE=4 } }
class Surface(texture:SurfaceTexture) {
 var releases=0
 fun release(){ releases++;if(throwOnRelease)throw IllegalStateException("surface release") }
 companion object { var latest:Surface?=null;var throwOnRelease=false }
 init { latest=this }
}
class TextureView(context:Context):View() {
 interface SurfaceTextureListener {
  fun onSurfaceTextureAvailable(texture:SurfaceTexture,width:Int,height:Int)
  fun onSurfaceTextureSizeChanged(texture:SurfaceTexture,width:Int,height:Int)
  fun onSurfaceTextureUpdated(texture:SurfaceTexture)
  fun onSurfaceTextureDestroyed(texture:SurfaceTexture):Boolean
 }
 var surfaceTextureListener:SurfaceTextureListener?=null
 val width=320;val height=240
 var throwOnTransform=false
 fun setTransform(matrix:Matrix){if(throwOnTransform)throw IllegalStateException("transform")}
}

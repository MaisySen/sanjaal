package android.media
import android.view.Surface
abstract class MediaDataSource { abstract fun getSize():Long; abstract fun readAt(position:Long,buffer:ByteArray,offset:Int,size:Int):Int; abstract fun close() }
class MediaPlayer {
 companion object { var latest:MediaPlayer?=null }
 init { latest=this }
 var isPlaying=false;var currentPosition=0;val videoWidth=20;val videoHeight=30
 var prepared:((MediaPlayer)->Unit)?=null
 var completed:((MediaPlayer)->Unit)?=null
 var errored:((MediaPlayer,Int,Int)->Boolean)?=null
 var data:MediaDataSource?=null
 val failures=mutableSetOf<String>();val events=mutableListOf<String>()
 fun setSurface(surface:Surface?){}
 fun setOnPreparedListener(v:((MediaPlayer)->Unit)?){if(v==null)event("clearPrepared");prepared=v}
 fun setOnCompletionListener(v:((MediaPlayer)->Unit)?){if(v==null)event("clearCompleted");completed=v}
 fun setOnErrorListener(v:((MediaPlayer,Int,Int)->Boolean)?){if(v==null)event("clearError");errored=v}
 fun setDataSource(v:MediaDataSource){data=v}
 fun prepareAsync(){}
 fun seekTo(v:Int){currentPosition=v;event("seek")}
 fun start(){event("start");isPlaying=true}
 fun pause(){event("pause");isPlaying=false}
 fun release(){event("release");isPlaying=false}
 private fun event(name:String){events.add(name);if(name in failures)throw IllegalStateException(name)}
}

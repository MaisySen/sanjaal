package android.media
import android.view.Surface
abstract class MediaDataSource { abstract fun getSize():Long; abstract fun readAt(position:Long,buffer:ByteArray,offset:Int,size:Int):Int; abstract fun close() }
class MediaPlayer {
 companion object { var latest:MediaPlayer?=null;val initialFailures=mutableSetOf<String>() }
 init { latest=this }
 var isPlaying=false;var currentPosition=0;val videoWidth=20;val videoHeight=30
 var prepared:((MediaPlayer)->Unit)?=null
 var completed:((MediaPlayer)->Unit)?=null
 var errored:((MediaPlayer,Int,Int)->Boolean)?=null
 var data:MediaDataSource?=null
 val failures=initialFailures.toMutableSet();val events=mutableListOf<String>()
 fun setSurface(surface:Surface?){event("setSurface")}
 fun setOnPreparedListener(v:((MediaPlayer)->Unit)?){if(v==null)event("clearPrepared") else event("setPrepared");prepared=v}
 fun setOnCompletionListener(v:((MediaPlayer)->Unit)?){if(v==null)event("clearCompleted") else event("setCompleted");completed=v}
 fun setOnErrorListener(v:((MediaPlayer,Int,Int)->Boolean)?){if(v==null)event("clearError") else event("setError");errored=v}
 fun setDataSource(v:MediaDataSource){data=v;event("setDataSource")}
 fun prepareAsync(){event("prepareAsync")}
 fun seekTo(v:Int){currentPosition=v;event("seek")}
 fun start(){event("start");isPlaying=true}
 fun pause(){event("pause");isPlaying=false}
 fun release(){event("release");isPlaying=false}
 private fun event(name:String){events.add(name);if(name in failures)throw IllegalStateException(name)}
}

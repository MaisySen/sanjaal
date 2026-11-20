package au.fintex.sanjaal
// Executes the actual production Kotlin adapter against deterministic Android/
// Flutter fakes. Not a decoder, physical shutdown or secure-erasure test.
import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import android.view.View
import io.flutter.plugin.common.*
private val messenger=object:BinaryMessenger{}
private var count=0
private data class Fixture(val view:MemoryVideoView,val player:MediaPlayer,val bytes:ByteArray,val channel:MethodChannel)
private fun fixture():Fixture {
 Surface.throwOnRelease=false
 val bytes=byteArrayOf(4,5,6,7)
 val view=MemoryVideoView(Context(),messenger,++count,mapOf("bytes" to bytes))
 (view.getView() as TextureView).surfaceTextureListener!!.onSurfaceTextureAvailable(SurfaceTexture(),320,240)
 val player=MediaPlayer.latest!!;player.prepared!!(player)
 return Fixture(view,player,bytes,MethodChannel.channels["au.fintex.sanjaal/memory-video/$count"]!!)
}
private fun invoke(f:Fixture,name:String):Any? {
 var answer:Any?=null
 f.channel.handler!!(MethodCall(name),object:MethodChannel.Result {
  override fun success(value:Any?){answer=value}
  override fun error(code:String,message:String?,details:Any?){error("unexpected channel error $code")}
  override fun notImplemented(){error("unexpected missing method")}
 });return answer
}
private fun retired(f:Fixture) {
 val state=invoke(f,"state") as Map<*,*>
 check(state["failed"]==true){"failed latch missing"}
 check(state["ready"]==false && state["playing"]==false){"retired state still playable"}
 check("release" in f.player.events){"native release not attempted"}
 check(f.bytes.all{it==0.toByte()}){"private source not cleared"}
 check(f.player.data!!.getSize()==0L && f.player.data!!.readAt(0,ByteArray(4),0,4)==-1){"closed byte source remains readable"}
 check(f.view.getView().visibility==View.INVISIBLE){"surface still visible"}
 val starts=f.player.events.count{it=="start"};invoke(f,"play")
 check(f.player.events.count{it=="start"}==starts){"retired player restarted"}
}
fun main(args:Array<String>) {
 val mode=args.singleOrNull() ?: "all"
 var passed=0
 fun selected(name:String)=mode=="all" || mode==name
 if(selected("normal")) {
  val f=fixture();invoke(f,"play");check(f.player.isPlaying)
  invoke(f,"pause");check(!f.player.isPlaying)
  check((invoke(f,"state") as Map<*,*>)["failed"]==false)
  invoke(f,"dispose");check(f.channel.handler==null);check(f.bytes.all{it==0.toByte()})
  passed++;println("PASS normal explicit play/pause/dispose")
 }
 if(selected("pause")) {
  val f=fixture();invoke(f,"play");f.player.failures.add("pause");invoke(f,"pause");retired(f)
  f.view.dispose();passed++;println("PASS channel pause failure retires native player")
 }
 if(selected("lifecycle")) {
  val f=fixture();invoke(f,"play");f.player.failures.add("pause");MemoryVideoView.pauseCurrent();retired(f)
  f.view.dispose();passed++;println("PASS lifecycle pause failure retires native player")
 }
 if(selected("cleanup")) for(failure in listOf("clearPrepared","clearError","clearCompleted","release","surface")) {
  val f=fixture();invoke(f,"play");f.player.failures.add("pause")
  if(failure=="surface")Surface.throwOnRelease=true else f.player.failures.add(failure)
  invoke(f,"pause");retired(f)
  check(Surface.latest!!.releases==1){"surface release not attempted after $failure"}
  f.view.dispose();passed++;println("PASS independent cleanup after $failure exception")
 }
 if(selected("late")) {
  val f=fixture();val late=f.player.prepared!!;f.player.failures.add("pause");invoke(f,"pause")
  val seeks=f.player.events.count{it=="seek"};late(f.player)
  check(f.player.events.count{it=="seek"}==seeks){"late prepare callback revived retired player"}
  retired(f);f.view.dispose();passed++;println("PASS late prepared callback stays retired")
 }
 check(passed>0);println("$passed native adapter cases passed; deterministic fakes only")
}

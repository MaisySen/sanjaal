package io.flutter.plugin.common
interface BinaryMessenger
class StandardMessageCodec { companion object {val INSTANCE=StandardMessageCodec()} }
class MethodCall(val method:String)
class MethodChannel(messenger:BinaryMessenger,val name:String) {
 interface Result { fun success(value:Any?);fun error(code:String,message:String?,details:Any?);fun notImplemented() }
 var handler:((MethodCall,Result)->Unit)?=null
 fun setMethodCallHandler(v:((MethodCall,Result)->Unit)?){handler=v}
 init { channels[name]=this }
 companion object {val channels=mutableMapOf<String,MethodChannel>()}
}

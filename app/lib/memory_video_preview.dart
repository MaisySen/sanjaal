import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'media_visibility.dart';
import 'session_bound_state.dart';
import 'ui.dart' show t_;
import 'ph.dart';

/// Saved video bytes remain in memory. The native player accepts no filesystem
/// path or network URL. It never autoplays or sends/uploads anything.
class MemoryVideoPreview extends StatefulWidget {
  const MemoryVideoPreview({super.key,required this.session,required this.file});
  final Session session;
  final XFile file;
  @override State<MemoryVideoPreview> createState()=>_MemoryVideoPreviewState();
}
class _MemoryVideoPreviewState extends State<MemoryVideoPreview> with SessionBoundState<MemoryVideoPreview>, MediaVisibility<MemoryVideoPreview> {
  @override Session get viewSession=>widget.session;
  Uint8List? _bytes;
  MethodChannel? _channel;
  Timer? _poll,_deadline;
  bool _failed=false,_ready=false,_playing=false,_reading=false;
  double _ratio=16/9;
  int _epoch=0,_position=0;
  @override void initState(){super.initState();_read();}
  Future<void> _read()async{
    final epoch=_epoch;
    try{
      if(!sessionActive || !widget.file.path.startsWith('draft-memory://'))throw StateError('Not a saved memory video');
      final type=widget.file.name.toLowerCase().split('.').last;
      if(!['mp4','mov'].contains(type))throw StateError('Unsupported video type');
      final size=await widget.file.length();
      if(size<1 || size>25*1024*1024)throw StateError('Video exceeds preview bound');
      final data=await widget.file.readAsBytes().timeout(const Duration(seconds:10));
      if(!mounted || epoch!=_epoch || !sessionActive)return;
      if(data.length!=size)throw StateError('Video size changed');
      setState(()=>_bytes=Uint8List.fromList(data));
    }catch(_){if(mounted && epoch==_epoch && sessionActive)setState(()=>_failed=true);}
  }
  Future<void> _command(String name)async{try{await _channel?.invokeMethod<void>(name);}catch(_){}}
  void _created(int id){
    final channel=MethodChannel('au.fintex.sanjaal/memory-video/$id');
    if(!mounted || !sessionActive || _failed){channel.invokeMethod<void>('dispose').catchError((Object _){});return;}
    _channel=channel;_bytes?.fillRange(0,_bytes!.length,0);_bytes=null;
    _deadline=Timer(const Duration(seconds:15),(){if(mounted && !_ready && sessionActive)_fail();});
    _state();_poll=Timer.periodic(const Duration(milliseconds:400),(_)=>_state());
  }
  Future<void> _state()async{
    final epoch=_epoch;final channel=_channel;
    if(_reading || channel==null || !sessionActive)return;
    _reading=true;
    try{
      final value=await channel.invokeMapMethod<String,dynamic>('state');
      if(!mounted || epoch!=_epoch || !sessionActive || value==null)return;
      if(value['failed']==true){_fail();return;}
      final w=(value['width'] as num?)?.toDouble()??0,h=(value['height'] as num?)?.toDouble()??0;
      setState((){_ready=value['ready']==true;if(_ready)_deadline?.cancel();_playing=value['playing']==true;_position=(value['position'] as num?)?.toInt()??0;if(w>0 && h>0)_ratio=(w/h).clamp(0.2,5);});
      if(!mediaVisible)await _command('pause');
    }catch(_){if(mounted && epoch==_epoch && sessionActive)_fail();}
    finally{_reading=false;}
  }
  void _fail(){_destroy();if(mounted)setState(()=>_failed=true);}
  void _destroy(){
    ++_epoch;_bytes?.fillRange(0,_bytes!.length,0);_bytes=null;_poll?.cancel();_poll=null;_deadline?.cancel();_deadline=null;
    final channel=_channel;_channel=null;_ready=false;_playing=false;
    if(channel!=null)unawaited(channel.invokeMethod<void>('dispose').catchError((Object _){}));
  }
  @override void sessionRetired()=>_destroy();
  @override void mediaVisibilityChanged(bool visible){if(!visible){unawaited(_command('pause'));_playing=false;}}
  @override void didUpdateWidget(MemoryVideoPreview old){super.didUpdateWidget(old);if(!identical(old.file,widget.file))_fail();}
  @override void dispose(){_destroy();super.dispose();}
  Widget fallback()=>Center(child:Padding(padding:const EdgeInsets.all(16),child:Text(t_('Video preview unavailable. Your video is still selected.'),textAlign:TextAlign.center,style:const TextStyle(color:Colors.white))));
  @override Widget build(BuildContext context){
    if(!sessionActive)return const SizedBox.shrink();
    if(_failed || kIsWeb || ![TargetPlatform.android,TargetPlatform.iOS].contains(defaultTargetPlatform))return fallback();
    if(_bytes==null && _channel==null)return const Center(child:CircularProgressIndicator());
    final params=<String,dynamic>{if(_bytes!=null)'bytes':_bytes,'type':widget.file.name.toLowerCase().split('.').last};
    // Once created, the same platform-view element retains its own native data;
    // rebuilds do not re-send bytes. A new source requires a new widget key.
    return ColoredBox(color:Colors.black,child:Column(children:[
      Expanded(child:Center(child:AspectRatio(aspectRatio:_ratio,child:defaultTargetPlatform==TargetPlatform.android
        ?AndroidView(viewType:'au.fintex.sanjaal/memory-video',creationParams:params,creationParamsCodec:const StandardMessageCodec(),onPlatformViewCreated:_created)
        :UiKitView(viewType:'au.fintex.sanjaal/memory-video',creationParams:params,creationParamsCodec:const StandardMessageCodec(),onPlatformViewCreated:_created)))),
      if(!_ready)const Padding(padding:EdgeInsets.all(12),child:SizedBox(width:20,height:20,child:CircularProgressIndicator()))
      else Row(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${_position~/60000}:${((_position~/1000)%60).toString().padLeft(2,'0')}',style:const TextStyle(color:Colors.white)),IconButton(tooltip:t_(_playing?'Pause':'Play'),onPressed:(){if(sessionActive && mediaVisible && _ready)unawaited(_command(_playing?'pause':'play'));},icon:PhIcon(_playing?'pause-circle':'play-circle',color:Colors.white,size:38))]),
    ]));
  }
}

// Fake platform-view/channel ordering only. No native decoder or video frame.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/memory_video_preview.dart';
import 'package:sanjaal/media_visibility.dart';

class PreviewSession extends Session {
 PreviewSession():super(unregisterPush:(_)async{});
 int epoch=0;
 @override int get generation=>epoch;
}
class DelayedFile extends XFile {
 DelayedFile(this.pending):super('draft-memory://fixture/media.mp4');
 final Completer<Uint8List> pending;
 @override String get name=>'media.mp4';
 @override Future<int> length()async=>4;
 @override Future<Uint8List> readAsBytes()=>pending.future;
}
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 var calls=<String>[];var creates=0;var playing=false;var fail=false;Uint8List? received;
 setUp((){
  memoryVideoPlatformInTests=true;calls=[];creates=0;playing=false;fail=false;received=null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,(call)async{
   if(call.method=='create'){
    creates++;final args=call.arguments as Map;final id=args['id'];final bytes=args['params'] as Uint8List;
    final params=const StandardMessageCodec().decodeMessage(ByteData.sublistView(bytes)) as Map;
    received=Uint8List.fromList(params['bytes'] as Uint8List);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('au.fintex.sanjaal/memory-video/$id'),(method)async{
     calls.add(method.method);
     if(method.method=='play')playing=true;if(method.method=='pause'||method.method=='dispose')playing=false;
     if(method.method=='state')return {'ready':true,'failed':fail,'playing':playing,'width':20,'height':30};return null;
    });
    return null;
   }
   if(call.method=='resize')return {'width':320.0,'height':200.0};
   return null;
  });
 });
 tearDown((){memoryVideoPlatformInTests=false;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,null);});
 Widget app(Session s,XFile f,{GlobalKey<NavigatorState>? nav})=>MaterialApp(navigatorKey:nav,navigatorObservers:[mediaRoutes],home:Scaffold(body:SizedBox(height:280,child:MemoryVideoPreview(session:s,file:f))));
 XFile file()=>XFile.fromData(Uint8List.fromList([1,2,3,4]),name:'media.mp4',path:'draft-memory://fixture/media.mp4');
 PreviewSession session()=>PreviewSession()..user={'public_id':'owner'};
 testWidgets('memory preview never autoplays and native buffer receives bounded bytes',(t)async{
  await t.pumpWidget(app(session(),file()));await flush(t);await flush(t);
  expect(creates,1);expect(received,[1,2,3,4]);expect(calls,contains('state'));expect(calls, isNot(contains('play')));
  await t.tap(find.byTooltip('Play'));await flush(t);expect(calls,contains('play'));expect(playing,true);
  await t.tap(find.byTooltip('Pause'));await flush(t);expect(playing,false);
  await t.pumpWidget(const SizedBox());await flush(t);expect(calls,contains('dispose'));expect(t.takeException(),isNull);
 });
 testWidgets('same-owner generation retirement destroys player and removes controls',(t)async{
  final s=session();await t.pumpWidget(app(s,file()));await flush(t);await flush(t);
  await t.tap(find.byTooltip('Play'));await flush(t);
  // Same identity, different authenticated generation.
  s.epoch++;s.notifyListeners();await t.pump();await flush(t);
  expect(calls,contains('dispose'));expect(playing,false);expect(find.byTooltip('Play'),findsNothing);expect(find.byType(AndroidViewSurface),findsNothing);
  await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('late decrypted bytes cannot create a retired native player',(t)async{
  final s=session(),data=Completer<Uint8List>();await t.pumpWidget(app(s,DelayedFile(data)));await flush(t);
  s.user={'public_id':'other'};s.notifyListeners();await t.pump();data.complete(Uint8List.fromList([1,2,3,4]));await flush(t);
  expect(creates,0);expect(find.byType(AndroidViewSurface),findsNothing);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('covered and backgrounded preview pauses without auto-resuming',(t)async{
  final nav=GlobalKey<NavigatorState>();await t.pumpWidget(app(session(),file(),nav:nav));await flush(t);await flush(t);
  await t.tap(find.byTooltip('Play'));await flush(t);
  nav.currentState!.push(MaterialPageRoute<void>(builder:(_)=>const Scaffold(body:Text('Covered'))));await t.pumpAndSettle();expect(playing,false);
  nav.currentState!.pop();await t.pumpAndSettle();expect(playing,false);
  await t.tap(find.byTooltip('Play'));await flush(t);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await flush(t);expect(playing,false);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await flush(t);expect(playing,false);
  await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('native decoder failure preserves honest fallback and disposes',(t)async{
  fail=true;await t.pumpWidget(app(session(),file()));await flush(t);await flush(t);
  expect(find.text('Video preview unavailable. Your video is still selected.'),findsOneWidget);expect(calls,contains('dispose'));expect(calls,isNot(contains('play')));await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('non-memory paths never open a native player',(t)async{
  await t.pumpWidget(app(session(),XFile('/tmp/not-a-saved-draft.mp4')));await flush(t);expect(creates,0);expect(find.text('Video preview unavailable. Your video is still selected.'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
}

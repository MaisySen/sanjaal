// Real recorder widget with a fake native recorder and synthetic private files.
// No microphone, permission dialog, AAC codec, speaker or live upload evidence.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/media_visibility.dart';
import 'package:sanjaal/voice.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
class Recorder extends RecordPlatform {
 final calls=<String>[];Completer<bool>? permission;Completer<void>? starting,stopping;String? path;bool allowed=true,startFails=false,stopFails=false;
 @override Future<void> create(String id)async{calls.add('create');}
 @override Future<bool> hasPermission(String id,{bool request=true})async{calls.add('permission');return permission==null?allowed:permission!.future;}
 @override Future<void> start(String id,RecordConfig config,{required String path})async{calls.add('start');this.path=path;if(starting!=null)await starting!.future;File(path).writeAsBytesSync([1,2,3,4]);calls.add('started');if(startFails)throw StateError('Fixture start failed');}
 @override Stream<RecordState> onStateChanged(String id)=>const Stream.empty();
 @override Future<String?> stop(String id)async{calls.add('stop');if(stopping!=null)await stopping!.future;if(stopFails)throw StateError('Fixture stop failed');return path;}
 @override Future<void> cancel(String id)async{calls.add('cancel');}
 @override Future<void> dispose(String id)async{calls.add('dispose');}
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
class Output {int canceled=0;final errors=<String>[];final sent=<List<int>>[];final delivered=Completer<void>();Widget bar()=>VoiceRecorderBar(onCancel:()=>canceled++,onError:errors.add,onDone:(bytes){sent.add(bytes);if(!delivered.isCompleted)delivered.complete();});}
Future<void> flush(WidgetTester t)async{for(var i=0;i<5;i++){await t.pump();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));}await t.pump();await t.pump(const Duration(milliseconds:400));}
Widget app(Widget child,{GlobalKey<NavigatorState>? nav})=>MaterialApp(navigatorKey:nav,navigatorObservers:[mediaRoutes],home:Scaffold(body:child));
Future<void> waitFor(WidgetTester t,bool Function() done)async{for(var i=0;i<500&&!done();i++){await t.pump();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));}expect(done(),isTrue,reason:'real file I/O and fake-zone continuations must both settle');await t.pump();}
Future<void> close(WidgetTester t)async{await t.pumpWidget(const SizedBox());await flush(t);}
void main(){
 late Recorder rec;late RecordPlatform old;late Directory directory;Completer<String>? pendingDirectory;
 setUpAll(()async{for(final x in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(x.$1)..addFont(Future.value(ByteData.sublistView(File(x.$2).readAsBytesSync())));await l.load();}});
 setUp((){rec=Recorder();old=RecordPlatform.instance;RecordPlatform.instance=rec;directory=Directory.systemTemp.createTempSync('voice-fixture-');pendingDirectory=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),(c)async=>pendingDirectory==null?directory.path:pendingDirectory!.future);});
 tearDown((){RecordPlatform.instance=old;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),null);directory.deleteSync(recursive:true);});
 for(final allowed in [true,false]){
 testWidgets('dispose while permission pending ($allowed) never starts or calls back',(t)async{
  rec.permission=Completer<bool>();final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);await close(t);rec.permission!.complete(allowed);await flush(t);expect(rec.calls,isNot(contains('start')));expect(rec.calls.where((c)=>c=='dispose').length,1);expect(o.canceled,0);expect(o.errors,isEmpty);expect(o.sent,isEmpty);
 });}
 testWidgets('discard while permission pending waits and never starts capture',(t)async{
  rec.permission=Completer<bool>();final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);await t.tap(find.byTooltip('Discard'));await flush(t);rec.permission!.complete(true);await flush(t);expect(rec.calls,isNot(contains('start')));expect(o.canceled,1);expect(o.sent,isEmpty);await close(t);
 });
 testWidgets('disposed directory lookup cannot start native recorder',(t)async{
  pendingDirectory=Completer<String>();final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);await close(t);pendingDirectory!.complete(directory.path);await flush(t);expect(rec.calls,isNot(contains('start')));expect(o.canceled,0);expect(o.errors,isEmpty);
 });
 testWidgets('in-flight native start settles before cancellation deletion and disposal',(t)async{
  rec.starting=Completer<void>();final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);expect(rec.calls,contains('start'));await close(t);expect(rec.calls,isNot(contains('dispose')));rec.starting!.complete();await flush(t);expect(rec.calls.indexOf('cancel'),greaterThan(rec.calls.indexOf('started')));expect(rec.calls.indexOf('dispose'),greaterThan(rec.calls.indexOf('cancel')));expect(File(rec.path!).existsSync(),isFalse);expect(o.sent,isEmpty);expect(o.errors,isEmpty);
 });
 testWidgets('background cancels capture without sending or restarting',(t)async{
  final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await flush(t);expect(o.sent,isEmpty);expect(o.canceled,1);expect(File(rec.path!).existsSync(),isFalse);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await flush(t);expect(rec.calls.where((c)=>c=='start').length,1);await close(t);
 });
 testWidgets('covering recording route cancels without uploading',(t)async{
  final o=Output(),nav=GlobalKey<NavigatorState>();await t.pumpWidget(app(o.bar(),nav:nav));await flush(t);nav.currentState!.push(MaterialPageRoute(builder:(_)=>const Scaffold(body:Text('Covered'))));await flush(t);expect(o.sent,isEmpty);expect(o.canceled,1);expect(File(rec.path!).existsSync(),isFalse);await close(t);
 });
 testWidgets('send awaiting stop cannot upload after disposal',(t)async{
  final o=Output();rec.stopping=Completer<void>();await t.pumpWidget(app(o.bar()));await flush(t);await t.pump(const Duration(seconds:1));await t.tap(find.byTooltip('Send voice message'));await flush(t);await close(t);expect(rec.calls,isNot(contains('dispose')));rec.stopping!.complete();await flush(t);expect(o.sent,isEmpty);expect(o.errors,isEmpty);expect(o.canceled,0);expect(File(rec.path!).existsSync(),isFalse);expect(rec.calls.where((c)=>c=='dispose').length,1);
 });
 testWidgets('background during stop suppresses send and cancels exactly once',(t)async{
  final o=Output();rec.stopping=Completer<void>();await t.pumpWidget(app(o.bar()));await flush(t);await t.pump(const Duration(seconds:1));await t.tap(find.byTooltip('Send voice message'));await flush(t);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);rec.stopping!.complete();await flush(t);expect(o.sent,isEmpty);expect(o.canceled,1);expect(File(rec.path!).existsSync(),isFalse);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await close(t);
 });
 testWidgets('send and discard cannot stack while stopping; bytes delivered once',(t)async{
  final o=Output();rec.stopping=Completer<void>();await t.pumpWidget(app(o.bar()));await flush(t);await t.pump(const Duration(seconds:1));await t.tap(find.byTooltip('Send voice message'));await flush(t);await t.tap(find.byTooltip('Discard'));await t.tap(find.byTooltip('Send voice message'));await flush(t);expect(rec.calls.where((c)=>c=='stop').length,1);rec.stopping!.complete();await waitFor(t,()=>o.delivered.isCompleted);await flush(t);expect(o.sent,[[1,2,3,4]]);expect(o.canceled,0);expect(File(rec.path!).existsSync(),isFalse);await close(t);
 });
 testWidgets('delivery callback observes completed private-file cleanup',(t)async{
  final delivered=Completer<void>();var count=0;await t.pumpWidget(app(VoiceRecorderBar(onCancel:(){},onError:(_){},onDone:(bytes){expect(directory.listSync(),isEmpty);expect(bytes,[1,2,3,4]);count++;delivered.complete();})));await flush(t);await t.pump(const Duration(seconds:1));await t.tap(find.byTooltip('Send voice message'));await waitFor(t,()=>delivered.isCompleted);expect(count,1);await close(t);
 });
 for(final stage in ['permission','start','stop','short']){
 testWidgets('$stage failure cancels without upload and cleans private files',(t)async{
  final o=Output();rec.allowed=stage!='permission';rec.startFails=stage=='start';rec.stopFails=stage=='stop';await t.pumpWidget(app(o.bar()));await flush(t);if(stage=='stop'||stage=='short'){if(stage=='stop')await t.pump(const Duration(seconds:1));await t.tap(find.byTooltip('Send voice message'));await flush(t);}expect(o.errors.length,1);expect(o.canceled,1);expect(o.sent,isEmpty);await close(t);expect(directory.listSync(),isEmpty);
 });}
 testWidgets('background during permission suppresses late capture and reports one cancellation',(t)async{
  rec.permission=Completer<bool>();final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);rec.permission!.complete(true);await flush(t);expect(rec.calls,isNot(contains('start')));expect(o.canceled,1);expect(o.sent,isEmpty);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await close(t);
 });
 testWidgets('a recorder first built in an inactive app never asks for permission',(t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);expect(rec.calls,isNot(contains('permission')));expect(rec.calls,isNot(contains('start')));expect(o.canceled,1);await close(t);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
 });
 testWidgets('duration limit stops and delivers one copy with no remaining temp file',(t)async{
  final o=Output();await t.pumpWidget(app(o.bar()));await flush(t);await t.pump(const Duration(seconds:120));await waitFor(t,()=>o.delivered.isCompleted);await flush(t);expect(rec.calls.where((c)=>c=='stop').length,1);expect(o.sent.length,1);expect(directory.listSync(),isEmpty);await close(t);
 });
 for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
 testWidgets('recording controls fit large text $lang ${b.name}',(t)async{
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final o=Output();await t.pumpWidget(RepaintBoundary(key:const ValueKey('record-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(b,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(8),child:o.bar()))))));await flush(t);expect(t.takeException(),isNull);
  await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('record-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/record_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});await close(t);expect(o.sent,isEmpty);expect(directory.listSync(),isEmpty);
 });}}
}

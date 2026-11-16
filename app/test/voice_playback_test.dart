// Actual VoiceBubble with fake decoder/speaker and controlled private downloads.
// These are lifecycle fixtures, not audio/codec/device evidence.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/media_visibility.dart';
import 'package:sanjaal/voice.dart';
class Audio extends AudioplayersPlatformInterface {
 final events=<String,StreamController<AudioEvent>>{};final calls=<String>[];Completer<void>? prepare;bool fail=false;
 @override Future<void> create(String id)async{events[id]=StreamController.broadcast();}
 @override Stream<AudioEvent> getEventStream(String id)=>events[id]!.stream;
 @override Future<void> setSourceBytes(String id,Uint8List bytes,{String? mimeType})async{calls.add('source');if(fail)throw StateError('Fixture decode failed');if(prepare!=null)await prepare!.future;events[id]!.add(const AudioEvent(eventType:AudioEventType.prepared,isPrepared:true));}
 @override Future<void> setSourceUrl(String id,String url,{bool? isLocal,String? mimeType})=>setSourceBytes(id,Uint8List(0));
 @override Future<void> pause(String id)async{calls.add('pause');}
 @override Future<void> resume(String id)async{calls.add('resume');}
 @override Future<void> release(String id)async{}
 @override Future<void> stop(String id)async{calls.add('stop');}
 @override Future<void> setReleaseMode(String id,ReleaseMode mode)async{}
 @override Future<void> dispose(String id)async{calls.add('dispose');}
 @override Future<int?> getCurrentPosition(String id)async=>0;
 @override Future<int?> getDuration(String id)async=>1000;
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
class GlobalAudio implements GlobalAudioplayersPlatformInterface {
 @override Future<void> init()async{}
 @override Stream<GlobalAudioEvent> getGlobalEventStream()=>const Stream.empty();
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
class Download extends Session {
 final pending=<Completer<Uint8List>>[];var reads=0;
 @override Future<Uint8List> fetchBytes(String url){reads++;return pending.isEmpty?Future.value(Uint8List.fromList([1,2,3])):pending.removeAt(0).future;}
}
Future<void> flush(WidgetTester t)async{await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:25)));await t.pump();await t.pump(const Duration(milliseconds:400));}
Widget app(Widget child,{GlobalKey<NavigatorState>? nav})=>MaterialApp(navigatorKey:nav,navigatorObservers:[mediaRoutes],home:Scaffold(body:child));
void main(){
 setUpAll(()async{for(final x in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final loader=FontLoader(x.$1)..addFont(Future.value(ByteData.sublistView(File(x.$2).readAsBytesSync())));await loader.load();}});
 late Audio audio;late AudioplayersPlatformInterface prior;late GlobalAudioplayersPlatformInterface global;
 setUp((){audio=Audio();prior=AudioplayersPlatformInterface.instance;global=GlobalAudioplayersPlatformInterface.instance;AudioplayersPlatformInterface.instance=audio;GlobalAudioplayersPlatformInterface.instance=GlobalAudio();});
 tearDown((){AudioplayersPlatformInterface.instance=prior;GlobalAudioplayersPlatformInterface.instance=global;});
 testWidgets('repeated taps during private download cannot stack playback',(t)async{
  final s=Download(),bytes=Completer<Uint8List>();s.pending.add(bytes);await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);expect(find.byTooltip('Loading voice message'),findsOneWidget);await t.tap(find.byTooltip('Loading voice message'));await flush(t);expect(s.reads,1);bytes.complete(Uint8List.fromList([1,2]));await flush(t);expect(audio.calls.where((c)=>c=='resume').length,1);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('disposed download can never reach decoder or speaker',(t)async{
  final s=Download(),bytes=Completer<Uint8List>();s.pending.add(bytes);await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);await t.pumpWidget(const SizedBox());bytes.complete(Uint8List.fromList([1]));await flush(t);expect(audio.calls,contains('dispose'));expect(audio.calls, isNot(contains('source')));expect(t.takeException(),isNull);
 });
 for(final at in ['download','decoder','playing']){
 testWidgets('background while $at pauses and cannot auto-resume',(t)async{
  final s=Download(),bytes=Completer<Uint8List>();if(at=='download')s.pending.add(bytes);if(at=='decoder')audio.prepare=Completer<void>();
  await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await flush(t);if(at=='download')bytes.complete(Uint8List.fromList([1]));if(at=='decoder')audio.prepare!.complete();await flush(t);final before=audio.calls.where((c)=>c=='resume').length;expect(before,at=='playing'?1:0);t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await flush(t);expect(audio.calls.where((c)=>c=='resume').length,before);await t.pumpWidget(const SizedBox());await flush(t);
 });}
 testWidgets('covering a playing route pauses and returning needs explicit Play',(t)async{
  final nav=GlobalKey<NavigatorState>();await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/voice'),nav:nav));await t.tap(find.byTooltip('Play voice message'));await flush(t);nav.currentState!.push(MaterialPageRoute(builder:(_)=>const Scaffold(body:Text('Other screen'))));await flush(t);expect(audio.calls,contains('pause'));nav.currentState!.pop();await flush(t);expect(find.byTooltip('Play voice message'),findsOneWidget);expect(audio.calls.where((c)=>c=='resume').length,1);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('pause then play resumes the same authenticated source without downloading again',(t)async{
  final s=Download();await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);await t.tap(find.byTooltip('Pause voice message'));await flush(t);await t.tap(find.byTooltip('Play voice message'));await flush(t);expect(s.reads,1);expect(audio.calls.where((c)=>c=='source').length,1);expect(audio.calls.where((c)=>c=='resume').length,2);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('failed private fetch offers a new explicit attempt',(t)async{
  final s=Download(),bytes=Completer<Uint8List>();s.pending.add(bytes);await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);bytes.completeError(StateError('Fixture download failed'));await flush(t);expect(find.text('Could not play this voice message.'),findsOneWidget);await t.tap(find.byTooltip('Play voice message'));await flush(t);expect(s.reads,2);expect(find.byTooltip('Pause voice message'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('changing source invalidates an old private download',(t)async{
  final s=Download(),old=Completer<Uint8List>();s.pending.add(old);await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/old',session:s)));await t.tap(find.byTooltip('Play voice message'));await flush(t);await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/new',session:s)));old.complete(Uint8List.fromList([1]));await flush(t);expect(audio.calls,isNot(contains('source')));await t.tap(find.byTooltip('Play voice message'));await flush(t);expect(s.reads,2);expect(audio.calls.where((c)=>c=='resume').length,1);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('covered private download cannot load or play after returning',(t)async{
  final s=Download(),bytes=Completer<Uint8List>();s.pending.add(bytes);final nav=GlobalKey<NavigatorState>();await t.pumpWidget(app(VoiceBubble(url:'https://fixture.invalid/private',session:s),nav:nav));await t.tap(find.byTooltip('Play voice message'));await flush(t);nav.currentState!.push(MaterialPageRoute(builder:(_)=>const Scaffold(body:Text('Covered'))));await flush(t);bytes.complete(Uint8List.fromList([1]));await flush(t);nav.currentState!.pop();await flush(t);expect(audio.calls,isNot(contains('source')));expect(find.byTooltip('Play voice message'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
 testWidgets('decoder failure can be retried explicitly and completion resets the control',(t)async{
  audio.fail=true;await t.pumpWidget(app(const VoiceBubble(url:'https://fixture.invalid/voice')));await t.tap(find.byTooltip('Play voice message'));await flush(t);await t.pump(const Duration(seconds:31));await flush(t);expect(find.text('Could not play this voice message.'),findsOneWidget);audio.fail=false;await t.tap(find.byTooltip('Play voice message'));await flush(t);expect(find.byTooltip('Pause voice message'),findsOneWidget);audio.events.values.last.add(const AudioEvent(eventType:AudioEventType.complete));await flush(t);expect(find.byTooltip('Play voice message'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);
 });
 for(final lang in ['en','ne']){for(final brightness in [Brightness.light,Brightness.dark]){
 testWidgets('own and received voice controls retain contrast $lang ${brightness.name}',(t)async{
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final theme=buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']);final s=theme.colorScheme;
  await t.pumpWidget(RepaintBoundary(key:const ValueKey('voice-shot'),child:MaterialApp(theme:theme,debugShowCheckedModeBanner:false,builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final own in [false,true])Padding(padding:const EdgeInsets.all(12),child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:own?s.primary:s.surfaceContainerHigh,borderRadius:BorderRadius.circular(16)),child:DefaultTextStyle(style:theme.textTheme.bodyMedium!.copyWith(color:own?s.onPrimary:s.onSurface),child:const VoiceBubble(url:'https://fixture.invalid/voice'))))]))))));
  await t.pump();expect(t.takeException(),isNull);await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('voice-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/voice_${lang}_${brightness.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});await t.pumpWidget(const SizedBox());await flush(t);
 });}}

}

// Synthetic session, media and picker boundaries only. No live stories are read,
// uploaded or deleted and no native decoder/hardware is exercised.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class StorySession extends Session {
  String owner='a';
  final requests=<String>[];
  Future<dynamic> Function(String,String)? response;
  Future<Map<String,String>>? headers;
  Future<Uint8List>? photo;
  var photoReads=0;
  @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async {
    if(path=='/auth/me')return {'user':{'public_id':owner,'username':owner}};
    requests.add('$method $path');
    return response==null?{}:response!(method,path);
  }
  @override Future<dynamic> takeHome(String key)async=>null;
  @override Future<Map<String,String>> privateMediaHeaders(String url)async=>headers==null?{}:headers!;
  @override Future<Uint8List> fetchProtectedBytes(String url)async {
    photoReads++;return photo==null?Uint8List.fromList([0]):photo!;
  }
}
Map<String,dynamic> group({bool video=false,bool protected=true})=>{
 'author':{'public_id':'a','username':'a'},'all_viewed':false,
 'items':[{'public_id':'private-story','type':video?'video':'image','protected_media':protected,
 'url':'https://fixture.invalid/story','caption':'Private story caption','created_at':'2026-11-20T00:00:00Z'}]
};
Future<void> flush(WidgetTester t)async {await t.pump();await t.pump(const Duration(milliseconds:400));await t.pump();}
Future<void> fixture(Future<void> Function(StorySession) run)async {
 await http.runWithClient(()async{final s=StorySession();await s.login('first','not-a-password');await run(s);},()=>MockClient((_)async=>http.Response(jsonEncode({'access_token':'fixture','expires_in':3600}),200)));
}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final same in [false,true]){
  testWidgets('story bar drops delayed private rings on ${same?'same':'other'} login',(t)async{
   final pending=Completer<dynamic>();
   await fixture((s)async{
    s.response=(m,p)=>pending.future;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:StoriesBar(session:s))));await flush(t);
    if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
    pending.complete({'data':[{'author':{'username':'Late private author'},'items':[]}]});await flush(t);
    expect(find.text('Late private author'),findsNothing);expect(find.text('Your story'),findsNothing);expect(s.requests,['GET /stories']);
    await t.pumpWidget(const SizedBox());expect(t.takeException(),isNull);
   });
  });
  for(final boundary in ['headers','bytes']){
   testWidgets('viewer stops at delayed $boundary on ${same?'same':'other'} login',(t)async{
    final headers=Completer<Map<String,String>>(),bytes=Completer<Uint8List>();
    await fixture((s)async{
     s.headers=boundary=='headers'?headers.future:null;s.photo=boundary=='bytes'?bytes.future:null;
     await t.pumpWidget(MaterialApp(home:StoryViewer(session:s,group:group())));await flush(t);
     if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
     headers.complete({});bytes.complete(Uint8List.fromList([0]));await flush(t);
     expect(find.text('Private story caption'),findsNothing);expect(find.textContaining('another signed-in session'),findsOneWidget);
     expect(s.photoReads,boundary=='headers'?0:1);expect(s.requests,isEmpty);
     await t.pumpWidget(const SizedBox());expect(t.takeException(),isNull);
    });
   });
  }
  for(final action in ['delete','viewers-pending','viewers-open']){
   testWidgets('$action retires without replacement-account action on ${same?'same':'other'} login',(t)async{
    final pending=Completer<dynamic>();
    await fixture((s)async{
     s.response=(m,p)=>p.endsWith('/viewers')?pending.future:Future.value({});
     await t.pumpWidget(MaterialApp(home:StoryViewer(session:s,group:group())));await flush(t);
     expect(find.text('Private story caption'),findsOneWidget);
     await t.tap(find.byTooltip(action=='delete'?'Delete story':'Story viewers'));await flush(t);
     if(action=='viewers-open'){pending.complete({'data':[{'username':'Private viewer'}]});await flush(t);expect(find.text('@Private viewer'),findsOneWidget);}
     if(action=='delete')expect(find.byType(AlertDialog),findsOneWidget);
     if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
     if(!pending.isCompleted)pending.complete({'data':[{'username':'Private viewer'}]});await flush(t);
     expect(find.byType(AlertDialog),findsNothing);expect(find.text('@Private viewer'),findsNothing);expect(find.text('Private story caption'),findsNothing);
     expect(s.requests.where((r)=>r.startsWith('DELETE')),isEmpty);expect(s.requests.where((r)=>r=='POST /stories/private-story/view').length,1);
     expect(find.textContaining('another signed-in session'),findsOneWidget);await t.pumpWidget(const SizedBox());expect(t.takeException(),isNull);
    });
   });
  }
 }
 testWidgets('replacing Session object retires loaded story despite same owner and epoch',(t)async{
  await fixture((s)async{
   final key=GlobalKey();await t.pumpWidget(MaterialApp(home:StoryViewer(key:key,session:s,group:group())));await flush(t);
   final other=StorySession()..user={'public_id':'a','username':'a'};
   await t.pumpWidget(MaterialApp(home:StoryViewer(key:key,session:other,group:group())));await flush(t);
   expect(find.text('Private story caption'),findsNothing);expect(find.textContaining('another signed-in session'),findsOneWidget);expect(other.requests,isEmpty);
   await t.pumpWidget(const SizedBox());expect(t.takeException(),isNull);
  });
 });
 for(final pendingInit in [false,true]){
  testWidgets('video retirement disposes controller and never resumes after delayed initialization=$pendingInit',(t)async{
   final old=VideoPlayerPlatform.instance;final v=StoryVideo()..delayed=pendingInit;VideoPlayerPlatform.instance=v;
   addTearDown(()=>VideoPlayerPlatform.instance=old);
   await fixture((s)async{
    await t.pumpWidget(MaterialApp(home:StoryViewer(session:s,group:group(video:true,protected:false))));await flush(t);
    expect(v.nextId,1);if(!pendingInit)expect(v.playing[0],true);
    final plays=v.calls.where((a)=>a=='play:0').length;
    s.owner='b';await s.login('replacement','not-a-password');await flush(t);
    if(pendingInit)v.initialize(0);await flush(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await flush(t);
    expect(v.playing[0],false);expect(v.calls.where((a)=>a=='play:0').length,plays);expect(v.calls.where((a)=>a=='dispose:0').length,1);
    expect(find.textContaining('another signed-in session'),findsOneWidget);await t.pumpWidget(const SizedBox());await flush(t);expect(t.takeException(),isNull);
   });
  });
 }
 for(final lang in ['en','ne'])for(final mode in [Brightness.light,Brightness.dark]){
  testWidgets('retired story readable at large text $lang ${mode.name}',(t)async{
   for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));await l.load();}
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);prefs.lang=lang;addTearDown(()=>prefs.lang='en');
   await fixture((s)async{
    await t.pumpWidget(RepaintBoundary(key:const ValueKey('story-retired-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(2)),child:w!),home:StoryViewer(session:s,group:group()))));await flush(t);
    s.owner='b';await s.login('replacement','not-a-password');await flush(t);expect(find.text('Private story caption'),findsNothing);expect(t.takeException(),isNull);
    await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('story-retired-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/story_retired_${lang}_${mode.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
    await t.pumpWidget(const SizedBox());
   });
  });
 }
}

class StoryVideo extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int, bool>{};
  final calls = <String>[];
  var nextId = 0;
  bool delayed = false;
  bool failNext = false;
  @override
  Future<void> init() async {}
  void initialize(int id) => streams[id]!.add(VideoEvent(eventType: VideoEventType.initialized, size: const Size(100, 100), duration: const Duration(seconds: 30)));
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = nextId++;
    streams[id] = StreamController<VideoEvent>();
    playing[id] = false;
    if (failNext) { failNext = false; streams[id]!.addError(PlatformException(code:'VideoError',message:'fixture decoder failure')); } else if (!delayed) { initialize(id); }
    return id;
  }
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async { calls.add('dispose:$playerId'); playing[playerId] = false; }
  @override
  Future<void> play(int playerId) async { calls.add('play:$playerId'); playing[playerId] = true; }
  @override
  Future<void> pause(int playerId) async { calls.add('pause:$playerId'); playing[playerId] = false; }
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Colors.black);
}

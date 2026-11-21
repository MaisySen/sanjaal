// Independent reviewer harness. Exact PR screens; local fixture API and video frame.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/wallet_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/main.dart' show HomeShell, buildTheme;
import 'package:sanjaal/glass_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
ui.Image? frameImage;
class FrameVideo extends VideoPlayerPlatform {
 final streams=<int,StreamController<VideoEvent>>{};int next=1;
 @override Future<void> init()async{}
 @override Future<int?> createWithOptions(VideoCreationOptions o)async{final id=next++;streams[id]=StreamController<VideoEvent>();streams[id]!.add(VideoEvent(eventType:VideoEventType.initialized,size:const Size(390,520),duration:const Duration(seconds:18)));return id;}
 @override Stream<VideoEvent> videoEventsFor(int id)=>streams[id]!.stream;
 @override Future<void> dispose(int id)async{}
 @override Future<void> play(int id)async{}
 @override Future<void> pause(int id)async{}
 @override Future<void> setLooping(int id,bool v)async{}
 @override Future<void> setVolume(int id,double v)async{}
 @override Future<void> setPlaybackSpeed(int id,double v)async{}
 @override Future<void> setMixWithOthers(bool v)async{}
 @override Future<Duration> getPosition(int id)async=>Duration.zero;
 @override Future<void> seekTo(int id,Duration v)async{}
 @override Widget buildViewWithOptions(VideoViewOptions o)=>RawImage(image:frameImage,fit:BoxFit.cover);
}
final person=<String,dynamic>{'public_id':'mira','name':'Mira Chen','username':'mira','avatar_url':null,'following':false,'posts_count':24,'followers_count':318,'following_count':204};
Map<String,dynamic> post(String kind)=>{'public_id':kind+'1','kind':kind,'body':'A slower kind of morning.','author':person,'media':[{'type':'video','url':'https://fixture.invalid/local-frame.mp4'}],'hashtags':['morning'],'likes_count':128,'comments_count':14,'liked':false,'my_reaction':null,'created_at':DateTime.now().toUtc().subtract(const Duration(minutes:12)).toIso8601String()};
class FixtureSession extends Session {
 final reads=<String>[];
 FixtureSession(){user={'public_id':'review','username':'review','name':'Review account'};loading=false;}
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
  if(method!='GET')throw StateError('Review fixture disallows writes');reads.add(path);
  if(path=='/posts')return {'data':[post(query?['kind']=='reel'?'reel':'post')],'next_cursor':null};
  if(path=='/notifications/summary')return {'unread_messages':12};
  if(path=='/stories')return {'data':[{'author':person,'items':[{'public_id':'story1','type':'image','url':'https://fixture.invalid/story.jpg','seen':false,'created_at':DateTime.now().toUtc().toIso8601String()}]}]};
  if(path=='/wallet')return {'balance':0,'entries':[],'topup':{'esewa':false}};
  if(path.startsWith('/users/'))return {'user':person};
  return {'data':[],'next_cursor':null};
 }
}
void main(){
 setUpAll(()async{
  final devanagari=FontLoader('NotoDev')..addFont(File('assets/fonts/NotoSansDevanagari.ttf').readAsBytes().then((b)=>ByteData.sublistView(b)));await devanagari.load();
  final root=Platform.environment['FLUTTER_ROOT']??'';
  for(final family in ['Roboto','MaterialIcons']){final loader=FontLoader(family);loader.addFont(File('$root/bin/cache/artifacts/material_fonts/${family=='Roboto'?'Roboto-Regular.ttf':'MaterialIcons-Regular.otf'}').readAsBytes().then((b)=>ByteData.sublistView(b)));if(family=='Roboto'){loader.addFont(File('/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf').readAsBytes().then((b)=>ByteData.sublistView(b)));}await loader.load();}
 });
 for(final width in [390.0,320.0]){for(final scale in [1.0,1.8]){for(final brightness in [Brightness.light,Brightness.dark]){for(final screen in ['auth','feed','reels','wallet','profile','chats','rooms','settings']){
 testWidgets('$screen $width $scale ${brightness.name}',(tester)async{
  SharedPreferences.setMockInitialValues({});final old=VideoPlayerPlatform.instance;VideoPlayerPlatform.instance=FrameVideo();addTearDown(()=>VideoPlayerPlatform.instance=old);
  tester.view.physicalSize=Size(width,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
  await tester.runAsync(()async{if(frameImage==null){final codec=await ui.instantiateImageCodec(await File('/downloads/sanjaal-highfidelity/mountain.jpg').readAsBytes());frameImage=(await codec.getNextFrame()).image;}});
  final session=FixtureSession(),key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(theme:buildTheme(brightness,fontFamily:'Roboto'),debugShowCheckedModeBanner:false,builder:(c,child)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:switch(screen){'auth'=>AuthPage(session:session),'wallet'=>WalletPage(session:session),'profile'=>UserProfilePage(session:session,username:'mira'),'chats'=>ChatsPage(session:session),'rooms'=>RoomsPage(session:session),'settings'=>SettingsPage(session:session),_=>HomeShell(session:session)})));
  for(var i=0;i<5;i++){await tester.pump(const Duration(milliseconds:100));}
  if(screen=='reels'){final tab=tester.widget<GlassNavBar>(find.byType(GlassNavBar));tab.onSelected(1);for(var i=0;i<5;i++){await tester.pump(const Duration(milliseconds:100));}}
  final errors=<String>[];Object? e;while((e=tester.takeException())!=null){errors.add(e.toString());}
  print('EXACT_SCREEN_RESULT $screen width=$width scale=$scale ${brightness.name} errors=$errors');
  await tester.runAsync(()async{final image=await(key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('/downloads/sanjaal-pr-aligned/aligned-$screen-${width.toInt()}-$scale-${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
  if(screen=='feed'){
    await tester.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.byTooltip('Search')));
    for(var i=0;i<5;i++){await tester.pump(const Duration(milliseconds:100));}
    expect(find.byType(SearchPage),findsOneWidget);
  }
  await tester.pumpWidget(const SizedBox());await tester.pump();
  expect(errors,isEmpty);
 });
 }}}}
}

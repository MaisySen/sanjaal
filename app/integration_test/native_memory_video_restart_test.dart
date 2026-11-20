// Synthetic video, encrypted private draft files and native decoders only.
// One install, two processes. No API, upload, external endpoint or real member.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/creator_drafts_page.dart';
import 'package:sanjaal/creator_media_draft_store.dart';
import 'package:sanjaal/memory_video_preview.dart';
import 'package:sanjaal/media_visibility.dart';

const _owner='synthetic-memory-video-owner';
Future<void> until(WidgetTester t,bool Function() ready)async{
 for(var i=0;i<160 && !ready();i++)await t.pump(const Duration(milliseconds:100));
 expect(ready(),isTrue,reason:'native memory video must reach its explicit state');
}
String clock(WidgetTester t)=>t.widgetList<Text>(find.byType(Text)).map((w)=>w.data).whereType<String>().where((v)=>RegExp(r'^\d+:\d\d$').hasMatch(v)).single;
Future<void> assertPausedWallClock(WidgetTester t,String label)async{
 // Pumping a Duration alone advances test time, not the native decoder clock.
 // Keep polling while real time passes, then require the visible clock to hold.
 await t.pump(const Duration(milliseconds:450));
 final value=clock(t),elapsed=Stopwatch()..start();
 final parts=value.split(':').map(int.parse).toList();
 expect(parts[0]*60+parts[1],lessThan(17),reason:'Pause stability must be tested before the20-second fixture ends');
 while(elapsed.elapsedMilliseconds<1600){
  await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
  await t.pump(const Duration(milliseconds:100));
  expect(find.byTooltip('Pause'),findsNothing,reason:'$label must not resume');
  expect(find.byTooltip('Play'),findsOneWidget);
  expect(clock(t),value,reason:'$label clock advanced while paused');
 }
 print('NATIVE_PAUSE_WALL_CLOCK $label elapsed_ms=${elapsed.elapsedMilliseconds} position=$value');
}
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();SemanticsHandle? semantics;
 setUpAll(()async{if(Platform.isIOS){semantics=binding.ensureSemantics();for(var i=0;i<100&&!ui.PlatformDispatcher.instance.semanticsEnabled;i++)await Future<void>.delayed(const Duration(milliseconds:100));}});
 tearDownAll(()=>semantics?.dispose());
 Future<void> capture(WidgetTester t,String name)async{
  final preview=find.byType(MemoryVideoPreview);
  final native=find.byWidgetPredicate((w)=>w is AndroidViewSurface||w is UiKitView);
  final rect=preview.evaluate().isEmpty||native.evaluate().isEmpty?null:t.getRect(preview);
  final viewport=t.view.physicalSize/t.view.devicePixelRatio;
  final spec=<String,dynamic>{'viewport':[viewport.width,viewport.height],if(rect!=null)'videoRect':[rect.left,rect.top,rect.width,rect.height]};
  // OS capture is required: a Flutter raster does not include a native view.
  final dir=await getApplicationSupportDirectory();
  final pending=File('${dir.path}/$name.native-pending'),done=File('${dir.path}/$name.native-done');
  // Test bindings do not schedule normal Flutter frames while runAsync waits.
  // Keep pumping so Android platform textures reach the actual OS compositor.
  for(var frame=0;frame<6;frame++){
   await t.pump(const Duration(milliseconds:100));
   await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
  }
  await t.runAsync(()=>pending.writeAsString(jsonEncode(spec),flush:true));
  var captured=false;
  for(var i=0;i<250;i++){
   await t.pump(const Duration(milliseconds:100));
   captured=(await t.runAsync(()=>done.exists()))!;
   if(captured)break;
   await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
  }
  expect(captured,isTrue,reason:'Missing synchronized OS image');
 }
 testWidgets('encrypted videos play only from recovered memory after actual process death',(t)async{
  final dir=(await t.runAsync(getApplicationSupportDirectory))!;
  final sentinel=Platform.isAndroid?File('/data/user/0/au.fintex.sanjaal/files/synthetic-marker-recover'):File('${dir.path}/synthetic-marker-recover');
  final recover=sentinel.existsSync();const store=CreatorMediaDraftStore();
  final identity=File('${dir.path}/memory-video-identity.json');
  final original=File('${dir.path}/synthetic-picker.mp4');
  final nav=GlobalKey<NavigatorState>();
  final session=NoNetworkSession()..user={'public_id':_owner,'username':'synthetic'}..protectedStoriesEnabled=true;
  if(!recover){
   final bytes=(await rootBundle.load('test/fixtures/memory_synthetic_video.mp4')).buffer.asUint8List();
   await t.runAsync(()=>original.writeAsBytes(bytes,flush:true));
   final rows=<Map<String,dynamic>>[];
   for(final story in [false,true]){
    var d=(await t.runAsync(()=>store.save(_owner,text:story?'Recovered private video story':'Recovered video post',video:true,files:[XFile(original.path)],story:story,audience:story?'only_me':null)))!;
    d=(await t.runAsync(()=>store.attempted(_owner,d,value:true)))!;
    rows.add({'draft':d.toJson(),'hash':sha256.convert(bytes).toString()});
   }
   await t.runAsync(()=>identity.writeAsString(jsonEncode(rows),flush:true));await t.runAsync(original.delete);
   await t.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Encrypted videos saved; originals deleted'))));await t.pumpAndSettle();await capture(t,'memory_video_0_seed');return;
  }
  expect(original.existsSync(),false);expect(await t.runAsync(()=>store.read('different-owner')),isEmpty);
  final rows=jsonDecode(await identity.readAsString()) as List;
  for(final row in rows){
   final d=CreatorMediaDraft.decode(row['draft']);final files=(await t.runAsync(()=>store.open(_owner,d)))!;
   expect(sha256.convert(await files.single.readAsBytes()).toString(),row['hash']);expect(files.single.path,startsWith('draft-memory://'));
   await t.pumpWidget(MaterialApp(navigatorKey:nav,navigatorObservers:[mediaRoutes],home:CreatorDraftsPage(session:session)));
   await until(t,()=>find.text(d.text).evaluate().isNotEmpty);await t.tap(find.text(d.text));
   await until(t,()=>find.byType(MemoryVideoPreview).evaluate().isNotEmpty);
   await t.scrollUntilVisible(find.byType(MemoryVideoPreview),120,scrollable:find.byType(Scrollable).first);
   await until(t,()=>find.byTooltip('Play').evaluate().isNotEmpty);
   // Neither loading nor merely opening can start playback.
   expect(find.byTooltip('Pause'),findsNothing);expect(find.text('0:00'),findsOneWidget);
   await capture(t,d.story?'memory_video_4_story_ready':'memory_video_1_post_ready');
   await t.ensureVisible(find.byTooltip('Play'));await t.tap(find.byTooltip('Play'));
   await until(t,()=>find.text('0:01').evaluate().isNotEmpty);
   await capture(t,d.story?'memory_video_5_story_playing':'memory_video_2_post_playing');
   if(!d.story){
    nav.currentState!.push(MaterialPageRoute<void>(builder:(_)=>const Scaffold(body:Text('Preview covered'))));
    await t.pumpAndSettle();
    nav.currentState!.pop();await t.pumpAndSettle();
    await until(t,()=>find.byTooltip('Play').evaluate().isNotEmpty);
    await assertPausedWallClock(t,'route-return');
    await capture(t,'memory_video_2a_route_return_paused');
    await t.tap(find.byTooltip('Play'));await until(t,()=>find.byTooltip('Pause').evaluate().isNotEmpty);
   }
   await t.tap(find.byTooltip('Pause'));await until(t,()=>find.byTooltip('Play').evaluate().isNotEmpty);
   await assertPausedWallClock(t,d.story?'story-manual':'post-manual');
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,d.story?'Share story':'Post')).onPressed,isNull,reason:'playback never lifts uncertain-send lock');
   await capture(t,d.story?'memory_video_6_story_paused':'memory_video_3_post_paused');
   await t.pageBack();await t.pumpAndSettle();expect(session.requests,0);
  }
  // A loaded native preview must be removed when the opening login retires.
  final video=CreatorMediaDraft.decode(rows.first['draft']);
  final file=(await t.runAsync(()=>store.open(_owner,video)))!.single;
  await t.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(height:280,child:MemoryVideoPreview(session:session,file:file)))));
  await until(t,()=>find.byTooltip('Play').evaluate().isNotEmpty);await t.tap(find.byTooltip('Play'));await until(t,()=>find.byTooltip('Pause').evaluate().isNotEmpty);
  session.epoch++;session.notifyListeners();await t.pumpAndSettle();
  expect(find.byType(AndroidViewSurface),findsNothing);expect(find.byType(UiKitView),findsNothing);expect(find.byTooltip('Pause'),findsNothing);
  await capture(t,'memory_video_7_retired');expect(session.requests,0);
  expect(original.existsSync(),false);expect((await t.runAsync(()=>store.read(_owner)))!.every((d)=>d.attempted),isTrue);
  print('MEMORY_VIDEO exact encrypted originals restored after process death; native post/story decoder clock advanced; covered route stayed paused; same-owner generation retired; explicit Play/Pause; no auto-start; attempted locks unchanged; session retirement; zero API requests');
 });
}
class NoNetworkSession extends Session{
 var requests=0,epoch=0;
 @override int get generation=>epoch;
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{requests++;throw StateError('No preview fixture may call API');}
}

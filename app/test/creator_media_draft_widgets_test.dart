// Synthetic local media UI only, not native restart or backend proof.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/creator_media_draft_store.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:sanjaal/ui.dart' show prefs,t_;
import 'package:sanjaal/main.dart' show buildTheme;

class CapturedMediaSession extends Session {
 List<UploadFile>? sent;
 bool guarded=false;
 @override Future<Map<String,dynamic>> createPost(String body,{List<UploadFile> files=const [],bool reel=false,List<String>? pollOptions,String? intent})async{
  guarded=(await const CreatorMediaDraftStore().read('a')).single.attempted;
  sent=files;
  return {'public_id':'synthetic-confirmed','author':{'public_id':'a','username':'synthetic'},'media':[],'kind':reel?'reel':'post'};
 }
}
class CapturedStorySession extends Session {
 Map<String,String>? sentFields;
 bool guarded=false;
 @override Future<Map<String,dynamic>> upload(String path,{Map<String,String> fields=const {},String field='media',UploadFile? file,String? intent})async{
  guarded=(await const CreatorMediaDraftStore().read('a')).single.attempted;
  sentFields=fields;
  return {'story':{'public_id':'synthetic-confirmed-story','url':'https://fixture.invalid/story.png','type':'image'}};
 }
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late Directory root;
 setUp((){
  prefs.lang='en';
  root=Directory.systemTemp.createTempSync('media-ui-test-');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),(call)async=>root.path);
 });
 tearDown((){
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),null);
  root.deleteSync(recursive:true);
 });
 Future<(CreatorMediaDraft,List<XFile>)> seed({bool attempted=false,bool video=false,bool story=false,String? audience})async{
  print('MEDIA_UI seed start');
  final source=File(video?'test/fixtures/ios_synthetic_video.mp4':'test/fixtures/ridge.png');
  const store=CreatorMediaDraftStore();
  var draft=await store.save('a',text:'A saved community moment',video:video,files:[XFile(source.path)],story:story,audience:audience);
  print('MEDIA_UI encrypted seed saved');
  if(attempted)draft=await store.attempted('a',draft,value:true);
  print('MEDIA_UI seed opening');
  return (draft,await store.open('a',draft));
 }
 testWidgets('explicit story save keeps selected only-me audience without sharing',(t)async{
  final session=CapturedStorySession()..user={'public_id':'a'};session.protectedStoriesEnabled=true;
  final data=File('test/fixtures/ridge.png').readAsBytesSync();
  await t.pumpWidget(MaterialApp(home:StoryComposePage(session:session,file:XFile.fromData(data,path:'selected.png'),isVideo:false)));
  await t.pumpAndSettle();
  await t.tap(find.text('Followers'));await t.pumpAndSettle();
  await t.tap(find.text('Only me'));await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byType(TextField),150,scrollable:find.byType(Scrollable).first);
  await t.enterText(find.byType(TextField),'Private story draft');
  await t.runAsync(()async{
   await t.tap(find.byTooltip('Save media draft'));
   for(var i=0;i<100;i++){
    if((await const CreatorMediaDraftStore().read('a')).isNotEmpty)break;
    await Future<void>.delayed(const Duration(milliseconds:20));
   }
  });
  await t.pumpAndSettle();
  final saved=(await t.runAsync(()=>const CreatorMediaDraftStore().read('a')))!.single;
  expect(saved.text,'Private story draft');expect(saved.story,isTrue);expect(saved.audience,'only_me');expect(saved.attempted,isFalse);
  expect(session.sentFields,isNull);
  await t.pumpWidget(const SizedBox());
 });
 for(final audience in [('followers','Followers'),('close_friends','Close friends'),('only_me','Only me')]){
  testWidgets('saved story keeps ${audience.$1} audience in its own composer',(t)async{
   final data=(await t.runAsync(()=>seed(story:true,audience:audience.$1)))!;
   final session=Session()..user={'public_id':'a'};session.protectedStoriesEnabled=true;
   await t.pumpWidget(MaterialApp(home:StoryComposePage(session:session,file:data.$2.single,isVideo:false,initialMediaDraft:data.$1)));
   await t.pumpAndSettle();
   expect(find.text(audience.$2),findsOneWidget);
   await t.scrollUntilVisible(find.byType(TextField),150,scrollable:find.byType(Scrollable).first);
   expect(t.widget<TextField>(find.byType(TextField)).controller!.text,data.$1.text);
   session.user={'public_id':'b'};session.setOffline(true);await t.pump();
   expect(find.textContaining('another signed-in session'),findsOneWidget);
   expect(find.text(audience.$2),findsNothing);
   expect(find.byType(TextField),findsNothing);
   await t.pumpWidget(const SizedBox());
  });
 }
 testWidgets('manual saved only-me story remains only-me and marks before send',(t)async{
  final data=(await t.runAsync(()=>seed(story:true,audience:'only_me')))!;
  final session=CapturedStorySession()..user={'public_id':'a'};session.protectedStoriesEnabled=true;
  await t.pumpWidget(MaterialApp(home:StoryComposePage(session:session,file:data.$2.single,isVideo:false,backgroundUpload:true,initialMediaDraft:data.$1)));
  await t.pumpAndSettle();
  await t.runAsync(()async{
   await t.tap(find.text('Share story'));
   for(var i=0;i<100 && session.sentFields==null;i++){await Future<void>.delayed(const Duration(milliseconds:20));}
  });
  await t.pumpAndSettle();
  expect(session.sentFields?['audience'],'only_me');expect(session.guarded,isTrue);
  expect(session.sentFields?['caption'],data.$1.text);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('attempted story requires separate-upload confirmation and preserves audience',(t)async{
  final data=(await t.runAsync(()=>seed(story:true,audience:'close_friends',attempted:true)))!;
  final session=Session()..user={'public_id':'a'};session.protectedStoriesEnabled=true;
  await t.pumpWidget(MaterialApp(home:StoryComposePage(session:session,file:data.$2.single,isVideo:false,initialMediaDraft:data.$1)));
  await t.pumpAndSettle();
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Share story')).onPressed,isNull);
  await t.tap(find.text('Prepare a separate upload'));await t.pumpAndSettle();
  expect((await t.runAsync(()=>const CreatorMediaDraftStore().read('a')))!.single.toJson(),data.$1.toJson());
  await t.tap(find.text('Cancel'));await t.pumpAndSettle();
  expect(find.text('Close friends'),findsOneWidget);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('restored media edit must be saved before manual Post',(t)async{
  final data=(await t.runAsync(()=>seed()))!;
  final session=Session()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,initialMediaDraft:data.$1,savedMediaFiles:data.$2)));
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  expect(find.byType(Image),findsWidgets);
  await t.enterText(find.byType(TextField),'Changed caption');
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  expect(find.textContaining('Save media changes before posting'),findsOneWidget);
  expect((await t.runAsync(()=>const CreatorMediaDraftStore().read('a')))!.single.attempted,isFalse);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('manual send uses encrypted saved bytes, not changed picker bytes',(t)async{
  final data=(await t.runAsync(()=>seed()))!;
  final original=await data.$2.single.readAsBytes();
  final source=File('${root.path}/picker.png');await t.runAsync(()=>source.writeAsBytes(original));
  final session=CapturedMediaSession()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,backgroundUpload:true,initialMediaDraft:data.$1,savedMediaFiles:[XFile(source.path)])));
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  await t.runAsync(()=>source.writeAsString('picker changed after saving'));
  await t.runAsync(()async{
   await t.tap(find.widgetWithText(FilledButton,'Post'));
   for(var i=0;i<100 && session.sent==null;i++){await Future<void>.delayed(const Duration(milliseconds:20));}
  });
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  expect(session.sent,isNotNull);expect(session.guarded,isTrue);
  expect(session.sent!.single.bytes,original);
  expect(session.sent!.single.name,'media.png');
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('restored attempted video cannot post or reset without confirmation',(t)async{
  final data=(await t.runAsync(()=>seed(attempted:true,video:true)))!;
  final session=Session()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,initialMediaDraft:data.$1,savedMediaFiles:data.$2)));
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  expect(find.text('media.mp4'),findsOneWidget);
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull);
  await t.tap(find.text('Prepare a separate upload'));
  print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
  expect((await t.runAsync(()=>const CreatorMediaDraftStore().read('a')))!.single.toJson(),data.$1.toJson());
  await t.pumpWidget(const SizedBox());
 });
 for(final lang in ['en','ne'])for(final brightness in Brightness.values){
  testWidgets('saved story audience render ${brightness.name} $lang',(t)async{
   final data=(await t.runAsync(()=>seed(story:true,audience:'only_me',attempted:true)))!;
   prefs.lang=lang;
   for(final font in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
    final loader=FontLoader(font.$1)..addFont(Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())));await loader.load();
   }
   t.view.physicalSize=const Size(960,1920);t.view.devicePixelRatio=3;addTearDown(t.view.reset);
   final key=GlobalKey();final session=Session()..user={'public_id':'a'};session.protectedStoriesEnabled=true;
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.6),viewInsets:const EdgeInsets.only(bottom:240)),child:w!),home:StoryComposePage(session:session,file:data.$2.single,isVideo:false,initialMediaDraft:data.$1))));
   await t.pumpAndSettle();expect(t.takeException(),isNull);
   await t.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive:true);
    File('test/renders/story_saved_${brightness.name}_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
   });
   await t.scrollUntilVisible(find.byType(TextField),120,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();
   expect(find.byType(TextField).hitTestable(),findsOneWidget);
   await t.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    File('test/renders/story_caption_${brightness.name}_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
   });
   await t.pumpWidget(const SizedBox());
  });
 }
 for(final lang in ['en','ne'])for(final brightness in Brightness.values){
  testWidgets('attempted media render ${brightness.name} $lang',(t)async{
   final data=(await t.runAsync(()=>seed(attempted:true)))!;
   prefs.lang=lang;
   for(final font in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
    final loader=FontLoader(font.$1)..addFont(Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())));await loader.load();
   }
   t.view.physicalSize=const Size(960,1920);t.view.devicePixelRatio=3;addTearDown(t.view.reset);
   final key=GlobalKey();
   final session=Session()..user={'public_id':'a'};
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:const TextScaler.linear(1.6),viewInsets:const EdgeInsets.only(bottom:240)),child:w!),home:ComposePage(session:session,initialMediaDraft:data.$1,savedMediaFiles:data.$2))));
   print('MEDIA_UI pump settle');
  await t.pumpAndSettle();
  print('MEDIA_UI settle done');
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,t_('Post'))).onPressed,isNull);
   expect(t.takeException(),isNull);
   await t.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive:true);
    File('test/renders/media_attempted_${brightness.name}_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
   });
   await t.scrollUntilVisible(find.byType(TextField),100,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();
   final field=t.getRect(find.byType(TextField));
   final toolbar=t.getRect(find.text('Remove media').evaluate().isNotEmpty?find.text('Remove media'):find.text(t_('Remove media')));
   expect(field.top,greaterThanOrEqualTo(56));expect(field.top,lessThan(toolbar.top));
   await t.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    File('test/renders/media_caption_${brightness.name}_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
   });
   await t.pumpWidget(const SizedBox());
  });
 }
}

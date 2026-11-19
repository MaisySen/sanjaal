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
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late Directory root;
 setUp(()async{
  prefs.lang='en';
  root=await Directory.systemTemp.createTemp('media-ui-test-');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),(call)async=>root.path);
 });
 tearDown(()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),null);
  await root.delete(recursive:true);
 });
 Future<(CreatorMediaDraft,List<XFile>)> seed({bool attempted=false,bool video=false})async{
  final source=File(video?'test/fixtures/ios_synthetic_video.mp4':'test/fixtures/ridge.png');
  const store=CreatorMediaDraftStore();
  var draft=await store.save('a',text:'A saved community moment',video:video,files:[XFile(source.path)]);
  if(attempted)draft=await store.attempted('a',draft,value:true);
  return (draft,await store.open('a',draft));
 }
 testWidgets('restored media edit must be saved before manual Post',(t)async{
  final data=(await t.runAsync(()=>seed()))!;
  final session=Session()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,initialMediaDraft:data.$1,savedMediaFiles:data.$2)));
  await t.pumpAndSettle();
  expect(find.byType(Image),findsWidgets);
  await t.enterText(find.byType(TextField),'Changed caption');
  await t.tap(find.widgetWithText(FilledButton,'Post'));
  await t.pumpAndSettle();
  expect(find.textContaining('Save media changes before posting'),findsOneWidget);
  expect((await const CreatorMediaDraftStore().read('a')).single.attempted,isFalse);
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('manual send uses encrypted saved bytes, not changed picker bytes',(t)async{
  final data=(await t.runAsync(()=>seed()))!;
  final original=await data.$2.single.readAsBytes();
  final source=File('${root.path}/picker.png');await t.runAsync(()=>source.writeAsBytes(original));
  final session=CapturedMediaSession()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,backgroundUpload:true,initialMediaDraft:data.$1,savedMediaFiles:[XFile(source.path)])));
  await t.pumpAndSettle();
  await t.runAsync(()=>source.writeAsString('picker changed after saving'));
  await t.runAsync(()async{
   await t.tap(find.widgetWithText(FilledButton,'Post'));
   for(var i=0;i<100 && session.sent==null;i++){await Future<void>.delayed(const Duration(milliseconds:20));}
  });
  await t.pumpAndSettle();
  expect(session.sent,isNotNull);expect(session.guarded,isTrue);
  expect(session.sent!.single.bytes,original);
  expect(session.sent!.single.name,'media.png');
  await t.pumpWidget(const SizedBox());
 });
 testWidgets('restored attempted video cannot post or reset without confirmation',(t)async{
  final data=(await t.runAsync(()=>seed(attempted:true,video:true)))!;
  final session=Session()..user={'public_id':'a'};
  await t.pumpWidget(MaterialApp(home:ComposePage(session:session,initialMediaDraft:data.$1,savedMediaFiles:data.$2)));
  await t.pumpAndSettle();
  expect(find.text('media.mp4'),findsOneWidget);
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull);
  await t.tap(find.text('Prepare a separate upload'));
  await t.pumpAndSettle();
  expect((await const CreatorMediaDraftStore().read('a')).single.toJson(),data.$1.toJson());
  await t.pumpWidget(const SizedBox());
 });
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
   await t.pumpAndSettle();
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,t_('Post'))).onPressed,isNull);
   expect(t.takeException(),isNull);
   await t.runAsync(()async{
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    Directory('test/renders').createSync(recursive:true);
    File('test/renders/media_attempted_${brightness.name}_$lang.png').writeAsBytesSync(bytes!.buffer.asUint8List());
   });
   await t.pumpWidget(const SizedBox());
  });
 }
}

// Synthetic auth/media only. No private service, real identity or device proof.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/private_media_image.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

const url='$apiBase/conversations/synthetic/messages/private/media';
Future<void> flush(WidgetTester t)async{
 for(var i=0;i<4;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump();}
}
bool hasPixels(WidgetTester t)=>t.widgetList<RawImage>(find.byType(RawImage)).any((w)=>w.image!=null);
Future<void> scene(WidgetTester t,Future<void> Function(Session,Completer<http.Response>,void Function(String),Completer<http.Response>,List<String>) run)async{
 SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});
 final media=Completer<http.Response>(),replacement=Completer<http.Response>();final requests=<String>[];var owner='first',grants=0;
 await http.runWithClient(()async{
  final s=Session(unregisterPush:(_)async{});await s.login('synthetic','synthetic');
  await run(s,media,(v)=>owner=v,replacement,requests);
  await t.pumpWidget(const SizedBox());await flush(t);
 },()=>MockClient((r)async{
  if(r.url.path.endsWith('/oauth/token')){if(++grants>1)return replacement.future;return http.Response(jsonEncode({'access_token':'synthetic','expires_in':3600}),200);}
  if(r.url.path.endsWith('/devices/remove'))return http.Response('{}',200);
  if(r.url.path.endsWith('/auth/me'))return http.Response(jsonEncode({'user':{'public_id':owner,'username':owner}}),200);
  requests.add(r.url.toString());return media.future;
 }));
 // Each test starts cold, never borrowing another test's decoded pixels.
 PaintingBinding.instance.imageCache.clear();PaintingBinding.instance.imageCache.clearLiveImages();

}
Widget view(Session s,{Brightness brightness=Brightness.light})=>RepaintBoundary(key:const ValueKey('private-photo-shot'),child:MaterialApp(theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(2)),child:w!),home:PrivatePhotoViewer(session:s,urls:const[url])));
Future<http.Response> imageReply(WidgetTester t)async{
 final r=ui.PictureRecorder();ui.Canvas(r).drawColor(const ui.Color(0xffcc2277),ui.BlendMode.src);
 return (await t.runAsync(()async{final im=await r.endRecording().toImage(20,20);final bytes=(await im.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();im.dispose();return http.Response.bytes(bytes,200);}))!;
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final mode in ['same login','other login','logout','failed pending login']){
  for(final delayed in [false,true]){
   testWidgets('private viewer retires ${delayed?'delayed':'decoded'} photo on $mode',(t)async{
    await scene(t,(s,media,owner,replacement,requests)async{
     final response=await imageReply(t);
     if(!delayed)media.complete(response);
     await t.pumpWidget(view(s));await flush(t);expect(requests.length,1);
     if(!delayed)expect(hasPixels(t),isTrue);
     final old=PrivateMediaImage(s,url);
     Future<void>? login;
     if(mode=='logout'){await t.runAsync(s.logout);}else{if(mode=='other login')owner('second');login=s.login('replacement','synthetic');}
     await t.pump();expect(find.byType(Image),findsNothing);expect(hasPixels(t),isFalse);
     expect(find.textContaining('another signed-in session'),findsOneWidget);
     final next=PrivateMediaImage(s,url);expect(next==old,isFalse);
     await expectLater(old.obtainKey(ImageConfiguration.empty),throwsA(isA<ApiError>()));
     if(delayed)media.complete(response);
     if(login!=null){replacement.complete(mode=='failed pending login'?http.Response('{}',401):http.Response(jsonEncode({'access_token':'replacement','expires_in':3600}),200));if(mode=='failed pending login'){await expectLater(login,throwsA(isA<ApiError>()));}else{await login;}}
     await flush(t);expect(find.byType(Image),findsNothing);expect(requests.length,1);expect(t.takeException(),isNull);
    });
   });
  }
 }
 testWidgets('replacing the Session object retires an already decoded private photo',(t)async{
  await scene(t,(s,media,owner,replacement,requests)async{
   media.complete(await imageReply(t));await t.pumpWidget(view(s));await flush(t);expect(hasPixels(t),isTrue);
   final other=Session(unregisterPush:(_)async{})..user={'public_id':'first','username':'first'};
   await t.pumpWidget(view(other));await flush(t);
   expect(find.byType(Image),findsNothing);expect(hasPixels(t),isFalse);expect(find.textContaining('another signed-in session'),findsOneWidget);
   expect(requests.length,1);expect(t.takeException(),isNull);
  });
 });
 testWidgets('new login cannot reuse old private image cache key even for same member',(t)async{
  await scene(t,(s,media,owner,replacement,requests)async{
   media.complete(await imageReply(t));final old=PrivateMediaImage(s,url);
   await t.pumpWidget(view(s));await flush(t);expect(hasPixels(t),isTrue);
   final login=s.login('same-member','synthetic');replacement.complete(http.Response(jsonEncode({'access_token':'replacement','expires_in':3600}),200));await login;
   final current=PrivateMediaImage(s,url);expect(old==current,isFalse);
   await t.pumpWidget(const SizedBox());await flush(t);await t.pumpWidget(view(s));await flush(t);
   expect(hasPixels(t),isTrue);expect(requests.length,2,reason:'new generation must load its own private bytes');expect(t.takeException(),isNull);
  });
 });
 for(final lang in ['en','ne'])for(final dark in [false,true]){
  testWidgets('retired private viewer large text $lang dark=$dark',(t)async{
   t.view.physicalSize=const Size(320,720);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   prefs.lang=lang;addTearDown(()=>prefs.lang='en');
   for(final f in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));await l.load();}
   await scene(t,(s,media,owner,replacement,requests)async{
    media.complete(await imageReply(t));
    await t.pumpWidget(view(s,brightness:dark?Brightness.dark:Brightness.light));await flush(t);
    await t.runAsync(s.logout);await flush(t);expect(find.byType(Image),findsNothing);expect(t.takeException(),isNull);
    await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('private-photo-shot'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/private_photo_${lang}_${dark?'dark':'light'}.png').writeAsBytesSync(data!.buffer.asUint8List());image.dispose();});
   });
  });
 }
}

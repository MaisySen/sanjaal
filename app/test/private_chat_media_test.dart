// Synthetic HTTP only. No live chat, credential or private image is used.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/private_media_image.dart';
import 'package:sanjaal/photo_gallery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
Future<void> fixture(Future<void> Function(Session) run,{Future<http.Response> Function(http.Request)? media})async{
 SharedPreferences.setMockInitialValues({});
 await http.runWithClient(()async{final s=Session();await s.login('fixture','not-a-password');await run(s);},()=>MockClient((r)async{
  if(r.url.path.endsWith('/oauth/token'))return http.Response(jsonEncode({'access_token':'fixture','expires_in':3600}),200);
  if(r.url.path.endsWith('/auth/me'))return http.Response(jsonEncode({'user':{'public_id':'member','username':'fixture'}}),200);
  return media==null?http.Response.bytes([1,2,3],200):media(r);
 }));
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final url in ['https://unrelated.invalid/file','https://sanjaal-api.onrender.com.attacker.invalid/file','https://name:secret@sanjaal-api.onrender.com/file','/relative/file','file:///tmp/file','not a url','http://sanjaal-api.onrender.com/file','https://sanjaal-api.onrender.com:444/file']){
 test('foreign malformed or credentialed private URL is rejected before HTTP $url',()async{
  var requests=0;await fixture((s)async{
   expect(s.supportsPrivateMedia(url),isFalse);expect(s.mediaHeadersFor(url),isEmpty);
   await expectLater(s.fetchBytes(url),throwsA(isA<ApiError>()));expect(requests,0);
  },media:(r)async{requests++;return http.Response.bytes([1],200);});
 });
 }
 testWidgets('private image decoder and full-screen provider use non-redirecting bytes',(t)async{
  final recorder=ui.PictureRecorder();ui.Canvas(recorder).drawColor(const ui.Color(0xff123456),ui.BlendMode.src);
  final bytes=await t.runAsync(()async{final pixel=await recorder.endRecording().toImage(2,2);final result=(await pixel.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();pixel.dispose();return result;});
  var requests=0;
  await fixture((s)async{
   await t.pumpWidget(MaterialApp(home:PhotoViewer(urls:['$apiBase/conversations/c/messages/m/media'],provider:(url)=>PrivateMediaImage(s,url))));
   for(var i=0;i<5;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump();}
   expect(t.widget<Image>(find.byType(Image)).image,isA<PrivateMediaImage>());expect(requests,1);
   expect(t.widgetList<RawImage>(find.byType(RawImage)).any((w)=>w.image!=null),isTrue);expect(t.takeException(),isNull);
   final original=PrivateMediaImage(s,'$apiBase/conversations/c/messages/m/media');s.user={'public_id':'other','username':'other'};
   expect(original==PrivateMediaImage(s,'$apiBase/conversations/c/messages/m/media'),isFalse);
   await t.pumpWidget(const SizedBox());
  },media:(r)async{requests++;expect(r.followRedirects,isFalse);return http.Response.bytes(bytes!,200);});
 });
 testWidgets('private full-screen image refuses redirected bytes and never opens destination',(t)async{
  var requests=0;
  await fixture((s)async{
   await t.pumpWidget(MaterialApp(home:PhotoViewer(urls:['$apiBase/conversations/c/messages/redirect/media'],provider:(url)=>PrivateMediaImage(s,url))));
   for(var i=0;i<4;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump();}
   expect(requests,1);expect(find.text('Photo could not load'),findsOneWidget);expect(t.takeException(),isNull);
   await t.tap(find.text('Try again'));for(var i=0;i<4;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump();}
   expect(requests,2);expect(find.text('Photo could not load'),findsOneWidget);await t.pumpWidget(const SizedBox());
  },media:(r)async{requests++;expect(r.followRedirects,isFalse);return http.Response('',302,headers:{'location':'https://unrelated.invalid/image'});});
 });
 test('own API sends private headers and disables redirects',()async{
  var requests=0;await fixture((s)async{
   expect(s.supportsPrivateMedia('$apiBase/conversations/c/messages/m/media'),isTrue);
   expect(await s.fetchBytes('$apiBase/conversations/c/messages/m/media'),[1,2,3]);expect(requests,1);
  },media:(r)async{requests++;expect(r.headers['Authorization'],'Bearer fixture');expect(r.followRedirects,isFalse);return http.Response.bytes([1,2,3],200);});
 });
 test('redirect response is refused rather than fetching another origin',()async{
  var requests=0;await fixture((s)async{
   await expectLater(s.fetchBytes('$apiBase/conversations/c/messages/m/media'),throwsA(isA<ApiError>()));expect(requests,1);
  },media:(r)async{requests++;expect(r.followRedirects,isFalse);return http.Response('',302,headers:{'location':'https://unrelated.invalid/private'});});
 });
 test('late private audio bytes cannot cross member identities',()async{
  final pending=Completer<http.Response>();final requested=Completer<void>();
  await fixture((s)async{
   final bytes=s.fetchBytes('$apiBase/conversations/c/messages/m/media');final check=expectLater(bytes,throwsA(isA<ApiError>()));await requested.future;
   s.user={'public_id':'different','username':'other'};s.notifyListeners();pending.complete(http.Response.bytes([9,9],200));await check;
  },media:(r)async{requested.complete();return pending.future;});
 });
}

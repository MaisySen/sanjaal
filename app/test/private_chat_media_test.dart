// Synthetic HTTP only. No live chat, credential or private image is used.
import 'dart:async';
import 'dart:convert';
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

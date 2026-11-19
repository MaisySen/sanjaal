// Synthetic identity-provider responses only. No accounts are created.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/refresh_store.dart';
http.Response reply(Object value,[int status=200])=>http.Response(jsonEncode(value),status);
Future<void> tick()async=>Future<void>.delayed(Duration.zero);
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp((){SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});});
 for(final same in [false,true])for(final status in [200,400]){
 test('late signup $status cannot replace ${same?'same':'other'} member login',()async{
  final signup=Completer<http.Response>();var grants=0,reads=0;String owner='a';final session=Session();
  await http.runWithClient(()async{
   await session.login('first','not-a-password');
   final pending=session.register('signup@fixture.invalid','new-member','not-a-password');
   final rejected=expectLater(pending,throwsA(isA<ApiError>()));await tick();
   if(!same)owner='b';await session.login('replacement','not-a-password');final generation=session.generation;
   signup.complete(reply(status==200?{'email':'signup@fixture.invalid'}:{'message':'Synthetic signup rejected'},status));
   await rejected;await tick();
   expect(grants,2);expect(reads,2);expect(session.generation,generation);expect(session.user?['public_id'],owner);expect(await RefreshStore.read(),'refresh-2');
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/dbconnections/signup'))return signup.future;
   if(r.url.path.endsWith('/oauth/token')){grants++;return reply({'access_token':'fixture-$grants','refresh_token':'refresh-$grants','expires_in':3600});}
   reads++;return reply({'user':{'public_id':owner,'username':owner}});
  }));
 });}
 test('late signup after logout does not reopen identity or credentials',()async{
  final signup=Completer<http.Response>();var grants=0;final session=Session(unregisterPush:(_)async{});
  await http.runWithClient(()async{
   final pending=session.register('signup@fixture.invalid','new-member','not-a-password');final rejected=expectLater(pending,throwsA(isA<ApiError>()));await tick();
   await session.logout();final generation=session.generation;
   signup.complete(reply({'email':'signup@fixture.invalid'}));await rejected;
   expect(grants,0);expect(session.user,isNull);expect(await RefreshStore.read(),isNull);expect(session.generation,generation);
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/dbconnections/signup'))return signup.future;
   grants++;return reply({});
  }));
 });
 test('older concurrent signup cannot sign in while newer signup is pending',()async{
  final old=Completer<http.Response>(),newer=Completer<http.Response>();var signups=0,grants=0;final session=Session();
  await http.runWithClient(()async{
   final first=session.register('first@fixture.invalid','first','not-a-password');final rejected=expectLater(first,throwsA(isA<ApiError>()));await tick();
   final second=session.register('second@fixture.invalid','second','not-a-password');await tick();
   old.complete(reply({'email':'first@fixture.invalid'}));await rejected;expect(grants,0);expect(session.user,isNull);
   newer.complete(reply({'email':'second@fixture.invalid'}));await second;expect(grants,1);expect(session.user?['public_id'],'newest');
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/dbconnections/signup'))return ++signups==1?old.future:newer.future;
   if(r.url.path.endsWith('/oauth/token')){grants++;expect(r.bodyFields['username'],'second@fixture.invalid');return reply({'access_token':'newest','refresh_token':'newest-refresh','expires_in':3600});}
   return reply({'user':{'public_id':'newest','username':'newest'}});
  }));
 });
 test('current signup retains explicit login continuation without duplicate request',()async{
  var signups=0,grants=0;final session=Session();
  await http.runWithClient(()async{
   await session.register('current@fixture.invalid','current','not-a-password');
   expect(signups,1);expect(grants,1);expect(session.user?['public_id'],'current');expect(await RefreshStore.read(),'current-refresh');
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/dbconnections/signup')){signups++;return reply({'email':'current@fixture.invalid'});}
   if(r.url.path.endsWith('/oauth/token')){grants++;return reply({'access_token':'current','refresh_token':'current-refresh','expires_in':3600});}
   return reply({'user':{'public_id':'current','username':'current'}});
  }));
 });
}

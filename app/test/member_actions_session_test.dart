// Synthetic account changes only. No real reports, follows, blocks or messages.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/actions.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/chat_pages.dart';
http.Response reply(Object body,[int status=200])=>http.Response(jsonEncode(body),status);
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
Map<String,dynamic> person()=>{'public_id':'target','username':'target','name':'Private profile','following':false,'followers_count':2};
void retired(){expect(find.textContaining('another signed-in session'),findsOneWidget);expect(find.text('Private profile'),findsNothing);expect(find.text('Follow'),findsNothing);expect(find.text('Message'),findsNothing);}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final same in [false,true])for(final pending in [false,true]){
 testWidgets('member profile retires ${pending?'pending':'loaded'} after ${same?'same':'other'} login',(t)async{
  String owner='a';var reads=0,writes=0;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:UserProfilePage(session:s,username:'target')));await flush(t);
   if(!pending)expect(find.text('Private profile'),findsOneWidget);if(!same)owner='b';await s.login('fixture','not-a-password');await flush(t);retired();
   if(pending){response.complete(reply({'user':person()}));await flush(t);retired();}
   owner='a';await s.login('fixture','not-a-password');await flush(t);retired();expect(reads,1);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
   if(r.method!='GET')writes++;
   if(r.url.path.endsWith('/users/target')){reads++;return pending?response.future:reply({'user':person()});}
   return reply({'data':[],'next_cursor':null});
  }));
 });}
 testWidgets('member profile retires replacement Session with matching member and epoch',(t)async{
  await http.runWithClient(()async{
   final a=Session(),b=Session();await a.login('fixture','not-a-password');await b.login('fixture','not-a-password');expect(a.generation,b.generation);
   Widget page(Session s)=>MaterialApp(home:UserProfilePage(session:s,username:'target'));
   await t.pumpWidget(page(a));await flush(t);expect(find.text('Private profile'),findsOneWidget);await t.pumpWidget(page(b));await flush(t);retired();expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async=>r.url.path.endsWith('/oauth/token')?reply({'access_token':'fixture','expires_in':3600}):r.url.path.endsWith('/auth/me')?reply({'user':{'public_id':'a','username':'a'}}):r.url.path.endsWith('/users/target')?reply({'user':person()}):reply({'data':[],'next_cursor':null})));
 });
 for(final action in ['Follow','Message'])for(final fail in [false,true]){
 testWidgets('$action late ${fail?'error':'success'} cannot navigate or update another login',(t)async{
  var writes=0;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:UserProfilePage(session:s,username:'target')));await flush(t);
   await t.tap(find.text(action));await flush(t);expect(writes,1);await s.login('fixture','not-a-password');await flush(t);retired();
   response.complete(fail?reply({'message':'Old action error'},422):reply(action=='Message'?{'conversation':{'public_id':'old-conversation','type':'direct'}}:{}));await flush(t);retired();expect(find.byType(ChatPage),findsNothing);expect(find.text('Old action error'),findsNothing);expect(writes,1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});
   if(r.method!='GET'){writes++;return response.future;}return r.url.path.endsWith('/users/target')?reply({'user':person()}):reply({'data':[],'next_cursor':null});
  }));
 });}
 for(final action in ['report','block'])for(final same in [false,true]){
 testWidgets('$action dialog closes on ${same?'same':'other'} login without mutation',(t)async{
  String owner='a';var writes=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:(){if(action=='report'){reportFlow(c,s,'user','target');}else{blockFlow(c,s,'target');}},child:const Text('Open action'))))));
   await t.tap(find.text('Open action'));await flush(t);expect(find.byType(action=='report'?SimpleDialog:AlertDialog),findsOneWidget);
   if(!same)owner='b';await s.login('fixture','not-a-password');await flush(t);expect(find.byType(SimpleDialog),findsNothing);expect(find.byType(AlertDialog),findsNothing);owner='a';await s.login('fixture','not-a-password');await flush(t);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});writes++;return reply({});}));
 });}
 for(final action in ['report','block'])for(final fail in [false,true]){
 testWidgets('$action pending ${fail?'failure':'success'} never reports completion after retirement',(t)async{
  var writes=0;bool? blocked;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()async{if(action=='report'){await reportFlow(c,s,'user','target');}else{blocked=await blockFlow(c,s,'target');}},child:const Text('Open action'))))));
   await t.tap(find.text('Open action'));await flush(t);await t.tap(find.text(action=='report'?'Spam':'Block'));await flush(t);if(action=='report'){await t.tap(find.text('Send report'));await flush(t);}expect(writes,1);
   await s.login('fixture','not-a-password');await flush(t);response.complete(fail?reply({'message':'Old moderation error'},422):reply({}));await flush(t);expect(find.textContaining('is blocked.'),findsNothing);expect(find.text('Report submitted.'),findsNothing);expect(find.text('Old moderation error'),findsNothing);if(action=='block')expect(blocked,isFalse);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});writes++;return response.future;}));
 });}
 for(final action in ['report','block']){
 testWidgets('$action uses opening route ownership before confirmation',(t)async{
  var active=true,writes=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:(){if(action=='report'){reportFlow(c,s,'user','target',isActive:()=>active);}else{blockFlow(c,s,'target',isActive:()=>active);}},child:const Text('Open action'))))));
   await t.tap(find.text('Open action'));await flush(t);active=false;await t.tap(find.text(action=='report'?'Spam':'Block'));await flush(t);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});writes++;return reply({});}));
 });}
 for(final action in ['report','block'])for(final cancel in [false,true]){
 testWidgets('$action unchanged login ${cancel?'cancels cleanly':'completes once'}',(t)async{
  var writes=0;bool? blocked;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()async{if(action=='report'){await reportFlow(c,s,'user','target');}else{blocked=await blockFlow(c,s,'target');}},child:const Text('Open action'))))));
   await t.tap(find.text('Open action'));await flush(t);
   if(cancel){Navigator.of(t.element(find.byType(action=='report'?SimpleDialog:AlertDialog))).pop();}else{await t.tap(find.text(action=='report'?'Spam':'Block'));}
   await flush(t);if(!cancel&&action=='report'){await t.tap(find.text('Send report'));await flush(t);}expect(writes,cancel?0:1);if(action=='block')expect(blocked,!cancel);
   expect(find.textContaining('We review every report'),findsNothing);
   if(!cancel)expect(find.textContaining(action=='report'?'Report submitted.':'is blocked.'),findsOneWidget);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});writes++;expect(r.url.path,endsWith(action=='report'?'/reports':'/users/target/block'));return reply({});}));
 });}
 testWidgets('member profile permanently retires changed route target',(t)async{
  var reads=0;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');Widget page(String target)=>MaterialApp(home:UserProfilePage(session:s,username:target));
   await t.pumpWidget(page('target'));await flush(t);expect(find.text('Private profile'),findsOneWidget);
   await t.pumpWidget(page('other'));await flush(t);retired();await t.pumpWidget(page('target'));await flush(t);retired();expect(reads,1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});if(r.url.path.endsWith('/users/target')){reads++;return reply({'user':person()});}return reply({'data':[],'next_cursor':null});}));
 });

}

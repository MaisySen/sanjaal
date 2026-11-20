// Synthetic recipients and account changes, no real messages.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/share_post.dart';
http.Response reply(Object b,[int status=200])=>http.Response(jsonEncode(b),status);
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
Object recipients()=>{'data':[{'public_id':'private-chat','title':'Private chat recipient'}]};
void retired(){expect(find.textContaining('another signed-in session'),findsOneWidget);expect(find.text('Private chat recipient'),findsNothing);expect(find.byType(ListTile),findsNothing);}
Widget shell(Session s,{void Function()? closed})=>MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()async{await shareToChat(c,s,'post');closed?.call();},child:const Text('Open share')))));
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final same in [false,true])for(final pending in [false,true]){
 testWidgets('share ${pending?'pending':'loaded'} recipients retire after ${same?'same':'other'} login',(t)async{
  String owner='a';var reads=0,writes=0;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(shell(s));await t.tap(find.text('Open share'));await flush(t);expect(reads,1);
   if(!pending)expect(find.text('Private chat recipient'),findsOneWidget);if(!same)owner='b';await s.login('fixture','not-a-password');await flush(t);retired();
   if(pending){response.complete(reply(recipients()));await flush(t);retired();}
   owner='a';await s.login('fixture','not-a-password');await flush(t);retired();expect(reads,1);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});if(r.method!='GET')writes++;reads++;return pending?response.future:reply(recipients());}));
 });}
 for(final fail in [false,true]){
 testWidgets('share late ${fail?'failure':'success'} cannot close or notify another login',(t)async{
  var writes=0;var closed=false;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(shell(s,closed:()=>closed=true));await t.tap(find.text('Open share'));await flush(t);await t.tap(find.text('Private chat recipient'));await flush(t);expect(writes,1);
   await s.login('fixture','not-a-password');await flush(t);retired();response.complete(fail?reply({'message':'Old share error'},422):reply({}));await flush(t);retired();expect(closed,isFalse);expect(find.text('Old share error'),findsNothing);expect(find.textContaining('Sent to'),findsNothing);expect(writes,1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});if(r.method!='GET'){writes++;return response.future;}return reply(recipients());}));
 });}
 testWidgets('share unchanged login sends selected post once and closes',(t)async{
  var writes=0;var closed=false;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(shell(s,closed:()=>closed=true));await t.tap(find.text('Open share'));await flush(t);await t.tap(find.text('Private chat recipient'));await flush(t);expect(writes,1);expect(closed,isTrue);expect(find.textContaining('Sent to'),findsOneWidget);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});if(r.method!='GET'){writes++;expect(r.url.path,endsWith('/conversations/private-chat/messages'));expect(jsonDecode(r.body)['shared_post'],'post');return reply({});}return reply(recipients());}));
 });
}

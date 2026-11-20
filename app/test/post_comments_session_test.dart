// Synthetic post/comment ownership. No production reads, posts or deletions.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/post_page.dart';
http.Response reply(Object b,[int status=200])=>http.Response(jsonEncode(b),status);
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
Map<String,dynamic> comment()=>{'public_id':'comment','body':'Private old comment','author':{'public_id':'a','username':'a'},'created_at':'2026-11-21T00:00:00Z'};
Object rows(String page)=>page=='post'?{'post':{'public_id':'post','body':'Private old post','media':[],'author':{'public_id':'a','username':'a'}}}:{'data':[comment()],'next_cursor':null};
Widget page(String kind,Session s,{String target='post'})=>kind=='post'?PostPage(session:s,postId:target):Scaffold(body:CommentsSheet(session:s,postId:target,postAuthorId:'a'));
void retired(){expect(find.textContaining('another signed-in session'),findsOneWidget);expect(find.text('Private old comment'),findsNothing);expect(find.text('Private old post'),findsNothing);expect(find.byType(TextField),findsNothing);}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final kind in ['post','comments'])for(final same in [false,true])for(final pending in [false,true]){
 testWidgets('$kind retires ${pending?'pending':'loaded'} after ${same?'same':'other'} login',(t)async{
  String owner='a';var reads=0,writes=0;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:page(kind,s)));await flush(t);expect(reads,1);
   if(kind=='comments'&&!pending){await t.enterText(find.byType(TextField),'Private unsent reply');await t.tap(find.text('Reply'));await flush(t);}
   if(!same)owner='b';await s.login('fixture','not-a-password');await flush(t);retired();expect(find.text('Private unsent reply'),findsNothing);
   if(pending){response.complete(reply(rows(kind)));await flush(t);retired();}
   owner='a';await s.login('fixture','not-a-password');await flush(t);retired();expect(reads,1);expect(writes,0);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});if(r.method!='GET')writes++;reads++;return pending?response.future:reply(rows(kind));}));
 });}
 for(final kind in ['post','comments'])for(final replacement in [false,true]){
 testWidgets('$kind retires changed ${replacement?'Session':'post target'} permanently',(t)async{
  var reads=0;
  await http.runWithClient(()async{
   final a=Session(),b=Session();await a.login('fixture','not-a-password');await b.login('fixture','not-a-password');expect(a.generation,b.generation);
   Widget view(Session s,String target)=>MaterialApp(home:page(kind,s,target:target));
   await t.pumpWidget(view(a,'post'));await flush(t);await t.pumpWidget(view(replacement?b:a,replacement?'post':'other'));await flush(t);retired();await t.pumpWidget(view(a,'post'));await flush(t);retired();expect(reads,1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});reads++;return reply(rows(kind));}));
 });}
 for(final action in ['send','delete'])for(final fail in [false,true]){
 testWidgets('comments $action late ${fail?'failure':'success'} cannot mutate replacement login',(t)async{
  var writes=0;final response=Completer<http.Response>();
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:page('comments',s)));await flush(t);
   if(action=='send'){await t.enterText(find.byType(TextField),'Private pending send');await t.tap(find.byTooltip('Send comment'));}else{await t.tap(find.byTooltip('Delete'));}await flush(t);expect(writes,1);
   await s.login('fixture','not-a-password');await flush(t);retired();response.complete(fail?reply({'message':'Old comment error'},422):reply(action=='send'?{'comment':comment()}:{'deleted_count':1}));await flush(t);retired();expect(find.text('Comment posted.'),findsNothing);expect(find.text('Old comment error'),findsNothing);expect(writes,1);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});if(r.method!='GET'){writes++;return response.future;}return reply(rows('comments'));}));
 });}
 testWidgets('retired comments do not pop replacement route after draft confirmation',(t)async{
  var writes=0;int? closed;var completed=false;
  await http.runWithClient(()async{
   final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()async{closed=await showModalBottomSheet<int>(context:c,isScrollControlled:true,builder:(_)=>CommentsSheet(session:s,postId:'post',postAuthorId:'a'));completed=true;},child:const Text('Open'))))));
   await t.tap(find.text('Open'));await flush(t);await t.enterText(find.byType(TextField),'Private draft');await t.tap(find.byTooltip('Close comments'));await flush(t);expect(find.text('Discard this draft?'),findsOneWidget);
   await s.login('fixture','not-a-password');await flush(t);await t.tap(find.text('Discard'));await flush(t);retired();expect(completed,isFalse);expect(writes,0);await t.pageBack();await flush(t);expect(completed,isTrue);expect(closed,isNull);expect(find.text('Open'),findsOneWidget);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'a','username':'a'}});if(r.method!='GET')writes++;return reply(rows('comments'));}));
 });
}

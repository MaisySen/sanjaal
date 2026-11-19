// Synthetic HTTP only. Account replacement must retire old chat screens.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/main.dart' show buildTheme;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';

http.Response reply(Object data)=>http.Response(jsonEncode(data),200);
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 for(final same in [false,true])for(final screen in ['chat','new']){
  testWidgets('$screen rejects late private content after ${same?'same-member login':'other-member login'}',(t)async{
   final pending=Completer<http.Response>();
   var reads=0,writes=0;String owner='a';
   await http.runWithClient(()async{
    final session=Session();await session.login('fixture','not-a-password');
    await t.pumpWidget(MaterialApp(home:screen=='chat'?ChatPage(session:session,convo:{'public_id':'private-chat','type':'direct','title':'Old private thread'}):NewChatPage(session:session)));
    if(screen=='new')await t.enterText(find.byType(TextField),'old private query');
    await flush(t);expect(reads,1);
    if(!same)owner='b';
    await session.login('replacement','not-a-password');await flush(t);
    expect(find.textContaining('another signed-in session'),findsOneWidget);
    expect(find.byType(TextField),findsNothing);expect(find.text('Old private thread'),findsNothing);
    pending.complete(reply(screen=='chat'?{'data':[{'public_id':'old-message','body':'Late private content','sender':{'public_id':'a','username':'a'},'seq':1,'kind':'text','created_at':'2026-11-20T00:00:00Z'}]}:{'users':[{'public_id':'private-member','username':'late','name':'Late private content'}]}));
    await flush(t);await t.pump(const Duration(seconds:3));
    expect(find.text('Late private content'),findsNothing);expect(writes,0);expect(reads,1);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());
   },()=>MockClient((r)async{
    if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
    if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
    if(r.method=='GET'){reads++;return pending.future;}
    writes++;return reply({});
   }));
  });
 }
 for(final same in [true,false])for(final action in ['Rename group','Add people','Leave group']){
  testWidgets('${same?'same-member':'other-member'} replacement closes stale $action dialog without group mutation',(t)async{
   String owner='a';var writes=0;
   await http.runWithClient(()async{
    final session=Session();await session.login('fixture','not-a-password');
    await t.pumpWidget(MaterialApp(home:GroupInfoPage(session:session,convo:{'public_id':'old-group','type':'group','title':'Private group title','my_role':'owner','members':[{'public_id':'a','username':'a'},{'public_id':'private-person','username':'private-person'}]})));
    await flush(t);await t.tap(find.text(action));await flush(t);expect(find.byType(AlertDialog),findsOneWidget);
    if(!same)owner='b';await session.login('replacement','not-a-password');await flush(t);
    expect(find.byType(AlertDialog),findsNothing);expect(find.text('Private group title'),findsNothing);expect(find.text('@private-person'),findsNothing);
    expect(find.textContaining('another signed-in session'),findsOneWidget);expect(writes,0);expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());
   },()=>MockClient((r)async{
    if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
    if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
    writes++;return reply({});
   }));
  });
 }
 testWidgets('inbox immediately hides old conversation previews after account replacement',(t)async{
  String owner='a';var inboxReads=0;
  await http.runWithClient(()async{
   final session=Session();await session.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:ChatsPage(session:session)));
   await flush(t);expect(find.text('Private preview'),findsOneWidget);
   owner='b';await session.login('replacement','not-a-password');await flush(t);
   expect(find.text('Private preview'),findsNothing);expect(find.byTooltip('New chat'),findsNothing);
   await t.pump(const Duration(seconds:15));expect(inboxReads,1);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
   inboxReads++;return reply({'data':[{'public_id':'private-chat','type':'direct','title':'Private title','last_message':{'body':'Private preview','kind':'text','created_at':'2026-11-20T00:00:00Z'},'unread':0}]});
  }));
 });
 for(final same in [false,true]){
 testWidgets('inbox stale settings menu closes on ${same?'same':'other'} member login',(t)async{
  String owner='a';var writes=0;
  await http.runWithClient(()async{
   final session=Session();await session.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:ChatsPage(session:session)));await flush(t);
   await t.longPress(find.text('Private title'));await flush(t);expect(find.text('Pin to top'),findsOneWidget);
   if(!same)owner='b';await session.login('replacement','not-a-password');await flush(t);
   expect(find.text('Pin to top'),findsNothing);expect(find.text('Private title'),findsNothing);expect(writes,0);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
   if(r.method!='GET')writes++;
   return reply({'data':[{'public_id':'old','type':'direct','title':'Private title','unread':0}]});
  }));
 });}
 for(final lang in ['en','ne'])for(final dark in [false,true]){
 testWidgets('retired chat readable $lang dark=$dark large text',(t)async{
  prefs.lang=lang;
  final key=GlobalKey();
  t.view.physicalSize=const Size(390,844);t.view.devicePixelRatio=1;
  addTearDown((){t.view.resetPhysicalSize();t.view.resetDevicePixelRatio();prefs.lang='en';});
  await http.runWithClient(()async{
   final session=Session();await session.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(theme:buildTheme(dark?Brightness.dark:Brightness.light),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),home:RepaintBoundary(key:key,child:GroupInfoPage(session:session,convo:{'public_id':'old','title':'Private group','members':[]}))));
   await session.login('replacement','not-a-password');await flush(t);
   final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);
   final bytes=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();
   await t.runAsync(()async{final file=File('test/renders/chat_session_${lang}_${dark?'dark':'light'}.png');await file.parent.create(recursive:true);await file.writeAsBytes(bytes);});
   image.dispose();expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async=>r.url.path.endsWith('/oauth/token')?reply({'access_token':'fixture','expires_in':3600}):reply({'user':{'public_id':'a','username':'a'}})));
 });}
 testWidgets('old failed text retry and newer unsent composer disappear on account change',(t)async{
  final held=Completer<http.Response>();var reads=0,writes=0;String owner='a';
  await http.runWithClient(()async{
   final session=Session();await session.login('fixture','not-a-password');
   await t.pumpWidget(MaterialApp(home:ChatPage(session:session,convo:{'public_id':'old-chat','type':'direct','title':'Private'})));
   await flush(t);await t.enterText(find.byType(TextField),'Old failed body');await t.tap(find.byTooltip('Send message'));await flush(t);
   expect(writes,1);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsOneWidget);
   await t.enterText(find.byType(TextField),'Newer unsent secret');
   owner='b';await session.login('replacement','not-a-password');await flush(t);
   expect(find.text('Old failed body'),findsNothing);expect(find.text('Newer unsent secret'),findsNothing);expect(find.byTooltip('Send message'),findsNothing);
   held.complete(reply({'data':[]}));await flush(t);expect(writes,1);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  },()=>MockClient((r)async{
   if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});
   if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':owner,'username':owner}});
   if(r.url.path.endsWith('/typing')||r.url.path.endsWith('/read'))return reply({});
   if(r.method=='GET')return ++reads==1?reply({'data':[]}):held.future;
   writes++;return http.Response(jsonEncode({'message':'Synthetic unavailable'}),503);
  }));
 });
}

// Offline request/capture boundaries. No real calls, rooms, gifts or money.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/call_page.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/gifts.dart';
import 'package:sanjaal/session_bound_state.dart';
import 'package:sanjaal/call_lifecycle.dart';
import 'package:sanjaal/room_lifecycle.dart';
class FixtureSession extends Session {
 String owner='a';final requests=<String>[];
 late Future<dynamic> Function(String,String) response;
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
  if(path=='/auth/me')return {'user':{'public_id':owner,'username':owner}};
  requests.add('$method $path');return response(method,path);
 }
}
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
class OwnedSetup extends StatefulWidget{
 const OwnedSetup({super.key,required this.session,required this.gate,required this.steps,required this.room});
 final Session session;final Completer<void> gate;final List<String> steps;final bool room;
 @override State<OwnedSetup> createState()=>_OwnedSetupState();
}
class _OwnedSetupState extends State<OwnedSetup> with SessionBoundState<OwnedSetup>{
 @override Session get viewSession=>widget.session;
 @override void initState(){super.initState();
  Future<void> step(String name)async{widget.steps.add(name);if(name=='connect')await widget.gate.future;}
  if(widget.room){connectRoomWhileActive(isActive:()=>sessionActive,requestToken:()=>step('token'),connect:()=>step('connect'),prepareMicrophone:()=>step('microphone'));}
  else{connectCallWhileActive(isActive:()=>sessionActive,requestToken:()=>step('token'),connect:()=>step('connect'),microphone:()=>step('microphone'),camera:()=>step('camera'),video:true);}
 }
 @override void sessionRetired(){widget.steps.add('close');}
 @override Widget build(BuildContext c)=>sessionActive?const SizedBox():retiredSessionView();
}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 Future<void> setup(Future<void> Function(FixtureSession) work)async{
  await http.runWithClient(()async{final s=FixtureSession();await s.login('fixture','not-a-password');await work(s);},()=>MockClient((_)async=>http.Response(jsonEncode({'access_token':'fixture','expires_in':3600}),200)));
 }
 testWidgets('pending failed replacement login immediately retires capture ownership',(t)async{
  var grants=0;final auth=Completer<http.Response>();final gate=Completer<void>();final steps=<String>[];
  await http.runWithClient(()async{
   final s=FixtureSession();await s.login('first','not-a-password');
   await t.pumpWidget(MaterialApp(home:OwnedSetup(session:s,gate:gate,steps:steps,room:false)));await flush(t);
   final replacement=s.login('replacement','not-a-password');
   final rejected=expectLater(replacement,throwsA(isA<ApiError>()));await flush(t);
   expect(steps,['token','connect','close']);expect(find.textContaining('another signed-in session'),findsOneWidget);
   gate.complete();auth.complete(http.Response(jsonEncode({'error_description':'Synthetic rejection'}),403));await rejected;await flush(t);
   expect(steps,['token','connect','close']);expect(find.textContaining('another signed-in session'),findsOneWidget);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  },()=>MockClient((_)async=>++grants==1?http.Response(jsonEncode({'access_token':'fixture','expires_in':3600}),200):auth.future));
 });
 for(final same in [false,true])for(final page in ['calls','rooms','incoming','call','room']){
 testWidgets('$page drops late account data on ${same?'same':'other'} member replacement',(t)async{
  final pending=Completer<dynamic>();
  await setup((s)async{
   s.response=(m,p)=>pending.future;
   final home=switch(page){
    'calls'=>CallsPage(session:s),'rooms'=>RoomsPage(session:s),
    'incoming'=>IncomingCallPage(session:s,call:{'public_id':'old-call','conversation_id':'old-convo','caller':{'name':'Private caller'},'kind':'voice'}),
    'call'=>CallPage(session:s,conversationId:'old-convo',title:'Private call',video:true),
    _=>RoomPage(session:s,roomId:'old-room'),
   };
   await t.pumpWidget(MaterialApp(home:home));await flush(t);
   if(page=='incoming'){await t.tap(find.byTooltip('Accept'));await flush(t);}
   expect(s.requests.length,1);
   if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
   expect(find.textContaining('another signed-in session'),findsOneWidget);
   expect(find.text('Private caller'),findsNothing);expect(find.text('Private call'),findsNothing);
   pending.complete(page=='calls'?{'data':[{'conversation_id':'late','created_at':'2026-11-20','duration_s':1,'title':'Late private call'}]}:page=='rooms'?{'data':[{'public_id':'late','title':'Late private room'}]}:<String,dynamic>{});
   await flush(t);expect(s.requests.length,1);expect(find.text('Late private call'),findsNothing);expect(find.text('Late private room'),findsNothing);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());await flush(t);expect(s.requests.length,1);
  });
 });}
 for(final same in [false,true]){
 testWidgets('room title dialog cannot start with replacement ${same?'same':'other'} member',(t)async{
  await setup((s)async{
   s.response=(m,p)async=>{'data':[]};
   await t.pumpWidget(MaterialApp(home:RoomsPage(session:s)));await flush(t);
   await t.tap(find.text('Go live').first);await flush(t);await t.enterText(find.byType(TextField),'Private room title');
   if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
   expect(find.byType(AlertDialog),findsNothing);expect(find.text('Private room title'),findsNothing);expect(s.requests,['GET /rooms']);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  });
 });
 testWidgets('gift sheet stops chained balance read after ${same?'same':'other'} replacement',(t)async{
  final pending=Completer<dynamic>();
  await setup((s)async{
   s.response=(m,p)=>pending.future;
   await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showGiftSheet(context,s,'old','private-recipient'),child:const Text('Open gift'))))));
   await t.tap(find.text('Open gift'));await flush(t);expect(s.requests,['GET /gifts']);
   if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);
   pending.complete({'data':[{'key':'rose','name':'Rose','coins':1}]});await flush(t);
   expect(s.requests,['GET /gifts']);expect(find.textContaining('private-recipient'),findsNothing);expect(find.text('Rose'),findsNothing);expect(t.takeException(),isNull);
   await t.pumpWidget(const SizedBox());
  });
 });
 for(final room in [false,true])testWidgets('${room?'room':'call'} ownership closes before pending connect can open microphone same=$same',(t)async{
  final gate=Completer<void>();final steps=<String>[];
  await setup((s)async{
   await t.pumpWidget(MaterialApp(home:OwnedSetup(session:s,gate:gate,steps:steps,room:room)));await flush(t);expect(steps,['token','connect']);
   if(!same)s.owner='b';await s.login('replacement','not-a-password');await flush(t);expect(steps,['token','connect','close']);
   gate.complete();await flush(t);expect(steps,['token','connect','close']);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());
  });
 });
 }
}

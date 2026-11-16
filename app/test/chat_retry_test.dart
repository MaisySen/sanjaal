// In-memory chat delivery recovery against synthetic HTTP. No live/device evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:shared_preferences/shared_preferences.dart';
http.Response json(Object body,[int code=200])=>http.Response(jsonEncode(body),code,headers:{'content-type':'application/json; charset=utf-8'});
Map<String,dynamic> message(String id,String body,{String? cid,Map<String,dynamic>? reply})=>{'public_id':id,'body':body,'client_id':cid,'sender':{'public_id':'me','username':'fixture'},'created_at':'2026-11-17T00:00:00Z','kind':'text','seq':id=='root'?1:2,if(reply!=null)'reply_to':reply};
Future<void> flush(WidgetTester t)async{await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:25)));await t.pump();await t.pump(const Duration(milliseconds:400));}
Future<void> fixture(WidgetTester t,Future<http.Response> Function(http.Request) api,Future<void> Function() run,{Brightness brightness=Brightness.light,String language='en',double scale=1,double keyboard=0})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=language;addTearDown(()=>prefs.lang='en');await http.runWithClient(()async{
  final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(RepaintBoundary(key:const ValueKey('chat-retry-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale),viewInsets:EdgeInsets.only(bottom:keyboard)),child:w!),home:ChatPage(session:s,convo:{'public_id':'chat','type':'direct','title':'Asha'}))));await flush(t);await run();await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:3));
 },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return json({'user':{'public_id':'me','username':'fixture'}});if(r.url.path.endsWith('/typing')||r.url.path.endsWith('/read'))return json({});return api(r);}));
}
void main(){
 setUpAll(()async{
  for(final pair in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(pair.$2);if(f.existsSync()){final l=FontLoader(pair.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}
 });

 for(final failure in ['rejected','lost','malformed']){
 testWidgets('$failure retry preserves client id original body reply and newer composer',(t)async{
  final requests=<Map<String,dynamic>>[];final held=Completer<http.Response>();var reads=0;
  await fixture(t,(r)async{
   if(r.method=='GET')return ++reads==1?json({'data':[message('root','Original question')],'typing':[]}):held.future;
   final b=(jsonDecode(r.body) as Map).cast<String,dynamic>();requests.add(b);
   if(requests.length==1){if(failure=='lost')throw const SocketException('Fixture response lost');if(failure=='malformed')return json({'message':{}});return json({'message':'Fixture rejected'},503);}
   return json({'message':message('delivered',b['body'],cid:b['client_id'],reply:{'public_id':'root','body':'Original question','sender':'fixture','kind':'text'})});
  },()async{
   await t.longPress(find.text('Original question').first);await flush(t);await t.tap(find.text('Reply'));await flush(t);
   await t.enterText(find.byType(TextField),'Retry this reply');await t.tap(find.byTooltip('Send message'));await flush(t);expect(requests.length,1);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsOneWidget);
   await t.longPress(find.text('Original question').first);await flush(t);await t.tap(find.text('Reply'));await flush(t);await t.enterText(find.byType(TextField),'Newer unsent draft');
   await t.tap(find.text('Delivery unconfirmed. Tap to retry.'));await flush(t);
   expect(requests.length,2);expect(requests[1],requests[0]);expect(requests[1]['reply_to'],'root');expect(find.text('Newer unsent draft'),findsOneWidget);expect(find.textContaining('Replying to @fixture:'),findsOneWidget);expect(find.text('Retry this reply'),findsOneWidget);
   held.complete(json({'data':[],'typing':[]}));
  });
 });}
 testWidgets('multiple taps during retry issue only one request',(t)async{
  final pending=Completer<http.Response>();final held=Completer<http.Response>();var reads=0,writes=0;String? cid;
  await fixture(t,(r)async{if(r.method=='GET')return ++reads==1?json({'data':[]}):held.future;cid=jsonDecode(r.body)['client_id'];return ++writes==1?json({'message':'Fixture unavailable'},503):pending.future;},()async{
   await t.enterText(find.byType(TextField),'Send once');await t.tap(find.byTooltip('Send message'));await flush(t);await t.tap(find.text('Delivery unconfirmed. Tap to retry.'));await t.pump();await t.tap(find.text('Send once'));await flush(t);expect(writes,2);
   pending.complete(json({'message':message('delivered','Send once',cid:cid)}));await flush(t);expect(find.text('Send once'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('poll confirmation removes a failed local copy without an extra send',(t)async{
  final poll=Completer<http.Response>();final held=Completer<http.Response>();var reads=0,writes=0;String? cid;
  await fixture(t,(r)async{if(r.method=='GET'){reads++;return reads==1?json({'data':[]}):reads==2?poll.future:held.future;}writes++;cid=jsonDecode(r.body)['client_id'];throw const SocketException('Fixture committed then lost');},()async{
   await t.enterText(find.byType(TextField),'Committed once');await t.tap(find.byTooltip('Send message'));await flush(t);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsOneWidget);
   await t.enterText(find.byType(TextField),'Still drafting');poll.complete(json({'data':[message('delivered','Committed once',cid:cid)]}));await flush(t);
   expect(find.text('Committed once'),findsOneWidget);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsNothing);expect(find.text('Still drafting'),findsOneWidget);expect(writes,1);held.complete(json({'data':[]}));
  });
 });
 testWidgets('poll arriving before lost-response error cannot downgrade confirmed delivery',(t)async{
  final poll=Completer<http.Response>(),send=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;String? cid;
  await fixture(t,(r)async{if(r.method=='GET')return ++reads==1?json({'data':[]}):reads==2?poll.future:held.future;cid=jsonDecode(r.body)['client_id'];return send.future;},()async{
   await t.enterText(find.byType(TextField),'Confirmed first');await t.tap(find.byTooltip('Send message'));await flush(t);poll.complete(json({'data':[message('delivered','Confirmed first',cid:cid)]}));await flush(t);send.completeError(const SocketException('Late loss'));await flush(t);
   expect(find.text('Confirmed first'),findsOneWidget);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsNothing);held.complete(json({'data':[]}));
  });
 });
 testWidgets('removed original stops retry without replacing the composer',(t)async{
  var reads=0;final held=Completer<http.Response>();await fixture(t,(r)async=>r.method=='GET'?(++reads==1?json({'data':[]}):held.future):json({'message':'The original message is no longer available.'},410),()async{
   await t.enterText(find.byType(TextField),'Removed message');await t.tap(find.byTooltip('Send message'));await flush(t);await t.enterText(find.byType(TextField),'New draft');expect(find.text('Original message unavailable.'),findsOneWidget);await t.tap(find.text('Removed message'));await flush(t);expect(find.text('New draft'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('late send after forced disposal never uses a disposed input',(t)async{
  final send=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;String? cid;
  await fixture(t,(r)async{if(r.method=='GET')return ++reads==1?json({'data':[]}):held.future;cid=jsonDecode(r.body)['client_id'];return send.future;},()async{
   await t.enterText(find.byType(TextField),'Pending');await t.tap(find.byTooltip('Send message'));await flush(t);await t.pumpWidget(const SizedBox());send.complete(json({'message':message('delivered','Pending',cid:cid)}));held.complete(json({'data':[]}));await flush(t);expect(t.takeException(),isNull);
  });
 });
 testWidgets('another sender using the same client id cannot acknowledge a local message',(t)async{
  final poll=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;String? cid;
  await fixture(t,(r)async{if(r.method=='GET')return ++reads==1?json({'data':[]}):reads==2?poll.future:held.future;cid=jsonDecode(r.body)['client_id'];throw const SocketException('Fixture loss');},()async{
   await t.enterText(find.byType(TextField),'My original');await t.tap(find.byTooltip('Send message'));await flush(t);
   final other={...message('other','Their message',cid:cid),'sender':{'public_id':'other','username':'bina'}};poll.complete(json({'data':[other]}));await flush(t);
   expect(find.text('My original'),findsOneWidget);expect(find.text('Their message'),findsOneWidget);expect(find.text('Delivery unconfirmed. Tap to retry.'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });


 testWidgets('out of order send responses retain canonical message order',(t)async{
  final first=Completer<http.Response>(),second=Completer<http.Response>(),held=Completer<http.Response>();final keys=<String>[];var reads=0;
  await fixture(t,(r)async{if(r.method=='GET')return ++reads==1?json({'data':[]}):held.future;keys.add(jsonDecode(r.body)['client_id']);return keys.length==1?first.future:second.future;},()async{
   await t.enterText(find.byType(TextField),'First sent');await t.tap(find.byTooltip('Send message'));await flush(t);await t.enterText(find.byType(TextField),'Second sent');await t.tap(find.byTooltip('Send message'));await flush(t);
   second.complete(json({'message':{...message('second','Second sent',cid:keys[1]),'seq':3}}));await flush(t);first.complete(json({'message':{...message('first','First sent',cid:keys[0]),'seq':2}}));await flush(t);
   expect(t.getTopLeft(find.text('First sent')).dy,lessThan(t.getTopLeft(find.text('Second sent')).dy));held.complete(json({'data':[]}));
  });
 });

 testWidgets('initial read failure retries without losing composer text',(t)async{
  final held=Completer<http.Response>();var reads=0;
  await fixture(t,(r)async=>++reads==1?json({'message':'Fixture read failed'},503):reads==2?json({'data':[message('root','Loaded after retry')]}):held.future,()async{
   expect(find.text('Fixture read failed'),findsOneWidget);await t.enterText(find.byType(TextField),'Draft before retry');await t.tap(find.text('Try again'));await flush(t);
   expect(find.text('Loaded after retry'),findsOneWidget);expect(find.text('Draft before retry'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('unreadable poll response is recoverable and retains messages',(t)async{
  final poll=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;
  await fixture(t,(r)async=>++reads==1?json({'data':[message('root','Kept conversation')]}):reads==2?poll.future:held.future,()async{
   poll.complete(json({'data':'malformed'}));await flush(t);expect(find.text('Kept conversation'),findsOneWidget);expect(find.text('Messages could not be loaded.'),findsOneWidget);
   held.complete(json({'data':[]}));await t.pump(const Duration(seconds:3));await flush(t);expect(find.text('Messages could not be loaded.'),findsNothing);
  });
 });
 for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
  testWidgets('chat retry keeps newer draft visible $lang ${b.name}',(t)async{
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
   final held=Completer<http.Response>();var reads=0;
   await fixture(t,(r)async=>r.method=='GET'?(++reads==1?json({'data':[]}):held.future):json({'message':'Fixture connection lost'},503),()async{
    await t.enterText(find.byType(TextField),lang=='ne'?'भोलि भेटौँला।':'See you tomorrow.');await t.tap(find.byTooltip('Send message'));await flush(t);await t.enterText(find.byType(TextField),lang=='ne'?'यो नयाँ मस्यौदा हो।':'This is a newer draft.');await flush(t);await t.pump(const Duration(seconds:5));await flush(t);expect(t.takeException(),isNull);
    await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('chat-retry-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_retry_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});held.complete(json({'data':[]}));
   },brightness:b,language:lang,scale:1.8,keyboard:240);
  });
 }}

}

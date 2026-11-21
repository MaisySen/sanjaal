// Synthetic history paging/reading-position regression. No live/device evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';
http.Response json(Object b,[int status=200])=>http.Response(jsonEncode(b),status,headers:{'content-type':'application/json; charset=utf-8'});
Map<String,dynamic> msg(int i)=>{'public_id':'m$i','seq':i,'body':'Message $i: ${i%3==0?'A longer conversation with several lines to exercise variable-height history.':'Community plans.'}','kind':'text','sender':{'public_id':'asha','username':'asha'},'created_at':'2026-11-17T00:00:00Z'};
List<Map<String,dynamic>> page(int start,int end)=>[for(var i=start;i<=end;i++)msg(i)];
Future<void> flush(WidgetTester t)async{await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:25)));await t.pump();await t.pump(const Duration(milliseconds:400));await t.pump();}
ScrollController ctl(WidgetTester t)=>t.widget<CustomScrollView>(find.byKey(const ValueKey('chat-history-scroll'))).controller!;
Future<void> top(WidgetTester t)async{final c=ctl(t);c.jumpTo(c.position.minScrollExtent);await t.pump();await t.pump();}
Future<void> fixture(WidgetTester t,Future<http.Response> Function(http.Request) api,Future<void> Function() run,{Brightness brightness=Brightness.light,String lang='en',double scale=1})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=lang;addTearDown(()=>prefs.lang='en');
 await http.runWithClient(()async{final s=Session();await s.login('fixture','not-a-password');await t.pumpWidget(RepaintBoundary(key:const ValueKey('history-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:ChatPage(session:s,convo:{'public_id':'chat','type':'direct','title':'Asha'}))));await flush(t);await run();await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:3));},()=>MockClient((r)async{
  if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return json({'user':{'public_id':'me','username':'fixture'}});if(r.url.path.endsWith('/read')||r.url.path.endsWith('/typing'))return json({});return api(r);
 }));
}
void main(){
 setUpAll(()async{for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(p.$2);if(f.existsSync()){final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}});
 for(final language in ['en','ne']){
 testWidgets('foreign private photo stays unavailable without a credentialed image $language',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(r)async=>json({'data':[{
   ...msg(1),'body':'','kind':'image','media_url':'https://unrelated.invalid/private.jpg',
  }]}),()async{
   expect(find.text(language=='ne'?'यो तस्बिर उपलब्ध छैन।':'This photo is unavailable.'),findsOneWidget);
   expect(t.widgetList<Image>(find.byType(Image)).where((w)=>w.image is NetworkImage && (w.image as NetworkImage).url=='https://unrelated.invalid/private.jpg'),isEmpty);
   expect(t.takeException(),isNull);
   await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('history-shot')));final image=await b.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/chat_private_photo_unavailable_${language}_1.8.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  },lang:language,brightness:Brightness.dark,scale:1.8);
 });
 }
 testWidgets('history loads only on request and retries the same cursor with draft intact',(t)async{
  final held=Completer<http.Response>();final cursors=<String>[];var fail=true;
  await fixture(t,(r)async{final before=r.url.queryParameters['before_seq'];if(before!=null){cursors.add(before);if(fail){fail=false;return json({'message':'Fixture older read failed'},503);}return json({'data':page(1,50)});}if(r.url.queryParameters.containsKey('after_seq'))return held.future;return json({'data':page(51,100)});},()async{
   expect(cursors,isEmpty);expect(find.text(msg(100)['body']),findsOneWidget);await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);expect(cursors,['51']);expect(find.text('Could not load this. Try again.'),findsOneWidget);
   await t.enterText(find.byType(TextField),'Draft while paging');await t.tap(find.text('Try again'));await flush(t);expect(cursors,['51','51']);expect(find.text('Draft while paging'),findsOneWidget);await top(t);expect(find.text(msg(1)['body']),findsOneWidget);expect(find.text('Load earlier messages'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('prepend preserves current message geometry even when a poll arrives in flight',(t)async{
  final old=Completer<http.Response>(),poll=Completer<http.Response>(),held=Completer<http.Response>();var polls=0;
  await fixture(t,(r)async{if(r.url.queryParameters.containsKey('before_seq'))return old.future;if(r.url.queryParameters.containsKey('after_seq'))return ++polls==1?poll.future:held.future;return json({'data':page(51,100)});},()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);final c=ctl(t);c.jumpTo(120);await t.pump();final anchor=find.text(msg(53)['body']);expect(anchor,findsOneWidget);final y=t.getTopLeft(anchor).dy;
   poll.complete(json({'data':[msg(101)]}));await flush(t);expect(t.getTopLeft(anchor).dy,closeTo(y,1));expect(find.text('New messages'),findsOneWidget);
   old.complete(json({'data':page(1,50)}));await flush(t);expect(t.getTopLeft(anchor).dy,closeTo(y,1));
   await t.tap(find.text('New messages'));await flush(t);expect(find.text(msg(101)['body']),findsOneWidget);expect(find.text('New messages'),findsNothing);held.complete(json({'data':[]}));
  });
 });
 testWidgets('incoming follows bottom but never pulls a reader away from older content',(t)async{
  final poll=Completer<http.Response>(),held=Completer<http.Response>();var polls=0;
  await fixture(t,(r)async=>r.url.queryParameters.containsKey('after_seq')?(++polls==1?poll.future:held.future):json({'data':page(51,100)}),()async{
   final c=ctl(t);expect(c.position.extentAfter,lessThan(2));poll.complete(json({'data':[msg(101)]}));await flush(t);expect(c.position.extentAfter,lessThan(2));expect(find.text(msg(101)['body']),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('short older page ends pagination and overlapping taps are ignored',(t)async{
  final old=Completer<http.Response>(),held=Completer<http.Response>();var reads=0;
  await fixture(t,(r)async{if(r.url.queryParameters.containsKey('before_seq')){reads++;return old.future;}return r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)});},()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await t.pump();await top(t);expect(reads,1);old.complete(json({'data':page(40,50)}));await flush(t);await top(t);expect(find.text('Load earlier messages'),findsNothing);expect(find.text('Start of conversation'),findsOneWidget);expect(find.text(msg(40)['body']),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('malformed older page retains cursor and loaded conversation',(t)async{
  final held=Completer<http.Response>();final cursors=<String>[];
  await fixture(t,(r)async{final before=r.url.queryParameters['before_seq'];if(before!=null){cursors.add(before);return cursors.length==1?json({'data':[msg(80)]}):json({'data':[]});}return r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)});},()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);expect(find.text('Earlier messages could not be loaded.'),findsOneWidget);await t.tap(find.text('Try again'));await flush(t);expect(cursors,['51','51']);await top(t);expect(find.text('Start of conversation'),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('a second prepend preserves a negative-offset anchor inside already loaded history',(t)async{
  final second=Completer<http.Response>(),held=Completer<http.Response>();final cursors=<String>[];
  await fixture(t,(r)async{final before=r.url.queryParameters['before_seq'];if(before!=null){cursors.add(before);return cursors.length==1?json({'data':page(51,100)}):second.future;}return r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(101,150)});},()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);
   final c=ctl(t);c.jumpTo(c.position.minScrollExtent+200);await t.pump();final candidates=find.text(msg(53)['body']);expect(candidates,findsOneWidget);final y=t.getTopLeft(candidates).dy;
   second.complete(json({'data':page(1,50)}));await flush(t);expect(t.getTopLeft(candidates).dy,closeTo(y,1));expect(cursors,['101','51']);held.complete(json({'data':[]}));
  });
 });
 testWidgets('page merge ignores duplicate IDs without showing a message twice',(t)async{
  final held=Completer<http.Response>();await fixture(t,(r)async=>r.url.queryParameters.containsKey('before_seq')?json({'data':[msg(49),msg(49),msg(50)]}):r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)}),()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);await top(t);expect(find.text(msg(49)['body']),findsOneWidget);expect(find.text(msg(50)['body']),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('sending before initial history resolves cannot replace the latest-page request',(t)async{
  final initial=Completer<http.Response>(),held=Completer<http.Response>();final reads=<Map<String,String>>[];
  await fixture(t,(r)async{if(r.method=='POST'&&r.url.path.endsWith('/messages')){final b=jsonDecode(r.body);return json({'message':{...msg(101),'body':b['body'],'client_id':b['client_id'],'sender':{'public_id':'me','username':'fixture'}}});}reads.add(r.url.queryParameters);return reads.length==1?initial.future:held.future;},()async{
   await t.enterText(find.byType(TextField),'Send before history');await t.tap(find.byTooltip('Send message'));await flush(t);initial.complete(json({'data':page(51,100)}));await flush(t);expect(find.text('Send before history'),findsOneWidget);expect(reads.first, isEmpty);await top(t);expect(find.text('Load earlier messages'),findsOneWidget);expect(find.text(msg(51)['body']),findsOneWidget);held.complete(json({'data':[]}));
  });
 });
 testWidgets('send completion respects a reader who scrolled away during the request',(t)async{
  final sent=Completer<http.Response>(),held=Completer<http.Response>();String? client;
  await fixture(t,(r)async{if(r.method=='POST'&&r.url.path.endsWith('/messages')){client=jsonDecode(r.body)['client_id'];return sent.future;}return r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)});},()async{
   await t.enterText(find.byType(TextField),'Still sending');await t.tap(find.byTooltip('Send message'));await flush(t);await top(t);final anchor=find.text(msg(51)['body']);final y=t.getTopLeft(anchor).dy;
   sent.complete(json({'message':{...msg(101),'body':'Still sending','client_id':client,'sender':{'public_id':'me','username':'fixture'}}}));await flush(t);expect(t.getTopLeft(anchor).dy,closeTo(y,1));held.complete(json({'data':[]}));
  });
 });
 testWidgets('late older completion after disposal is safe',(t)async{
  final old=Completer<http.Response>(),held=Completer<http.Response>();await fixture(t,(r)async=>r.url.queryParameters.containsKey('before_seq')?old.future:r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)}),()async{
   await top(t);await t.tap(find.text('Load earlier messages'));await flush(t);await t.pumpWidget(const SizedBox());old.complete(json({'data':page(1,50)}));held.complete(json({'data':[]}));await flush(t);expect(t.takeException(),isNull);
  });
 });
 for(final lang in ['en','ne']){for(final b in [Brightness.light,Brightness.dark]){
  testWidgets('history retry layout $lang ${b.name}',(t)async{
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final held=Completer<http.Response>();
   await fixture(t,(r)async=>r.url.queryParameters.containsKey('before_seq')?json({'message':lang=='ne'?'अघिल्ला सन्देशहरू लोड हुन सकेनन्।':'Earlier messages could not be loaded.'},503):r.url.queryParameters.containsKey('after_seq')?held.future:json({'data':page(51,100)}),()async{
    await top(t);await t.tap(find.text(lang=='ne'?'अघिल्ला सन्देशहरू हेर्नुहोस्':'Load earlier messages'));await flush(t);await top(t);expect(t.takeException(),isNull);
    await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('history-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_history_${lang}_${b.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});held.complete(json({'data':[]}));
   },brightness:b,lang:lang,scale:1.8);
  });
 }}
}

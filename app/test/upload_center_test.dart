// Synthetic HTTP/files only. No live post, notification or device upload.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/upload_center.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/wallet_page.dart';
import 'package:sanjaal/stories_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object value, [int status = 200]) => http.Response(jsonEncode(value), status);
Map<String,dynamic> post(String id) => {'public_id':id,'kind':'post','body':'Confirmed $id','media':[], 'author':{'public_id':'me','username':'fixture'},'likes_count':0,'comments_count':0};
Future<void> flush(WidgetTester t) async { for(var i=0;i<3;i++) { await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await t.pump(const Duration(milliseconds:150)); } }
Future<void> fixture(WidgetTester t, Future<void> Function(Session,UploadCenter) run, {Future<http.Response> Function(http.Request)? respond, bool safe=true}) async {
 SharedPreferences.setMockInitialValues({});
 await http.runWithClient(() async { final s=Session();await s.login('fixture','not-a-password');final center=UploadCenter.of(s);await flush(t);await run(s,center);await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:4)); },()=>MockClient((r) async {
  if(r.url.path.endsWith('/oauth/token'))return json({'access_token':'fixture','expires_in':3600});
  if(r.url.path.endsWith('/auth/me'))return json({'user':{'public_id':'me','username':'fixture'},'features':{'upload_intents':safe}});
  return respond==null?json({'data':[],'next_cursor':null,'balance':0,'entries':[],'unread_messages':0}):respond(r);
 }));
}
void main(){
 setUpAll(()async{
    // This file must run first or alone from a clean checkout. Never rely on
    // another concurrently running test to create our screenshot directory.
    Directory('test/renders').createSync(recursive:true);
    for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final f=File(p.$2);if(f.existsSync()){final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await l.load();}}
 });

 testWidgets('normal phone progress strip stays small and leaves content usable',(t)async{
  t.view.physicalSize=const Size(360,800);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  final reply=Completer<Map<String,dynamic>>();
  await fixture(t,(s,c)async{
   var taps=0;
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('busy-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),home:Scaffold(body:Column(children:[UploadStrip(center:c),Expanded(child:Center(child:FilledButton(onPressed:()=>taps++,child:Text('Continue using app'))))])))));await flush(t);
   c.start('post',()=>reply.future);await flush(t);c.sending();s.uploadProgress.value=0.45;await flush(t);
   expect(t.getSize(find.byType(UploadStrip)).height,lessThanOrEqualTo(64));
   expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,0.45);
   await t.tap(find.text('Continue using app'));expect(taps,1);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('busy-review')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/upload_strip_busy_normal.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   reply.complete(post('normal'));await flush(t);expect(c.result?['public_id'],'normal');expect(t.takeException(),isNull);
  });
 });
 for(final language in ['en','ne']){
 testWidgets('persistent upload strip fits narrow phone and large text $language',(t)async{
  prefs.lang=language;addTearDown(()=>prefs.lang='en');
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('strip-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:Scaffold(body:Column(children:[UploadStrip(center:c),Expanded(child:Center(child:Text('Synthetic content')))])))));await flush(t);
   c.start('post',()async=>throw UploadError('A recoverable upload failed. Retry the same original.',resourceId:'original'));await flush(t);
   expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('strip-review')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/upload_strip_$language.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  });
 });
 }
 for(final language in ['en','ne']){
 testWidgets('unknown-result details stay readable and hide on account change $language',(t)async{
  prefs.lang=language;addTearDown(()=>prefs.lang='en');
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await fixture(t,(s,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('details-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:Scaffold(body:Column(children:[UploadStrip(center:c),const Expanded(child:Center(child:Text('Synthetic content')))])))));await flush(t);
   c.start('post',()async=>throw UploadError('The upload result is unknown. Check your posts or stories before sharing again.',uncertain:true));await flush(t);
   expect(c.canRetry,isFalse);expect(t.takeException(),isNull);
   await t.tap(find.text(language=='ne'?'विवरण':'Details'));await t.pumpAndSettle();
   expect(find.byType(AlertDialog),findsOneWidget);
   final dialogText=t.widget<Text>(find.descendant(of:find.byType(AlertDialog),matching:find.byType(Text)).at(1));
   expect(dialogText.maxLines,isNull);expect(dialogText.data,language=='ne'?'अपलोडको नतिजा थाहा भएन। फेरि साझा गर्नुअघि आफ्ना पोस्ट वा स्टोरी जाँच्नुहोस्।':'The upload result is unknown. Check your posts or stories before sharing again.');
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('details-review')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/upload_details_${language}_1.8.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   s.user={'public_id':'different','username':'other'};s.notifyListeners();await t.pump();
   expect(find.text(dialogText.data!),findsNothing);expect(t.takeException(),isNull);
  });
 });
 }
 testWidgets('delayed open-original story cannot navigate across an account change',(t)async{
  final reply=Completer<http.Response>();var reads=0;
  await fixture(t,(s,c)async{
   late BuildContext page;
   await t.pumpWidget(MaterialApp(home:Builder(builder:(context){page=context;return const Scaffold(body:Text('Current screen'));})));await flush(t);
   c.start('story',()async=>{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image'});await flush(t);
   final opening=c.openOriginal(page);await flush(t);await c.openOriginal(page);expect(reads,1);expect(c.openingOriginal,isTrue);
   s.user={'public_id':'different','username':'other'};s.notifyListeners();
   reply.complete(json({'data':[{'author':{'public_id':'me','username':'fixture'},'items':[{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image'}]}]}));await opening;await flush(t);
   expect(find.byType(StoryViewer),findsNothing);expect(find.text('Current screen'),findsOneWidget);expect(t.takeException(),isNull);
  },respond:(r)async{reads++;return reply.future;});
 });
 testWidgets('malformed original-story response does not claim it was deleted',(t)async{
  await fixture(t,(s,c)async{
   late BuildContext page;
   await t.pumpWidget(MaterialApp(home:Builder(builder:(context){page=context;return const Scaffold(body:Text('Current screen'));})));await flush(t);
   c.start('story',()async=>{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image'});await flush(t);
   await c.openOriginal(page);await t.pump();
   expect(find.text('Could not read stories. Try again.'),findsOneWidget);expect(find.text('The original story was removed or expired.'),findsNothing);expect(find.byType(StoryViewer),findsNothing);expect(t.takeException(),isNull);
  },respond:(r)async=>json({'data':[{'author':{},'items':[]}]}));
 });
 for(final malformed in <(String,Map<String,dynamic>)>[
  ('post',{...post(' ')}),('post',{...post('bad'),'author':{'public_id':'me','username':' '}}),
  ('post',{...post('bad'),'author':{'public_id':' ','username':'fixture'}}),
  ('story',{'public_id':' ','url':'https://fixture.invalid/a.jpg','type':'image'}),
  ('story',{'public_id':'story','url':' ','type':'image'}),
  ('story',{'public_id':'story','url':'https://fixture.invalid/a.jpg','type':'unknown'}),
 ]){
 testWidgets('malformed confirmed ${malformed.$1} identity ${malformed.$2} stays uncertain',(t)async{
  await fixture(t,(s,c)async{
   c.start(malformed.$1,()async=>malformed.$2);await flush(t);
   expect(c.result,isNull);expect(c.error,isA<UploadError>());expect(c.canRetry,isFalse);expect(c.confirmedPosts,isEmpty);expect(c.confirmedStories,isEmpty);
  });
 });
 }
 testWidgets('valid original-story response opens only that story',(t)async{
  await fixture(t,(s,c)async{
   late BuildContext page;
   await t.pumpWidget(MaterialApp(home:Builder(builder:(context){page=context;return const Scaffold(body:Text('Current screen'));})));await flush(t);
   c.start('story',()async=>{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image'});await flush(t);
   final opening=c.openOriginal(page);await flush(t);await t.pump(const Duration(milliseconds:400));
   expect(find.byType(StoryViewer),findsOneWidget);expect(t.widget<StoryViewer>(find.byType(StoryViewer)).group['items'].length,1);
   Navigator.of(t.element(find.byType(StoryViewer))).pop();await t.pump(const Duration(milliseconds:400));await opening;expect(t.takeException(),isNull);
  },respond:(r)async=>json({'data':[{'author':{'public_id':'me','username':'fixture'},'items':[{'public_id':'other','url':'https://fixture.invalid/other.jpg','type':'image','created_at':'2026-11-17T06:00:00Z'},{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image','created_at':'2026-11-17T06:00:00Z'}]}]}));
 });
 testWidgets('one app-level job survives composer exit and permits tab navigation until confirmed',(t) async {
  final reply=Completer<http.Response>();var writes=0,reads=0;
  await fixture(t,(s,center)async{
   await t.pumpWidget(MaterialApp(theme:buildTheme(Brightness.dark),home:HomeShell(session:s)));await flush(t);
   await t.tap(find.byTooltip('Post'));await t.pumpAndSettle();await t.tap(find.text('Post').last);await t.pump();await t.tap(find.widgetWithText(FilledButton,'Continue'));await t.pumpAndSettle();
   expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Post')).onPressed,isNull);
   await t.enterText(find.byType(TextField),'An original pending upload');await t.pump();await t.tap(find.widgetWithText(FilledButton,'Post'));await flush(t);
   await t.pump(const Duration(milliseconds:400));
   expect(find.byType(ComposePage),findsNothing);expect(center.busy,isTrue);expect(writes,1);expect(center.progress,1);expect(find.text('Finishing upload...'),findsOneWidget);
   await t.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.text('Wallet')));await flush(t);expect(find.byType(WalletPage),findsOneWidget);
   reply.complete(json({'post':post('new')}));await flush(t);expect(center.busy,isFalse);expect(center.error,isNull);
   await t.tap(find.descendant(of:find.byType(GlassNavBar),matching:find.text('Home')));await flush(t);expect(find.text('Confirmed new'),findsOneWidget);expect(reads,1,reason:'no refresh race is needed to show the committed response');
   expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='POST'&&r.url.path.endsWith('/posts')){writes++;expect(r.body,contains('An original pending upload'));return reply.future;}if(r.url.path.endsWith('/posts'))reads++;return json({'data':[],'next_cursor':null,'balance':0,'entries':[],'unread_messages':0});});
 });
 testWidgets('retry uses the immutable original key and data and duplicate start is rejected',(t)async{
  var writes=0;final bodies=<String>[];
  await fixture(t,(s,c)async{
   final intent=newUploadIntent();expect(c.start('post',()=>s.createPost('original',intent:intent)),isTrue);expect(c.start('post',()=>throw StateError('must not start')),isFalse);await flush(t);
   expect(c.canRetry,isTrue);expect(c.confirmedPosts,isEmpty);c.retry();await flush(t);expect(writes,2);expect(c.confirmedPosts.single['public_id'],'same');expect(bodies.every((b)=>b.contains(intent)&&b.contains('original')),isTrue);
  },respond:(r)async{bodies.add(r.body);if(++writes==1)throw http.ClientException('fixture reply lost');return json({'post':post('same')});});
 });
 testWidgets('legacy unknown result offers no retry and never resends on tab changes',(t)async{
  var writes=0;await fixture(t,(s,c)async{c.start('post',()=>s.createPost('legacy',intent:newUploadIntent()));await flush(t);expect(c.error,isA<UploadError>());expect(c.canRetry,isFalse);c.retry();await flush(t);expect(writes,1);},safe:false,respond:(r)async{writes++;throw http.ClientException('lost');});
 });
 testWidgets('incomplete success is not inserted as malformed feed content',(t)async{
  await fixture(t,(s,c)async{c.start('post',()=>s.createPost('original'));await flush(t);expect(c.error,isA<UploadError>());expect(c.confirmedPosts,isEmpty);expect(c.canRetry,isFalse);},respond:(r)async=>json({'post':{'public_id':'bad'}}));
 });
 testWidgets('account change discards in-memory job disclosure and ignores its late reply',(t)async{
  final reply=Completer<Map<String,dynamic>>();await fixture(t,(s,c)async{c.start('post',()=>reply.future);await flush(t);s.user={'public_id':'different','username':'other'};s.notifyListeners();expect(c.busy,isFalse);reply.complete(post('late'));await flush(t);expect(c.result,isNull);expect(c.confirmedPosts,isEmpty);expect(c.kind,isNull);});
 });
 testWidgets('confirmed result survives an older list request and deduplicates server acknowledgement',(t)async{
  final pending=Completer<http.Response>();var reads=0;
  await fixture(t,(s,c)async{
   final key=GlobalKey<FeedListState>();await t.pumpWidget(MaterialApp(home:Scaffold(body:FeedList(key:key,session:s,query:const {'kind':'post'}))));await flush(t);
   c.start('post',()async=>post('new'));await flush(t);expect(find.text('Confirmed new'),findsOneWidget);
   pending.complete(json({'data':[post('old')],'next_cursor':null}));await flush(t);expect(key.currentState!.posts.map((p)=>p['public_id']),['new','old']);
   await key.currentState!.load(refresh:true);await flush(t);expect(key.currentState!.posts.where((p)=>p['public_id']=='new').length,1);expect(t.takeException(),isNull);
  },respond:(r)async{reads++;return reads==1?pending.future:json({'data':[post('new'),post('old')],'next_cursor':null});});
 });
 testWidgets('story result appears in the current ring without refreshing stories',(t)async{
  var reads=0;await fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:Scaffold(body:StoriesBar(session:s))));await flush(t);
   c.start('story',()async=>{'public_id':'story','url':'https://fixture.invalid/story.jpg','type':'image','caption':'first'});await flush(t);
   expect(reads,1);expect(find.text('Your story'),findsOneWidget);expect(find.byType(StoriesBar),findsOneWidget);expect(c.confirmedStories.length,1);expect(t.takeException(),isNull);
  },respond:(r)async{reads++;return json({'data':[]});});
 });
 testWidgets('failed job retains snapshot until explicit dismissal, then permits a separate job',(t)async{
  await fixture(t,(s,c)async{c.start('post',()async=>throw ApiError('fixture preflight'));await flush(t);expect(c.occupied,isTrue);expect(c.start('post',()async=>post('two')),isFalse);await c.dismiss();expect(c.occupied,isFalse);c.start('post',()async=>post('two'));await flush(t);expect(c.result!['public_id'],'two');});
 });
}

// Offline members and controlled requests only. No real chat/group creation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object data,[int status=200])=>http.Response(jsonEncode(data),status);
const people=[{'public_id':'a','username':'asha','name':'Asha Gurung'},{'public_id':'b','username':'bikash','name':'Bikash Thapa'}];
Future<void> flush(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:400));await t.pump();}
Future<void> setup(WidgetTester t,Future<void> Function() body,Future<http.Response> Function(http.Request) handle,{String lang='en',Brightness mode=Brightness.light,bool big=false,bool keyboard=false})async{
 SharedPreferences.setMockInitialValues({});prefs.lang=lang;addTearDown(()=>prefs.lang='en');
 await http.runWithClient(()async{
  final session=Session();await session.login('fixture','not-a-password');
  final nav=GlobalKey<NavigatorState>();
  await t.pumpWidget(RepaintBoundary(key:const ValueKey('newchat-shot'),child:MaterialApp(navigatorKey:nav,debugShowCheckedModeBanner:false,theme:buildTheme(mode,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(big?1.8:1),viewInsets:EdgeInsets.only(bottom:keyboard?240:0)),child:w!),home:const Scaffold(body:Text('Inbox fixture')))));
  nav.currentState!.push(MaterialPageRoute<Map<String,dynamic>>(builder:(_)=>NewChatPage(session:session)));
  await flush(t);await body();await t.pumpWidget(const SizedBox());await flush(t);
 },()=>MockClient((r)async{if(r.url.path.endsWith('/oauth/token'))return reply({'access_token':'fixture','expires_in':3600});if(r.url.path.endsWith('/auth/me'))return reply({'user':{'public_id':'me','username':'fixture'}});return handle(r);}));
}
Future<void> search(WidgetTester t,String text)async{await t.enterText(find.byType(TextField).last,text);await flush(t);}
Future<void> group(WidgetTester t)async{await t.tap(find.byTooltip('New group'));await flush(t);await t.enterText(find.byType(TextField).first,'Sydney Nepali meetup');await search(t,'asha');await t.tap(find.text('Asha Gurung'));await flush(t);}
void main(){
 setUpAll(()async{for(final x in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){final l=FontLoader(x.$1)..addFont(Future.value(ByteData.sublistView(File(x.$2).readAsBytesSync())));await l.load();}});
 testWidgets('editing invalidates an older response before the next debounce fires',(t)async{
  final old=Completer<http.Response>();await setup(t,()async{
   await search(t,'a');await t.enterText(find.byType(TextField),'b');old.complete(reply({'users':[people.first]}));await t.pump();expect(find.text('Asha Gurung'),findsNothing);await flush(t);expect(find.text('Bikash Thapa'),findsOneWidget);
  },(r)async=>r.url.queryParameters['q']=='a'?old.future:reply({'users':[people.last]}));
 });
 testWidgets('clearing a query ignores a late failure and removes results',(t)async{
  final old=Completer<http.Response>();await setup(t,()async{await search(t,'a');await t.enterText(find.byType(TextField),'');old.complete(reply({'message':'Old error'},503));await flush(t);expect(find.text('Old error'),findsNothing);expect(find.text('Find someone to chat with'),findsOneWidget);expect(find.byType(CircularProgressIndicator),findsNothing);},(_)async=>old.future);
 });
 testWidgets('failed member read retries the same query without empty-state fiction',(t)async{
  var reads=0;await setup(t,()async{await search(t,'asha');expect(find.text('Fixture unavailable'),findsOneWidget);expect(find.text('No matches'),findsNothing);await t.tap(find.text('Try again'));await flush(t);expect(find.text('Asha Gurung'),findsOneWidget);expect(reads,2);},(r)async{expect(r.url.queryParameters['q'],'asha');return ++reads==1?reply({'message':'Fixture unavailable'},503):reply({'users':[people.first]});});
 });
 testWidgets('malformed search has retry and forced disposal suppresses late reads',(t)async{
  var reads=0;final late=Completer<http.Response>();await setup(t,()async{await search(t,'asha');expect(find.text('Could not load members. Try again.'),findsOneWidget);await t.tap(find.text('Try again'));await flush(t);await t.pumpWidget(const SizedBox());late.complete(reply({'users':people}));await flush(t);expect(t.takeException(),isNull);},(_)async=>++reads==1?reply({'users':'wrong'}):late.future);
 });
 testWidgets('pending group creation locks checkbox chips switch and back; no duplicate POST',(t)async{
  var posts=0;final pending=Completer<http.Response>();await setup(t,()async{await group(t);await t.tap(find.text('Create group (1)'));await flush(t);expect(posts,1);expect(t.widget<Checkbox>(find.byType(Checkbox).first).onChanged,isNull);expect(t.widget<InputChip>(find.byType(InputChip)).onDeleted,isNull);expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton&&w.tooltip=='One to one')).onPressed,isNull);await t.tap(find.text('Create group (1)'));await t.binding.handlePopRoute();await flush(t);expect(find.byType(NewChatPage),findsOneWidget);expect(posts,1);pending.complete(reply({'conversation':{'public_id':'new','type':'group'}}));await flush(t);await t.pumpAndSettle();expect(find.byType(NewChatPage),findsNothing);expect(posts,1);},(r)async{if(r.method=='POST'){posts++;return pending.future;}return reply({'users':people});});
 });
 testWidgets('explicit create rejection preserves group title and people for retry',(t)async{
  var posts=0;await setup(t,()async{await group(t);await t.tap(find.text('Create group (1)'));await flush(t);expect(find.text('Not permitted'),findsOneWidget);expect(find.text('Sydney Nepali meetup'),findsOneWidget);expect(find.byType(InputChip),findsOneWidget);await t.tap(find.text('Create group (1)'));await flush(t);expect(posts,2);},(r)async{if(r.method=='POST'){posts++;return reply({'message':'Not permitted'},422);}return reply({'users':people});});
 });
 for(final malformed in [false,true]){testWidgets('unknown creation result does not offer blind group resend ($malformed)',(t)async{
  var posts=0;await setup(t,()async{await group(t);await t.tap(find.text('Create group (1)'));await flush(t);expect(find.text('The chat may already exist. Check Chats before starting it again.'),findsOneWidget);await t.tap(find.text('Create group (1)'));expect(posts,1);await t.tap(find.text('Back to Chats'));await flush(t);await t.pumpAndSettle();expect(find.byType(NewChatPage),findsNothing);expect(find.byType(AlertDialog),findsNothing);},(r)async{if(r.method=='POST'){posts++;return malformed?reply({'conversation':{}}):reply({'message':'Unknown'},503);}return reply({'users':people});});
 });}
 testWidgets('selected people and group title ask before switching mode or leaving',(t)async{
  await setup(t,()async{await group(t);await t.tap(find.byTooltip('One to one'));await flush(t);expect(find.text('Discard this group?'),findsOneWidget);await t.tap(find.text('Keep editing'));await flush(t);expect(find.byType(InputChip),findsOneWidget);await t.binding.handlePopRoute();await flush(t);expect(find.text('Discard this draft?'),findsOneWidget);await t.tap(find.text('Keep editing'));await flush(t);expect(find.byType(NewChatPage),findsOneWidget);},(_)async=>reply({'users':people}));
 });
 testWidgets('a create completing after forced disposal cannot navigate the new route',(t)async{
  final pending=Completer<http.Response>();await setup(t,()async{await search(t,'asha');await t.tap(find.text('Asha Gurung'));await flush(t);await t.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Replacement'))));pending.complete(reply({'conversation':{'public_id':'new'}}));await flush(t);expect(find.text('Replacement'),findsOneWidget);expect(t.takeException(),isNull);},(r)async=>r.method=='POST'?pending.future:reply({'users':people}));
 });
 for(final lang in ['en','ne']){for(final mode in [Brightness.light,Brightness.dark]){for(final state in ['group','error','keyboard','unknown']){
 testWidgets('new chat $state small large-text ${mode.name} $lang',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  await setup(t,()async{
   if(state!='error'){
    await t.tap(find.byTooltip(lang=='en'?'New group':'नयाँ समूह'));await flush(t);await t.enterText(find.byType(TextField).first,'Sydney Nepali meetup');await search(t,'asha');await t.ensureVisible(find.text('Asha Gurung'));await t.tap(find.text('Asha Gurung'));await flush(t);
   if(state=='unknown'){await t.tap(find.byType(FilledButton));await flush(t);await t.ensureVisible(find.text(lang=='en'?'Back to Chats':'च्याटमा फर्कनुहोस्'));await flush(t);}
   }else{await search(t,'asha');}
   if(state=='keyboard'){final button=find.byType(FilledButton);expect(t.getBottomRight(button).dy,lessThanOrEqualTo(400));}expect(t.takeException(),isNull);await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('newchat-shot')));final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/newchat_${state}_${lang}_${mode.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
  },(r)async=>(state=='error'||r.method=='POST')?reply({'message':'Fixture unavailable'},503):reply({'users':people}),lang:lang,mode:mode,big:true,keyboard:state=='keyboard');
 });
 }}}
}

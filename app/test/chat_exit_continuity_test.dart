// Real ChatPage routes with synthetic responses. No live message, mic or device.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

Map<String,dynamic> row()=>{'public_id':'first','body':'Original question','sender':{'public_id':'other','username':'asha'},'seq':1,'kind':'text','created_at':'2026-11-20T00:00:00Z'};
class ExitSession extends Session{
 ExitSession(){user={'public_id':'me','username':'me'};}
 var reads=0,sends=0;bool reject=false;int epoch=0;
 @override int get generation=>epoch;
 final poll=Completer<dynamic>(),send=Completer<dynamic>();
 @override Future<dynamic> call(String method,String path,{Map<String,dynamic>? body,Map<String,String>? query})async{
  if(method=='GET')return ++reads==1?{'data':[row()]}:poll.future;
  if(path.endsWith('/messages')){sends++;if(reject)throw ApiError('Synthetic unavailable',503);return send.future;}
  return {};
 }
 void close(){if(!poll.isCompleted)poll.complete({'data':[]});if(!send.isCompleted)send.complete({'message':{...row(),'public_id':'sent','sender':{'public_id':'me','username':'me'},'body':'Pending message','seq':2}});}
}
Future<void> settle(WidgetTester t)async{await t.pump();await t.pump(const Duration(milliseconds:450));await t.pump();}
Future<void> open(WidgetTester t,ExitSession s,{Brightness brightness=Brightness.light,double scale=1})async{
 final nav=GlobalKey<NavigatorState>();
 await t.pumpWidget(RepaintBoundary(key:const ValueKey('exit-shot'),child:MaterialApp(debugShowCheckedModeBanner:false,navigatorKey:nav,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:const Scaffold(body:Text('Conversation list')))));
 nav.currentState!.push(MaterialPageRoute(builder:(_)=>ChatPage(session:s,convo:{'public_id':'chat','title':'Synthetic conversation','type':'direct'})));await settle(t);
 addTearDown(()async{s.close();await t.pumpWidget(const SizedBox());await t.pump(const Duration(seconds:3));});
}
void main(){
 setUpAll(()async{
  for(final pair in [('Roboto','${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]){
   final f=File(pair.$2);if(f.existsSync()){final font=FontLoader(pair.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await font.load();}
  }
 });
 setUp(()=>prefs.lang='en');
 testWidgets('unsent text requires deliberate leave and Stay preserves it',(t)async{
  final s=ExitSession();await open(t,s);await t.enterText(find.byType(TextField),'Unsent private draft');await settle(t);
  await t.pageBack();await settle(t);expect(find.text('Leave chat?'),findsOneWidget);
  await t.tap(find.text('Stay here'));await settle(t);expect(find.text('Unsent private draft'),findsOneWidget);expect(s.sends,0);
  await t.pageBack();await settle(t);await t.tap(find.text('Leave'));await settle(t);
  expect(find.text('Conversation list'),findsOneWidget);expect(s.sends,0);
 });
 testWidgets('cleared text does not leave a phantom draft prompt',(t)async{
  final s=ExitSession();await open(t,s);await t.enterText(find.byType(TextField),'Edit');await t.enterText(find.byType(TextField),'');await settle(t);await t.pageBack();await settle(t);expect(find.text('Conversation list'),findsOneWidget);expect(find.byType(AlertDialog),findsNothing);
 });
 testWidgets('selected reply without text is protected',(t)async{
  final s=ExitSession();await open(t,s);await t.longPress(find.text('Original question'));await settle(t);await t.tap(find.text('Reply'));await settle(t);
  await t.pageBack();await settle(t);expect(find.text('Leave chat?'),findsOneWidget);await t.tap(find.text('Stay here'));await settle(t);expect(find.textContaining('Replying to'),findsOneWidget);expect(s.sends,0);
 });
 testWidgets('failed text copy needs leave confirmation but does not resend',(t)async{
  final s=ExitSession()..reject=true;await open(t,s);await t.enterText(find.byType(TextField),'Failed original');await t.tap(find.byTooltip('Send message'));await settle(t);expect(s.sends,1);
  await t.pageBack();await settle(t);expect(find.text('Leave chat?'),findsOneWidget);await t.tap(find.text('Stay here'));await settle(t);expect(find.text('Failed original'),findsOneWidget);expect(s.sends,1);
 });
 testWidgets('pending text blocks route back without discarding or duplicate send',(t)async{
  final s=ExitSession();await open(t,s);await t.enterText(find.byType(TextField),'Pending message');await t.tap(find.byTooltip('Send message'));await settle(t);
  await t.pageBack();await settle(t);expect(find.byType(AlertDialog),findsNothing);expect(find.text('Your message is still sending.'),findsOneWidget);expect(find.text('Pending message'),findsOneWidget);expect(s.sends,1);
  s.close();await settle(t);await t.pageBack();await settle(t);expect(find.text('Conversation list'),findsOneWidget);expect(s.sends,1);
 });
 for(final brightness in Brightness.values)for(final language in ['en','ne']){
  testWidgets('chat leave prompt $brightness $language small large text',(t)async{
   prefs.lang=language;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(960,1920);t.view.devicePixelRatio=3;addTearDown(t.view.reset);
   final s=ExitSession();await open(t,s,brightness:brightness,scale:1.8);await t.enterText(find.byType(TextField),'Synthetic unsent text');await settle(t);await t.pageBack();await settle(t);
   expect(find.byType(AlertDialog),findsOneWidget);expect(t.takeException(),isNull);expect(s.sends,0);
   await t.runAsync(()async{final boundary=find.byKey(const ValueKey('exit-shot')).evaluate().single.renderObject! as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);Directory('test/renders').createSync(recursive:true);File('test/renders/chat_exit_${language}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
  });
 }
}

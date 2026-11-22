// Synthetic account/API only. No real person is blocked or unblocked.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/settings_page.dart';
import 'upload_center_test.dart' as helpers;
void main(){
 setUpAll(()async{for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final f=File(p.$2);if(f.existsSync()){final loader=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}}});
 for(final lang in ['en','ne']){for(final brightness in [Brightness.dark,Brightness.light]){
 testWidgets('blocked retry renders narrow large text $lang ${brightness.name}',(t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');
  await helpers.fixture(t,(session,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('blocked-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:BlockedPage(session:session))));await helpers.flush(t);
   expect(find.text(t_('Try again')),findsOneWidget);expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('blocked-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/blocked_retry_${lang}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
  },respond:(_)async=>http.Response(jsonEncode({'message':t_('Blocked people could not be loaded.')}),503,headers:{'content-type':'application/json; charset=utf-8'}));
 });}}

 testWidgets('blocked initial failure retries and empty state remains refreshable',(t)async{
  var reads=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   expect(find.text('Could not load this.'),findsOneWidget);
   await t.tap(find.text('Try again'));await helpers.flush(t);
   expect(find.text('You have not blocked anyone'),findsOneWidget);
   await t.tap(find.byTooltip('Refresh'));await helpers.flush(t);expect(reads,3);
  },respond:(_)async=>++reads==1?helpers.json({'message':'Synthetic unavailable'},503):helpers.json({'data':[]}));
 });
 testWidgets('refresh failure keeps existing blocked identity and explicit retry does not mutate',(t)async{
  var reads=0,writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   await t.tap(find.byTooltip('Refresh'));await helpers.flush(t);
   expect(find.text('@fixture'),findsOneWidget);expect(find.text('Could not load this.'),findsOneWidget);
   await t.tap(find.text('Try again'));await helpers.flush(t);expect(reads,3);expect(writes,0);
  },respond:(r)async{if(r.method!='GET')writes++;reads++;return reads==2?helpers.json({'message':'Synthetic read failed'},503):helpers.json({'data':[{'username':'fixture'}]});});
 });
 testWidgets('pending unblock locks duplicate mutation until reconciliation',(t)async{
  final reply=Completer<http.Response>();var writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   await t.tap(find.text('Unblock'));await helpers.flush(t);await t.tap(find.text('Unblock'));await helpers.flush(t);expect(writes,1);
   reply.complete(helpers.json({}));await helpers.flush(t);expect(t.takeException(),isNull);
  },respond:(r)async{if(r.method=='DELETE'){writes++;return reply.future;}return helpers.json({'data':[{'username':'fixture'}]});});
 });
 testWidgets('refresh cannot overtake pending unblock reconciliation',(t)async{
  final deletion=Completer<http.Response>();final oldRead=Completer<http.Response>();var reads=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   final retainedRefresh=t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
   await t.tap(find.text('Unblock'));await helpers.flush(t);
   expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Refresh')).onPressed,isNull);
   unawaited(retainedRefresh());await helpers.flush(t);
   expect(reads,1,reason:'manual refresh must wait for the pending moderation write');
   deletion.complete(helpers.json({}));await helpers.flush(t);
   expect(reads,2);expect(find.text('You have not blocked anyone'),findsOneWidget);
   expect(find.text('@fixture'),findsNothing);
  },respond:(r)async{
   if(r.method=='DELETE')return deletion.future;
   reads++;
   if(reads==1)return helpers.json({'data':[{'username':'fixture'}]});
   if(!deletion.isCompleted)return oldRead.future;
   return helpers.json({'data':[]});
  });
 });

 testWidgets('unblock failure releases refresh without inventing successful removal',(t)async{
  final deletion=Completer<http.Response>();var reads=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   await t.tap(find.text('Unblock'));await helpers.flush(t);
   deletion.complete(helpers.json({'message':'Synthetic failure'},503));await helpers.flush(t);
   expect(find.text('@fixture'),findsOneWidget);expect(reads,1);
   expect(t.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='Refresh')).onPressed,isNotNull);
   await t.tap(find.byTooltip('Refresh'));await helpers.flush(t);expect(reads,2);
  },respond:(r)async{if(r.method=='DELETE')return deletion.future;reads++;return helpers.json({'data':[{'username':'fixture'}]});});
 });
 testWidgets('post-unblock read failure offers retry after write lock ends',(t)async{
  var reads=0,writes=0;
  await helpers.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:BlockedPage(session:s)));await helpers.flush(t);
   await t.tap(find.text('Unblock'));await helpers.flush(t);
   expect(find.text('Try again'),findsOneWidget);expect(reads,2);expect(writes,1);
   await t.tap(find.text('Try again'));await helpers.flush(t);
   expect(reads,3);expect(writes,1);expect(find.text('You have not blocked anyone'),findsOneWidget);
  },respond:(r)async{
   if(r.method=='DELETE'){writes++;return helpers.json({});}
   reads++;
   if(reads==1)return helpers.json({'data':[{'username':'fixture'}]});
   if(reads==2)return helpers.json({'message':'Synthetic unavailable'},503);
   return helpers.json({'data':[]});
  });
 });

}

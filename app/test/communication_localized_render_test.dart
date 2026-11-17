// Synthetic call/room lists only, not device/call/room execution evidence.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/calls_page.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/rooms_page.dart';
import 'package:sanjaal/ui.dart';
import 'upload_center_test.dart' as helpers;
void main(){
 setUpAll(()async{for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final f=File(p.$2);if(f.existsSync()){final loader=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}}});
 for(final page in ['calls','rooms','chats']){for(final lang in ['en','ne']){for(final brightness in [Brightness.dark,Brightness.light]){
 testWidgets('localized $page recovery narrow large text $lang ${brightness.name}',(t)async{
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);var reads=0;
  await helpers.fixture(t,(session,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('communication-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:page=='calls'?CallsPage(session:session):page=='rooms'?RoomsPage(session:session):ChatsPage(session:session))));await helpers.flush(t);
   await t.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();await helpers.flush(t);expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('communication-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/communication_${page}_${lang}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
   if(page=='chats'){
    await t.tap(find.byTooltip(t_('More')));await t.pumpAndSettle();await t.tap(find.text(t_('Archived chats')));await helpers.flush(t);await t.pumpAndSettle();expect(find.text(t_('No archived chats')),findsOneWidget);expect(t.takeException(),isNull);
    await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('communication-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/communication_archived_${lang}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
   }
  },respond:(_)async=>++reads==1?helpers.json({'data':page=='calls'?[{'public_id':'call','conversation_id':'chat','title':'Asha Gurung','caller':{'username':'asha'},'direction':'incoming','kind':'voice','status':'ended','duration_s':125,'created_at':'2026-11-17T00:00:00Z'}]:page=='rooms'?[{'public_id':'room','title':'Community music','host_name':'Asha Gurung'}]:[{'public_id':'chat','title':'Community music','last_message':{'kind':'post','created_at':'2026-11-17T00:00:00Z'}},{'public_id':'new','title':'Asha Gurung'}]}):helpers.json({'data':reads==2?[{'title':'Malformed'}]:[]}));
 });}}}
}

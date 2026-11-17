// Synthetic notifications only, not device/push delivery evidence.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/notifications_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart';
import 'upload_center_test.dart' as helpers;
void main(){
 setUpAll(()async{for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final f=File(p.$2);if(f.existsSync()){final loader=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}}});
 for(final lang in ['en','ne']){for(final brightness in [Brightness.dark,Brightness.light]){
 testWidgets('localized activity and recovery narrow large text $lang ${brightness.name}',(t)async{
  prefs.lang=lang;addTearDown(()=>prefs.lang='en');t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);var reads=0;
  await helpers.fixture(t,(session,c)async{
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('activity-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:NotificationsPage(session:session))));await helpers.flush(t);
   await t.tap(find.byTooltip(t_('Refresh')));await helpers.flush(t);expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('activity-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/activity_localized_${lang}_${brightness.name}.png').writeAsBytesSync(data!.buffer.asUint8List());});
   await t.drag(find.byType(ListView),const Offset(0,-400));await t.pumpAndSettle();expect(find.textContaining('@chandra'),findsOneWidget);expect(t.takeException(),isNull);
   await t.runAsync(()async{final image=await t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('activity-review'))).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/activity_localized_${lang}_${brightness.name}_bottom.png').writeAsBytesSync(data!.buffer.asUint8List());});
  },respond:(_)async=>++reads==1?http.Response(jsonEncode({'data':[{'type':'like','actor':'asha','text':'Original caption','created_at':'2026-11-17T06:00:00Z'},{'type':'comment','actor':'bina','text':'Original words','created_at':'2026-11-17T06:00:00Z'},{'type':'follow','actor':'chandra','created_at':'2026-11-17T06:00:00Z'}]}),200,headers:{'content-type':'application/json; charset=utf-8'}):helpers.json({'data':[{'type':'unexpected'}]}));
 });}}
}

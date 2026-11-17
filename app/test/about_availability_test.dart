// Offline widget proof only. Does not establish installed-phone or payment readiness.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/about_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart';
void main(){
 setUpAll(()async{
  Directory('test/renders').createSync(recursive:true);
  for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final f=File(p.$2);if(f.existsSync()){final loader=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}}
 });
 for(final lang in ['en','ne']){
  testWidgets('About does not advertise unavailable money actions $lang',(t)async{
   prefs.lang=lang;addTearDown(()=>prefs.lang='en');
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('about-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.dark,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(1.8)),child:w!),home:const AboutPage())));
   await t.pumpAndSettle();
   final funding=find.text(t_('Adding coins is not switched on yet. Cash out is not available.'));
   final transfer=find.text(t_('Transfers are unavailable until live verification is complete.'));
   await t.scrollUntilVisible(funding,200);await t.pumpAndSettle();
   await t.ensureVisible(transfer);await t.pumpAndSettle();
   expect(funding,findsOneWidget);expect(transfer,findsOneWidget);
   expect(find.textContaining('Coins move between members'),findsNothing);expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('about-review')));final image=await boundary.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/about_money_hold_$lang.png').writeAsBytesSync(data!.buffer.asUint8List());});
  });
 }
}

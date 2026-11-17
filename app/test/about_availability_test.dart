// Offline widget proof only. Does not establish installed-phone or payment readiness.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/ui.dart';
void main(){
 setUpAll(()async{
  Directory('test/renders').createSync(recursive:true);
  for(final p in [('Roboto','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT']??''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')]){final f=File(p.$2);if(f.existsSync()){final loader=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));await loader.load();}}
 });
 for(final lang in ['en','ne']){for(final brightness in [Brightness.dark,Brightness.light]){for(final scale in [1.0,1.8]){
  testWidgets('About does not advertise unavailable money actions $lang ${brightness.name} $scale',(t)async{
   prefs.lang=lang;addTearDown(()=>prefs.lang='en');
   t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
   PackageInfo.setMockInitialValues(appName:'Sanjaal',packageName:'au.fintex.sanjaal',version:'0.5.5',buildNumber:'2010',buildSignature:'fixture');
   await t.pumpWidget(RepaintBoundary(key:const ValueKey('about-review'),child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto',fontFamilyFallback:['NotoDev']),builder:(context,w)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:const AboutPage())));
   await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:120)));await t.pumpAndSettle();
   Future<void> shot(String suffix)async{await t.runAsync(()async{final b=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('about-review')));final image=await b.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/about_full_${lang}_${brightness.name}_${scale==1?'normal':'large'}_$suffix.png').writeAsBytesSync(data!.buffer.asUint8List());});}
   await shot('top');
   for(final section in ['Publisher','Privacy','Terms','Open source licences']){
    final target=find.text(t_(section));await t.scrollUntilVisible(target,120);await t.ensureVisible(target);await t.pumpAndSettle();await shot(section.split(' ').first.toLowerCase());
   }
   if(lang=='ne'){
    for(final english in ['Terms','Privacy','Open source licences','View licences','App updates','Publisher','Check for updates'])expect(find.text(english,skipOffstage:false),findsNothing);
    expect(find.textContaining('Be kind.',skipOffstage:false),findsNothing);
   }
   final funding=find.text(t_('Adding coins is not switched on yet. Cash out is not available.'));
   final transfer=find.text(t_('Transfers are unavailable until live verification is complete.'));
   await t.scrollUntilVisible(funding,-180);await t.pumpAndSettle();
   await t.ensureVisible(transfer);await t.pumpAndSettle();
   expect(funding,findsOneWidget);expect(transfer,findsOneWidget);
   expect(find.textContaining('Coins move between members'),findsNothing);expect(t.takeException(),isNull);
   await t.runAsync(()async{final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('about-review')));final image=await boundary.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('test/renders/about_money_hold_${lang}_${brightness.name}_${scale==1?'normal':'large'}.png').writeAsBytesSync(data!.buffer.asUint8List());});
  });
 }}}
}

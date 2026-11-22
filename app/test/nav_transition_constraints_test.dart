// Host-frame constraint regression, not native-device or animation-performance proof.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/glass_nav.dart';

Future<void> shot(WidgetTester t,GlobalKey key,String name)async {
 await t.runAsync(()async {
 final boundary=key.currentContext!.findRenderObject() as RenderRepaintBoundary;
 final image=await boundary.toImage(pixelRatio:2);
 final data=await image.toByteData(format:ui.ImageByteFormat.png);
 await File('/downloads/sj-nav-$name.png').writeAsBytes(data!.buffer.asUint8List());image.dispose();
 });
}
void main(){
 setUpAll(()async {
  final font=File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  await (FontLoader('Roboto')..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
 });
 for(final brightness in [Brightness.light,Brightness.dark]){
 for(final scale in [1.0,1.8]){
 for(final direction in [true,false]){
 testWidgets('nav transition ${brightness.name} scale$scale expand$direction', (t)async{
  t.view.physicalSize=const Size(320,640);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
  final compact=ValueNotifier<bool>(direction),key=GlobalKey();addTearDown(compact.dispose);
  final errors=<Object>[];
  void check(){final error=t.takeException();if(error!=null)errors.add(error);}
  await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(brightness,fontFamily:'Roboto'),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:Scaffold(body:const Center(child:Text('Retained content')),bottomNavigationBar:ValueListenableBuilder<bool>(valueListenable:compact,builder:(c,value,_)=>GlassNavBar(items:const[NavItem('Home','house','house'),NavItem('Reels','play-circle','play-circle'),NavItem('Chats','chat-circle','chat-circle'),NavItem('Wallet','wallet','wallet'),NavItem('Me','user-circle','user-circle')],index:0,compact:value,onSelected:(_){},onSearch:(){}))))));
  await t.pumpAndSettle();check();
  compact.value=!compact.value;await t.pump();check();
  if(brightness==Brightness.light&&scale==1&&direction)await shot(t,key,'${const String.fromEnvironment('NAV_LABEL',defaultValue:'before')}-first');
  await t.pump(const Duration(milliseconds:90));check();
  if(brightness==Brightness.light&&scale==1&&direction)await shot(t,key,'${const String.fromEnvironment('NAV_LABEL',defaultValue:'before')}-mid');
  await t.pumpAndSettle();check();
  if(brightness==Brightness.light&&scale==1&&direction)await shot(t,key,'${const String.fromEnvironment('NAV_LABEL',defaultValue:'before')}-settled');
  expect(errors,isEmpty,reason:'No transient overflow while the outer bar interpolates its height');
 });
 }}}
}

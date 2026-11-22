// Additional raster screening only. Not native optics or formal contrast acceptance.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/main.dart' show buildTheme;
void main(){
 setUpAll(()async{final f=FontLoader('Roboto')..addFont(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf').readAsBytes().then((b)=>ByteData.sublistView(b)));await f.load();});
 for(final dark in [false,true]){for(final large in [false,true]){for(final bg in ['white','black','mountain','patan-bell']){
  testWidgets('backdrop $bg dark=$dark large=$large',(t)async{
   t.view.physicalSize=Size(large?320:390,844);t.view.devicePixelRatio=1;addTearDown(t.view.reset);final key=GlobalKey();
   final background=bg=='white'||bg=='black'?ColoredBox(color:bg=='white'?Colors.white:Colors.black,child:const SizedBox.expand()):Image.memory(File('/downloads/sanjaal-highfidelity/$bg.jpg').readAsBytesSync(),fit:BoxFit.cover,width:double.infinity,height:double.infinity);
   await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(dark?Brightness.dark:Brightness.light,fontFamily:'Roboto'),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(large?1.8:1)),child:w!),home:Scaffold(extendBody:true,body:background,bottomNavigationBar:GlassNavBar(immersive:dark,items:const[NavItem('Home','house','house-fill'),NavItem('Reels','play-circle','play-circle-fill'),NavItem('Chats','chat-circle','chat-circle-fill',badge:128),NavItem('Wallet','wallet','wallet-fill'),NavItem('Me','user-circle','user-circle-fill')],index:0,onSelected:(_){},onSearch:(){})))));
   for(var i=0;i<3;i++){await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));await t.pumpAndSettle();}
   expect(t.takeException(),isNull);
   await t.runAsync(()async{final im=await(key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await im.toByteData(format:ui.ImageByteFormat.png);Directory('/downloads/sanjaal-backdrop-review').createSync(recursive:true);File('/downloads/sanjaal-backdrop-review/$bg-${dark?'dark':'light'}-${large?'large':'normal'}.png').writeAsBytesSync(bytes!.buffer.asUint8List());});
   await t.pumpWidget(const SizedBox());await t.pump();
  });
 }}}
}

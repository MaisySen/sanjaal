import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/glass/glass_settings.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final dark in [false,true]) {
    for (final reduced in [false,true]) {
      testWidgets('nav optical transmission dark=$dark reduced=$reduced', (t) async {
        SharedPreferences.setMockInitialValues({});
        await glassSettings.setTransparency(.5);
        await glassSettings.setReduced(reduced);
        t.view.physicalSize=const Size(390,844);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
        final key=GlobalKey();
        await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.light),home:Scaffold(extendBody:true,body:Row(children:[for(final c in [const Color(0xFFF05050),const Color(0xFF32BA78),const Color(0xFF4488E0)]) Expanded(child:ColoredBox(color:c,child:const SizedBox.expand()))]),bottomNavigationBar:GlassNavBar(immersive:dark,items:const[NavItem('Home','house','house-fill'),NavItem('Reels','play-circle','play-circle-fill'),NavItem('Chats','chat-circle','chat-circle-fill'),NavItem('Wallet','wallet','wallet-fill'),NavItem('Me','user-circle','user-circle-fill')],index:0,onSelected:(_){})))));
        await t.pumpAndSettle();
        expect(t.takeException(),isNull);
        await t.runAsync(()async {
          final image=await(key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
          final rgba=(await image.toByteData(format:ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
          List<int> pixel(int x,int y){final i=(y*2*image.width+x*2)*4;return rgba.sublist(i,i+3);}
          final left=pixel(95,805),right=pixel(290,805);
          if(!reduced){expect(left[0]-left[2],greaterThan(20));expect(right[2]-right[0],greaterThan(20));}
          else {expect(left,right);}
          final data=await image.toByteData(format:ui.ImageByteFormat.png);
          File('/downloads/sanjaal-density-review/nav-optics-${dark?'dark':'light'}-${reduced?'reduced':'glass'}.png').writeAsBytesSync(data!.buffer.asUint8List());
          print('NAV_BACKGROUND_PIXELS dark=$dark reduced=$reduced left=$left right=$right');
        });
        await glassSettings.setReduced(false);
      });
    }
  }
}

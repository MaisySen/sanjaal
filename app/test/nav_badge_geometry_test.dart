// Fixture geometry only. No real notifications or native performance measurement.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/ph.dart';
import 'package:sanjaal/main.dart' show buildTheme;
void main() {
  setUpAll(() async {
    final font=FontLoader('Roboto')..addFont(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf').readAsBytes().then((b)=>ByteData.sublistView(b)));await font.load();
  });
  for(final width in [320.0,390.0]) { for(final scale in [1.0,1.8]) { for(final count in [12,99,128,12984]) {
    testWidgets('badge $count width=$width scale=$scale',(t) async {
      t.view.physicalSize=Size(width,844);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
      final taps=<int>[], key=GlobalKey();
      await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:buildTheme(Brightness.light,fontFamily:'Roboto'),builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!),home:Scaffold(body:const ColoredBox(color:Color(0xFFCCDDE9),child:SizedBox.expand()),bottomNavigationBar:GlassNavBar(items:[const NavItem('Home','house','house-fill'),const NavItem('Reels','play-circle','play-circle-fill'),NavItem('Chats','chat-circle','chat-circle-fill',badge:count),const NavItem('Wallet','wallet','wallet-fill'),const NavItem('Me','user-circle','user-circle-fill')],index:0,onSelected:taps.add,onSearch:()=>taps.add(5))))));
      await t.pumpAndSettle();
      final badge=t.getRect(find.byType(Badge));
      final label=t.getRect(find.text(count>99?'99+':'$count'));
      final wallet=t.getRect(find.byWidgetPredicate((w)=>w is PhIcon && w.icon=='wallet').last);
      expect(badge.overlaps(wallet),isFalse,reason:'badge $badge wallet $wallet label $label');
      if(scale>1) {
        final chats=t.getRect(find.byWidgetPredicate((w)=>w is PhIcon && w.icon=='chat-circle').last);
        final reels=t.getRect(find.byWidgetPredicate((w)=>w is PhIcon && w.icon=='play-circle').last);
        expect(badge.overlaps(chats),isFalse,reason:'Badge must not hide its own Chats icon');
        expect(badge.overlaps(reels),isFalse);
        expect(badge.bottom,lessThanOrEqualTo(chats.top));
        final mq=MediaQuery.of(t.element(find.text(count>99?'99+':'$count')));
        expect(mq.textScaler.scale(12),closeTo(12*scale,.01));
      }
      final gestures=find.descendant(of:find.byType(GlassNavBar),matching:find.byType(GestureDetector));
      final rects=<Rect>[];
      for(final e in gestures.evaluate()) {
        final w=e.widget as GestureDetector;if(w.onTap==null)continue;
        final box=e.renderObject as RenderBox;final r=box.localToGlobal(Offset.zero)&box.size;
        if(r.width<40 || r.height<40)continue;
        rects.add(r);
      }
      expect(rects.length,greaterThanOrEqualTo(5));
      for(var i=0;i<5;i++) {expect(rects[i].width,greaterThanOrEqualTo(44));expect(rects[i].height,greaterThanOrEqualTo(44));if(i>0)expect(rects[i-1].overlaps(rects[i]),isFalse);await t.tapAt(rects[i].center);}
      expect(taps.take(5).toList(),[0,1,2,3,4]);
      final search=t.getRect(find.byTooltip('Search'));
      expect(search.width,greaterThanOrEqualTo(44));expect(search.height,greaterThanOrEqualTo(44));
      expect(rects[4].overlaps(search),isFalse);
      await t.tapAt(search.center);expect(taps.last,5);
      expect(t.takeException(),isNull);
      if(width==320 && scale==1.8) { await t.runAsync(()async {
        final image=await(key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);File('/downloads/sanjaal-populated-review/nav-badge-$count.png').writeAsBytesSync(data!.buffer.asUint8List());
      }); }
      await t.pumpWidget(const SizedBox());await t.pump();
    });
  }}}
}

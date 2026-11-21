import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'proposed_service_designs.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    final root = Platform.environment['FLUTTER_ROOT'];
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(File('$root/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await loader.load();
  });
  for (final name in ['report-review','report-status','report-result','privacy-audience','privacy-saved','delete-review','delete-confirm','delete-status','export-request','export-ready']) {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('$name ${b.name} $scale', (t) async {
          t.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(key:key, child: MaterialApp(debugShowCheckedModeBanner:false, theme:buildTheme(b,fontFamily:'Roboto'), builder:(c,w)=>MediaQuery(data:MediaQuery.of(c).copyWith(textScaler:TextScaler.linear(scale)),child:w!), home:ProposedServiceScreen(name))));
          await t.pumpAndSettle();
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pumpAndSettle();
          expect(t.takeException(),isNull);
          await t.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
            final data = await image.toByteData(format:ui.ImageByteFormat.png);
            File('/downloads/sanjaal-pr-service-design/$name-${b.name}-$scale.png').writeAsBytesSync(data!.buffer.asUint8List());
          });
          if (scale > 1) {
            await t.drag(find.byType(ListView), const Offset(0, -1000));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            final scroll = t.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
            expect(scroll.position.extentAfter, lessThan(1));
            await t.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
              final data = await image.toByteData(format:ui.ImageByteFormat.png);
              File('/downloads/sanjaal-pr-service-design/$name-${b.name}-$scale-scrolled.png').writeAsBytesSync(data!.buffer.asUint8List());
            });
          }
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}

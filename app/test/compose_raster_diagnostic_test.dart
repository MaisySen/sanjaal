// Bounded synthetic raster diagnosis of exact acceptance runtime. No posts.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/feed_page.dart';
import 'creator_journey_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    for (final p in [('Roboto','${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),('MaterialIcons','${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),('NotoDev','assets/fonts/NotoSansDevanagari.ttf')]) {
      final f=File(p.$2);
      if(f.existsSync()) { final l=FontLoader(p.$1)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync()))); await l.load(); }
    }
  });
  testWidgets('compose enable-transition raster stages, exact unchanged runtime', (t) async {
    t.view.physicalSize = const Size(320,640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await fixtures.fixture(t, (s) => ComposePage(session:s), () async {
      final field=find.byType(TextField);
      await t.tap(field);
      await t.pump(const Duration(milliseconds:500));
      await t.showKeyboard(field);
      t.testTextInput.enterText('Synthetic compose diagnostic. Never posted.');
      await t.pump(const Duration(milliseconds:500));
      Future<void> capture(String stage) async {
        final label=find.descendant(of:find.byType(FilledButton),matching:find.text('Post'));
        final paragraph=t.renderObject<RenderParagraph>(label);
        // ignore: avoid_print
        print('RASTER $stage label=${paragraph.text.toPlainText()} span=${paragraph.text.style} default=${DefaultTextStyle.of(t.element(label)).style} enabled=${t.widget<FilledButton>(find.byType(FilledButton)).onPressed != null}');
        await fixtures.shot(t,'diagnostic_compose_$stage');
      }
      await capture('first_after_text');
      await t.pump();
      await capture('next_zero');
      await t.pump(const Duration(milliseconds:250));
      await capture('settled');
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
      final paragraph=t.renderObject<RenderParagraph>(find.descendant(of:find.byType(FilledButton),matching:find.text('Post')));
      expect(paragraph.text.style?.color,const Color(0xFF0B0D11));
      expect(t.takeException(),isNull);
    },brightness:Brightness.dark);
  });
}

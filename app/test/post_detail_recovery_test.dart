import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/post_page.dart';

import 'upload_center_test.dart' as h;

void main() {
  setUpAll(() async {
    for (final f in [
      (
        'Roboto',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(f.$1)..addFont(
            File(f.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  for (final bad in [
    <String, dynamic>{'post': null},
    <String, dynamic>{'post': []},
    {
      'post': {...h.post('wrong')},
    },
    {
      'post': {...h.post('fixture'), 'author': null},
    },
    {
      'post': {
        ...h.post('fixture'),
        'media': [true],
      },
    },
    {
      'post': {...h.post('fixture'), 'comments_count': 'invalid'},
    },
  ]) {
    testWidgets('malformed detail has recoverable error, not a spinner $bad', (
      t,
    ) async {
      var malformed = true, reads = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              home: PostPage(session: s, postId: 'fixture'),
            ),
          );
          await h.flush(t);
          expect(t.takeException(), isNull);
          expect(find.text('Post could not be loaded.'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          malformed = false;
          await t.tap(find.text('Try again'));
          await h.flush(t);
          expect(reads, 2);
          expect(find.text('Confirmed fixture'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          reads++;
          return h.json(malformed ? bad : {'post': h.post('fixture')});
        },
      );
    });
  }
  testWidgets('late malformed detail cannot surface in a replacement session', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(
        MaterialApp(
          home: PostPage(session: s, postId: 'fixture'),
        ),
      );
      await t.pump();
      s.user = {'public_id': 'other', 'username': 'other'};
      s.notifyListeners();
      await t.pump();
      pending.complete(h.json({'post': null}));
      await h.flush(t);
      expect(find.text('Post could not be loaded.'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(t.takeException(), isNull);
    }, respond: (_) => pending.future);
  });
  for (final lang in ['en', 'ne']) {
    testWidgets('post failure and retry readable 320 large text $lang', (
      t,
    ) async {
      prefs.lang = lang;
      addTearDown(() => prefs.lang = 'en');
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await h.fixture(t, (s, c) async {
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                lang == 'en' ? Brightness.light : Brightness.dark,
                fontFamily: 'Roboto',
              ),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(1.8)),
                child: w!,
              ),
              home: PostPage(session: s, postId: 'fixture'),
            ),
          ),
        );
        await h.flush(t);
        final retry = find.text(t_('Try again'));
        expect(retry.hitTestable(), findsOneWidget);
        expect(find.text(t_('Post could not be loaded.')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/sj-post-detail-$lang.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }, respond: (_) async => h.json({'post': null}));
    });
  }
}

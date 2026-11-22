// Synthetic inbox settings/recovery and render fixtures only.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_, RefreshReadNotice;

import 'upload_center_test.dart' as h;

Map<String, dynamic> row(String title, {bool muted = false}) => {
  'public_id': 'thread',
  'type': 'direct',
  'title': title,
  'unread': 0,
  'pinned': false,
  'muted': muted,
  'archived': false,
};
VoidCallback menu(WidgetTester t, String title) => t
    .widget<InkWell>(
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
    )
    .onLongPress!;
Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final image = await t
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('settings-review')),
        )
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('test/renders/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    Directory('test/renders').createSync(recursive: true);
    for (final p in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      final loader = FontLoader(
        p.$1,
      )..addFont(File(p.$2).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  for (final invalid in ['string', 'null', 'missing']) {
    testWidgets(
      'settings reconciliation rejects $invalid flag without replacing the snapshot',
      (t) async {
        var reads = 0, writes = 0;
        prefs.lang = 'en';
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
            await h.flush(t);
            final old = menu(t, 'Initial thread');
            old();
            await h.flush(t);
            await t.tap(find.widgetWithText(ListTile, 'Mute'));
            await h.flush(t);
            old();
            await h.flush(t);
            final retained = find.text('Initial thread').evaluate().length,
                rejected = find
                    .text('Unverified replacement')
                    .evaluate()
                    .length;
            final recovery = find.text('Could not refresh.').evaluate().length;
            final staleMenu = find
                .widgetWithText(ListTile, 'Mute')
                .evaluate()
                .length;
            await t.tap(find.text('Try again'));
            await h.flush(t);
            menu(t, 'Refreshed thread')();
            await h.flush(t);
            final confirmed = find
                .widgetWithText(ListTile, 'Unmute')
                .evaluate()
                .length;
            await t.pumpWidget(const SizedBox());
            await h.flush(t);
            expect(retained, 1);
            expect(rejected, 0);
            expect(recovery, 1);
            expect(staleMenu, 0);
            expect(confirmed, 1);
            expect(reads, 3);
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'PATCH') {
              writes++;
              return h.json({
                'pinned': false,
                'muted': true,
                'archived': false,
              });
            }
            reads++;
            final value = row(
              reads == 1
                  ? 'Initial thread'
                  : reads == 2
                  ? 'Unverified replacement'
                  : 'Refreshed thread',
              muted: reads > 1,
            );
            if (reads == 2) {
              if (invalid == 'missing') {
                value.remove('muted');
              } else {
                value['muted'] = invalid == 'null' ? null : 'true';
              }
            }
            return h.json({
              'data': [value],
            });
          },
        );
      },
    );
  }
  for (final config in [
    ('en', 1.8, 320.0, 640.0),
    ('ne', 1.8, 320.0, 640.0),
    ('en', 1.0, 390.0, 844.0),
    ('ne', 1.0, 390.0, 844.0),
  ]) {
    final lang = config.$1;
    final suffix = lang + (config.$2 == 1.0 ? '_normal' : '');
    testWidgets(
      'settings progress and read recovery readable $lang scale=${config.$2}',
      (t) async {
        t.view.physicalSize = Size(config.$3, config.$4);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        var reads = 0, writes = 0;
        final pending = Completer<http.Response>();
        final retryRead = Completer<http.Response>();
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('settings-review'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildTheme(
                    lang == 'en' ? Brightness.light : Brightness.dark,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: ['NotoDev'],
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(config.$2)),
                    child: child!,
                  ),
                  home: ChatsPage(session: s),
                ),
              ),
            );
            await h.flush(t);
            menu(t, 'A long synthetic conversation title')();
            await h.flush(t);
            await t.tap(find.widgetWithText(ListTile, t_('Mute')));
            await h.flush(t);
            expect(find.text(t_('Updating chat settings')), findsOneWidget);
            await capture(t, 'chat_settings_pending_$suffix');
            pending.complete(
              h.json({'pinned': false, 'muted': true, 'archived': false}),
            );
            await h.flush(t);
            expect(find.text(t_('Could not refresh.')), findsOneWidget);
            expect(find.text(t_('Updating chat settings')), findsNothing);
            await capture(t, 'chat_settings_recovery_$suffix');
            if (config.$2 == 1.0) {
              expect(
                t.getSize(find.byType(RefreshReadNotice)).height,
                lessThanOrEqualTo(72),
              );
            }
            final retry = t
                .widget<TextButton>(
                  find.widgetWithText(TextButton, t_('Try again')),
                )
                .onPressed!;
            retry();
            retry();
            await h.flush(t);
            expect(reads, 3);
            expect(find.text(t_('Updating chat settings')), findsOneWidget);
            expect(
              t
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, t_('Try again')),
                  )
                  .onPressed,
              isNull,
            );
            await capture(t, 'chat_settings_retry_$suffix');
            retryRead.complete(
              h.json({
                'data': [
                  row('A long synthetic conversation title', muted: true),
                ],
              }),
            );
            await h.flush(t);
            menu(t, 'A long synthetic conversation title')();
            await h.flush(t);
            expect(find.widgetWithText(ListTile, t_('Unmute')), findsOneWidget);
            await t.pumpWidget(const SizedBox());
            await h.flush(t);
            expect(reads, 3);
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'PATCH') {
              writes++;
              return pending.future;
            }
            reads++;
            if (reads == 2) {
              return h.json({'message': 'Synthetic read failure'}, 503);
            }
            if (reads == 3) return retryRead.future;
            return h.json({
              'data': [
                row('A long synthetic conversation title', muted: reads > 1),
              ],
            });
          },
        );
      },
    );
  }
}

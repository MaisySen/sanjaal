// Synthetic unavailable/read failures. No live post access or deletion.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(
            Future.value(ByteData.sublistView(File(font.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final lang in ['en', 'ne']) {
    for (final landscape in [false, true]) {
      for (final status in [404, 410, 503]) {
        testWidgets(
          'post read state stays localized and readable $status $lang landscape=$landscape',
          (t) async {
            prefs.lang = lang;
            addTearDown(() => prefs.lang = 'en');
            t.view.physicalSize = landscape
                ? const Size(640, 320)
                : const Size(320, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            var reads = 0;
            final message = List.filled(
              12,
              'Synthetic service detail.',
            ).join(' ');
            await h.fixture(
              t,
              (s, c) async {
                await t.pumpWidget(
                  MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildTheme(
                      lang == 'en' ? Brightness.light : Brightness.dark,
                      fontFamily: 'Roboto',
                      fontFamilyFallback: ['NotoDev'],
                    ),
                    builder: (context, w) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(1.8)),
                      child: w!,
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RepaintBoundary(
                                key: const ValueKey('review'),
                                child: PostPage(session: s, postId: 'fixture'),
                              ),
                            ),
                          ),
                          child: const Text('Open fixture'),
                        ),
                      ),
                    ),
                  ),
                );
                await t.tap(find.text('Open fixture'));
                await h.flush(t);
                await t.pumpAndSettle();
                expect(reads, 1);
                expect(t.takeException(), isNull);
                if (status != 503) {
                  expect(find.text(t_('Post unavailable')), findsOneWidget);
                  expect(
                    find.text(
                      t_(
                        'This post was removed or is no longer available to you.',
                      ),
                    ),
                    findsOneWidget,
                  );
                  if (lang == 'ne') {
                    expect(find.text('Post unavailable'), findsNothing);
                  }
                } else {
                  await t.ensureVisible(find.text(t_('Try again')));
                  await t.pumpAndSettle();
                  expect(
                    find.text(t_('Try again')).hitTestable(),
                    findsOneWidget,
                  );
                  expect(t.takeException(), isNull);
                }
                await p.shot(
                  t,
                  'post_read_${status}_${lang}_${landscape ? 'landscape' : 'portrait'}',
                );
                await t.pageBack();
                await t.pumpAndSettle();
                expect(find.text('Open fixture'), findsOneWidget);
              },
              respond: (r) async {
                reads++;
                return h.json({'message': message}, status);
              },
            );
          },
        );
      }
    }
  }
}

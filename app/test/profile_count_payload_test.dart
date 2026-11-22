// Synthetic malformed profile refresh only. No live profile/account operation.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

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
  for (final language in ['en', 'ne']) {
    testWidgets(
      'own profile unknown counts are not a successful zero $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var reads = 0;
        await p.fixture(
          t,
          (s) => MePage(session: s),
          () async {
            expect(find.text('0'), findsNothing);
            expect(find.text('-'), findsNWidgets(3));
            expect(
              t
                  .widgetList<Text>(find.text('-'))
                  .every((v) => v.semanticsLabel == t_('Unavailable')),
              isTrue,
            );
            expect(
              find.text(t_('Profile could not be loaded.')),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
            await p.shot(t, 'profile_counts_unknown_$language');
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(find.text('9'), findsOneWidget);
            expect(find.text('-'), findsNothing);
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: language == 'ne' ? Brightness.dark : Brightness.light,
          scale: 1.8,
          respond: (r) async => r.url.path.contains('/users/')
              ? p.json({
                  'user': {
                    ...p.person(followers: 9),
                    if (++reads == 1) 'followers_count': 'invalid-fixture',
                  },
                })
              : p.json({'data': [], 'next_cursor': null}),
        );
      },
    );
  }
  for (final own in [false, true]) {
    for (final invalid in <String, Object>{
      'followers_count': 'invalid-fixture',
      'posts_count': -1,
      'following_count': true,
    }.entries) {
      testWidgets(
        '${own ? 'own' : 'other'} profile retains counts after malformed ${invalid.key} refresh',
        (t) async {
          var reads = 0;
          await p.fixture(
            t,
            (s) => own
                ? MePage(session: s)
                : UserProfilePage(session: s, username: 'asha'),
            () async {
              expect(find.text('9'), findsOneWidget);
              t
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == 'Refresh profile',
                    ),
                  )
                  .onPressed!();
              await p.flush(t);
              expect(t.takeException(), isNull);
              expect(find.text('9'), findsOneWidget);
              expect(find.text('Profile could not be loaded.'), findsOneWidget);
              await t.tap(find.text('Try again'));
              await p.flush(t);
              expect(find.text('11'), findsOneWidget);
              expect(find.text('Profile could not be loaded.'), findsNothing);
              expect(t.takeException(), isNull);
            },
            respond: (r) async => r.url.path.contains('/users/')
                ? p.json({
                    'user': {
                      ...p.person(followers: reads < 2 ? 9 : 11),
                      if (++reads == 2) invalid.key: invalid.value,
                    },
                  })
                : p.json({'data': [], 'next_cursor': null}),
          );
        },
      );
    }
  }
}

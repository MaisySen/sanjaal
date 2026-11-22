// Synthetic empty feeds only. No live collection, search, follow or post.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/feed_page.dart';
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
    for (final kind in ['home', 'following', 'saved', 'hashtag', 'default']) {
      testWidgets(
        'empty feed copy respects locale $lang $kind at narrow large text',
        (t) async {
          prefs.lang = lang;
          addTearDown(() => prefs.lang = 'en');
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await h.fixture(t, (s, c) async {
            final page = switch (kind) {
              'saved' => SavedPage(session: s),
              'hashtag' => HashtagPage(session: s, tag: 'Nepal2026'),
              'default' => Scaffold(
                body: FeedList(session: s, query: const {}),
              ),
              _ => FeedPage(session: s, onCompose: () async {}),
            };
            await t.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('review'),
                child: MaterialApp(
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
                  home: page,
                ),
              ),
            );
            await h.flush(t);
            await t.pumpAndSettle();
            if (kind == 'following') {
              await t.tap(find.text(t_('Following')));
              await h.flush(t);
              await t.pumpAndSettle();
            }
            final original = switch (kind) {
              'home' => 'Nothing here yet',
              'following' => 'Follow people to fill this tab',
              'saved' => 'Nothing saved yet',
              'hashtag' => 'No posts with #Nepal2026 yet',
              _ => 'No posts yet',
            };
            final expected = kind == 'hashtag'
                ? t_('No posts with {tag} yet')
                      .replaceFirst('{tag}', '#Nepal2026')
                : t_(original);
            expect(find.text(expected), findsOneWidget);
            if (lang == 'ne') expect(find.text(original), findsNothing);
            if (kind == 'saved') {
              expect(
                find.text(
                  t_(
                    'Open the menu on a post and choose Save. Only you can see this list.',
                  ),
                ),
                findsOneWidget,
              );
            }
            await t.ensureVisible(find.text(expected));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await p.shot(t, 'empty_feed_${kind}_$lang');
          });
        },
      );
    }
  }
}

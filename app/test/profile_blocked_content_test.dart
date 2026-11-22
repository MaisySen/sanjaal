// Synthetic cached/pending profile feeds and moderation only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/post_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;
import 'profile_menu_ownership_test.dart' as m;
import 'profile_menu_recovery_test.dart' as r;

Map<String, dynamic> post() => {
  'public_id': 'cached-post',
  'kind': 'post',
  'body': 'Previously visible post',
  'media': [],
  'author': {'public_id': 'asha', 'username': 'asha'},
  'likes_count': 0,
  'comments_count': 0,
};
void main() {
  visualCases();
  for (final pending in [false, true]) {
    testWidgets(
      'covered block retires ${pending ? 'pending' : 'cached'} profile content',
      (t) async {
        final block = Completer<http.Response>(),
            feed = Completer<http.Response>();
        var writes = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await p.flush(t);
            VoidCallback? oldTile;
            if (!pending) {
              expect(find.text('Previously visible post'), findsOneWidget);
              oldTile = t
                  .widget<InkWell>(
                    find
                        .ancestor(
                          of: find.text('Previously visible post'),
                          matching: find.byType(InkWell),
                        )
                        .first,
                  )
                  .onTap;
            }
            m.menu(t)('block');
            await p.flush(t);
            await t.tap(find.text('Block'));
            await p.flush(t);
            await m.cover(t);
            block.complete(p.json({'blocked': true}));
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Keep this route'), findsOneWidget);
            await t.pageBack();
            await p.flush(t);
            await t.pumpAndSettle();
            if (pending) {
              feed.complete(
                p.json({
                  'data': [post()],
                  'next_cursor': null,
                }),
              );
              await p.flush(t);
            }
            expect(find.byType(FeedList, skipOffstage: false), findsNothing);
            expect(find.text('Previously visible post'), findsNothing);
            oldTile?.call();
            await p.flush(t);
            expect(find.byType(PostPage), findsNothing);
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (request) async {
            if (request.method == 'POST') {
              writes++;
              return block.future;
            }
            if (request.url.path.endsWith('/users/asha')) {
              return p.json({'user': m.person(writes > 0)});
            }
            if (request.url.path.endsWith('/posts')) {
              return pending
                  ? feed.future
                  : p.json({
                      'data': [post()],
                      'next_cursor': null,
                    });
            }
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  testWidgets(
    'blocked profile does not load content until a verified Unblock read',
    (t) async {
      var reads = 0, feeds = 0, writes = 0;
      await p.fixture(
        t,
        (s) => UserProfilePage(session: s, username: 'asha'),
        () async {
          expect(feeds, 0);
          expect(find.byType(FeedList), findsNothing);
          await r.choose(t, 'Unblock');
          await p.flush(t);
          expect(reads, 2);
          expect(feeds, 1);
          expect(writes, 1);
          expect(find.text('Previously visible post'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        respond: (request) async {
          if (request.method == 'DELETE') {
            writes++;
            return p.json({'blocked': false});
          }
          if (request.url.path.endsWith('/users/asha')) {
            return p.json({'user': m.person(++reads == 1)});
          }
          if (request.url.path.endsWith('/posts')) {
            feeds++;
            return p.json({
              'data': writes > 0 ? [post()] : [],
              'next_cursor': null,
            });
          }
          return p.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );
}

void visualCases() {
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
      'blocked content status is reachable at narrow large text $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var feeds = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await t.ensureVisible(find.text(t_('This member is blocked.')));
            await p.flush(t);
            expect(feeds, 0);
            expect(find.byType(FeedList), findsNothing);
            final bounds = t.getRect(find.text(t_('This member is blocked.')));
            expect(bounds.top, greaterThanOrEqualTo(56));
            expect(bounds.bottom, lessThanOrEqualTo(640));
            await p.shot(t, 'profile_blocked_content_$language');
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: language == 'en' ? Brightness.light : Brightness.dark,
          scale: 1.8,
          respond: (request) async {
            if (request.url.path.endsWith('/users/asha')) {
              return p.json({'user': m.person(true)});
            }
            if (request.url.path.endsWith('/posts')) feeds++;
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
}

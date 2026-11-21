// Real current-tree widget layouts with synthetic replies. Not device evidence.
import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;

http.Response fixtureJson(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  setUpAll(() async {
    for (final p in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final loader = FontLoader(
        p.$1,
      )..addFont(File(p.$2).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  for (final page in ['feed', 'chat', 'chats']) {
    for (final lang in ['en', 'ne']) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final scale in [1.0, 1.8]) {
          testWidgets('reviewed $page $lang ${brightness.name} $scale', (
            t,
          ) async {
            prefs.lang = lang;
            addTearDown(() => prefs.lang = 'en');
            t.view.physicalSize = Size(
              scale == 1 ? 390 : 320,
              scale == 1 ? 844 : 640,
            );
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            final key = GlobalKey();
            await h.fixture(
              t,
              (s, c) async {
                await t.pumpWidget(
                  RepaintBoundary(
                    key: key,
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: buildTheme(
                        brightness,
                        fontFamily: 'Roboto',
                        fontFamilyFallback: ['NotoDev'],
                      ),
                      builder: (context, w) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: w!,
                      ),
                      home: page == 'feed'
                          ? FeedPage(session: s, onCompose: () async {})
                          : page == 'chats'
                          ? ChatsPage(session: s)
                          : ChatPage(
                              session: s,
                              convo: {
                                'public_id': 'conversation',
                                'type': 'group',
                                'title': lang == 'ne'
                                    ? 'समुदायको कुराकानी'
                                    : 'Community music',
                                'members': [{}, {}],
                              },
                            ),
                    ),
                  ),
                );
                await h.flush(t);
                expect(t.takeException(), isNull);
                if (page == 'feed') {
                  expect(
                    t
                        .renderObject<RenderParagraph>(find.text(t_('For you')))
                        .didExceedMaxLines,
                    isFalse,
                  );
                }
                expect(
                  find.text(
                    page == 'feed'
                        ? (lang == 'ne'
                              ? 'आजको साँझ समुदायसँग।'
                              : 'An evening with our community.')
                        : page == 'chat'
                        ? (lang == 'ne' ? 'धन्यवाद' : 'Looking forward to it')
                        : 'Community music',
                  ),
                  findsOneWidget,
                );
                await t.runAsync(() async {
                  final image =
                      await (key.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage(pixelRatio: 2);
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final out = Directory(
                    Platform.environment['REVIEW_RENDER_DIR'] ??
                        'test/renders/reviewed-content',
                  )..createSync(recursive: true);
                  File('${out.path}/$page-$lang-${brightness.name}-$scale.png')
                      .writeAsBytesSync(data!.buffer.asUint8List());
                });
              },
              respond: (r) async {
                final path = r.url.path;
                if (path.endsWith('/stories')) {
                  return fixtureJson({
                    'data': [
                      {
                        'author': {
                          'public_id': 'asha',
                          'name': 'Asha Gurung',
                          'username': 'asha',
                        },
                        'all_viewed': false,
                        'items': [],
                      },
                      {
                        'author': {
                          'public_id': 'sita',
                          'name': 'Sita Rai',
                          'username': 'sita',
                        },
                        'all_viewed': true,
                        'items': [],
                      },
                    ],
                  });
                }
                if (path.endsWith('/posts')) {
                  return fixtureJson({
                    'data': [
                      {
                        'public_id': 'post',
                        'kind': 'post',
                        'body': lang == 'ne'
                            ? 'आजको साँझ समुदायसँग।'
                            : 'An evening with our community.',
                        'media': [],
                        'author': {
                          'public_id': 'asha',
                          'name': 'Asha Gurung',
                          'username': 'asha',
                        },
                        'likes_count': 128,
                        'comments_count': 24,
                        'my_reaction': null,
                        'reactions': {'like': 128},
                        'created_at': '2026-11-21T00:00:00Z',
                      },
                    ],
                    'next_cursor': null,
                  });
                }
                if (path.endsWith('/conversations')) {
                  return fixtureJson({
                    'data': [
                      {
                        'public_id': 'conversation',
                        'type': 'group',
                        'title': 'Community music',
                        'unread': 12,
                        'pinned': true,
                        'last_message': {
                          'kind': 'text',
                          'body': lang == 'ne'
                              ? 'भोलि भेटौँला'
                              : 'See you tomorrow',
                          'created_at': '2026-11-21T00:00:00Z',
                        },
                      },
                    ],
                  });
                }
                if (path.endsWith('/messages')) {
                  return fixtureJson({
                    'data': r.url.queryParameters.containsKey('after_seq')
                        ? []
                        : [
                            {
                              'public_id': 'm1',
                              'seq': 1,
                              'kind': 'text',
                              'body': lang == 'ne'
                                  ? 'भोलि भेटौँला'
                                  : 'See you tomorrow',
                              'sender': {
                                'public_id': 'asha',
                                'username': 'asha',
                              },
                              'created_at': '2026-11-21T00:00:00Z',
                            },
                            {
                              'public_id': 'm2',
                              'seq': 2,
                              'kind': 'text',
                              'body': lang == 'ne'
                                  ? 'धन्यवाद'
                                  : 'Looking forward to it',
                              'reply_to': {
                                'sender': 'asha',
                                'kind': 'text',
                                'body': lang == 'ne'
                                    ? 'भोलि भेटौँला'
                                    : 'See you tomorrow',
                              },
                              'sender': {
                                'public_id': 'me',
                                'username': 'fixture',
                              },
                              'created_at': '2026-11-21T00:00:00Z',
                            },
                          ],
                  });
                }
                return fixtureJson({});
              },
            );
          });
        }
      }
    }
  }
}

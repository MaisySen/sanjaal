// Synthetic share recipients, receipts and lost replies. Never sends a real message.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sanjaal/share_post.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'share_sheet_session_test.dart' as h;
import 'profile_journey_test.dart' as p;

Map<String, dynamic> receipt(http.Request r) => {
  'message': {
    'public_id': 'message',
    'conversation_id': r.url.pathSegments[r.url.pathSegments.length - 2],
    'client_id': jsonDecode(r.body)['client_id'],
    'kind': 'post',
    'sender': {'public_id': 'me'},
    'shared_post': {'public_id': 'post'},
  },
};
Future<void> fixture(
  WidgetTester t,
  Future<void> Function() run,
  Future<http.Response> Function(http.Request) send, {
  void Function()? closed,
  void Function(Session)? onSession,
  Future<http.Response> Function(http.Request)? read,
  String language = 'en',
  double scale = 1,
}) async {
  prefs.lang = language;
  addTearDown(() => prefs.lang = 'en');
  SharedPreferences.setMockInitialValues({});
  await http.runWithClient(
    () async {
      final s = Session();
      await s.login('fixture', 'fixture');
      onSession?.call(s);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('review'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(
              language == 'ne' ? Brightness.dark : Brightness.light,
              fontFamily: 'Roboto',
              fontFamilyFallback: ['NotoDev'],
            ),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!,
            ),
            home: Builder(
              builder: (c) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    await shareToChat(c, s, 'post');
                    closed?.call();
                  },
                  child: const Text('Open share'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open share'));
      await h.flush(t);
      await run();
      await t.pumpWidget(const SizedBox());
      await h.flush(t);
    },
    () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        return h.reply({'access_token': 'fixture', 'expires_in': 3600});
      }
      if (r.url.path.endsWith('/auth/me')) {
        return h.reply({
          'user': {'public_id': 'me', 'username': 'fixture'},
        });
      }
      if (r.method == 'POST') return send(r);
      if (read != null) return read(r);
      return h.reply({
        'data': [
          {'public_id': 'chat', 'title': 'Original chat'},
          {'public_id': 'other', 'title': 'Another chat'},
        ],
      });
    }),
  );
}

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
  testWidgets(
    'share retries lost receipt with the original logical message identity',
    (t) async {
      final committed = <String>{};
      var attempts = 0, closed = false;
      await fixture(
        t,
        () async {
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          expect(closed, isFalse);
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          expect(attempts, 2);
          expect(committed.length, 1);
          expect(closed, isTrue);
          expect(t.takeException(), isNull);
        },
        (r) async {
          committed.add(jsonDecode(r.body)['client_id'] as String);
          if (++attempts == 1) {
            throw http.ClientException('fixture lost reply after commit');
          }
          return h.reply(receipt(r));
        },
        closed: () => closed = true,
      );
    },
  );
  testWidgets('normal explicit close cannot race a retained send callback', (
    t,
  ) async {
    var writes = 0, closed = false;
    await fixture(
      t,
      () async {
        final send = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Original chat'))
            .onTap!;
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Close',
              ),
            )
            .onPressed!();
        send();
        await h.flush(t);
        expect(writes, 0);
        expect(closed, isTrue);
        expect(t.takeException(), isNull);
      },
      (r) async {
        writes++;
        return h.reply(receipt(r));
      },
      closed: () => closed = true,
    );
  });
  testWidgets(
    'unconfirmed share holds original recipient against another retained callback',
    (t) async {
      var writes = 0;
      await fixture(
        t,
        () async {
          final other = t
              .widget<ListTile>(find.widgetWithText(ListTile, 'Another chat'))
              .onTap!;
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          other();
          await h.flush(t);
          expect(writes, 1);
          expect(
            t
                .widget<ListTile>(find.widgetWithText(ListTile, 'Another chat'))
                .onTap,
            isNull,
          );
          expect(
            find.text(t_('Delivery unconfirmed. Tap to retry.')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        },
        (r) async {
          writes++;
          throw http.ClientException('fixture lost receipt');
        },
      );
    },
  );
  testWidgets(
    'busy share ignores duplicate callbacks and cannot close while checking',
    (t) async {
      final pending = Completer<http.Response>();
      http.Request? sent;
      var writes = 0, closed = false;
      await fixture(
        t,
        () async {
          final send = t
              .widget<ListTile>(find.widgetWithText(ListTile, 'Original chat'))
              .onTap!;
          send();
          send();
          await h.flush(t);
          await t.tap(find.byTooltip('Close'));
          await h.flush(t);
          expect(writes, 1);
          expect(closed, isFalse);
          expect(find.byType(AlertDialog), findsNothing);
          pending.complete(h.reply(receipt(sent!)));
          await h.flush(t);
          expect(closed, isTrue);
          expect(t.takeException(), isNull);
        },
        (r) {
          sent = r;
          writes++;
          return pending.future;
        },
        closed: () => closed = true,
      );
    },
  );
  testWidgets('confirmed share may have no current preview and still closes', (
    t,
  ) async {
    var closed = false;
    await fixture(
      t,
      () async {
        await t.tap(find.text('Original chat'));
        await h.flush(t);
        expect(closed, isTrue);
        expect(t.takeException(), isNull);
      },
      (r) async {
        final data = receipt(r);
        (data['message'] as Map)['shared_post'] = null;
        return h.reply(data);
      },
      closed: () => closed = true,
    );
  });
  testWidgets(
    'retiring session closes an old unconfirmed-exit dialog without another request',
    (t) async {
      late Session s;
      var writes = 0;
      await fixture(
        t,
        () async {
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          await t.tap(find.byTooltip('Close'));
          await h.flush(t);
          expect(find.byType(AlertDialog), findsOneWidget);
          await s.login('fixture', 'fixture');
          await h.flush(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.textContaining('another signed-in session'),
            findsOneWidget,
          );
          expect(writes, 1);
          expect(t.takeException(), isNull);
        },
        (r) async {
          writes++;
          throw http.ClientException('fixture lost receipt');
        },
        onSession: (value) => s = value,
      );
    },
  );
  testWidgets('system Back asks before abandoning an unconfirmed share', (
    t,
  ) async {
    var closed = false;
    await fixture(
      t,
      () async {
        await t.tap(find.text('Original chat'));
        await h.flush(t);
        await t.binding.handlePopRoute();
        await h.flush(t);
        expect(find.text('Close without confirming delivery?'), findsOneWidget);
        expect(closed, isFalse);
        await t.tap(find.widgetWithText(TextButton, 'Keep checking'));
        await h.flush(t);
        expect(find.text('Original chat'), findsOneWidget);
        expect(closed, isFalse);
        expect(t.takeException(), isNull);
      },
      (r) async => throw http.ClientException('fixture lost receipt'),
      closed: () => closed = true,
    );
  });
  for (final language in ['en', 'ne']) {
    testWidgets('unconfirmed share explicit exit remains readable $language', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var writes = 0, closed = false;
      await fixture(
        t,
        () async {
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          await t.pumpAndSettle();
          await p.shot(t, 'share_unconfirmed_$language');
          await t.tapAt(const Offset(8, 8));
          await h.flush(t);
          await t.drag(find.text(t_('Share to chat')), const Offset(0, 400));
          await h.flush(t);
          expect(closed, isFalse);
          await t.tap(find.byTooltip(t_('Close')));
          await h.flush(t);
          await t.pumpAndSettle();
          final keep = find.widgetWithText(TextButton, t_('Keep checking'));
          await t.ensureVisible(keep);
          await t.pumpAndSettle();
          await p.shot(t, 'share_unconfirmed_exit_$language');
          await t.tap(keep);
          await h.flush(t);
          expect(closed, isFalse);
          await t.tap(find.byTooltip(t_('Close')));
          await h.flush(t);
          final close = find.widgetWithText(TextButton, t_('Close'));
          await t.ensureVisible(close);
          await t.tap(close);
          await h.flush(t);
          expect(closed, isTrue);
          expect(writes, 1);
          expect(t.takeException(), isNull);
        },
        (r) async {
          writes++;
          throw http.ClientException('fixture lost receipt');
        },
        closed: () => closed = true,
        language: language,
        scale: 1.8,
      );
    });
  }
  for (final invalid in <Object>[
    {
      'data': [
        {'public_id': '', 'title': 'Unknown'},
      ],
    },
    {
      'data': [
        {'public_id': 'chat', 'title': 42},
      ],
    },
    {'data': {}},
  ]) {
    testWidgets('malformed share recipient list is retryable $invalid', (
      t,
    ) async {
      var reads = 0, writes = 0;
      await fixture(
        t,
        () async {
          expect(find.text('Chats could not be loaded.'), findsOneWidget);
          expect(find.byType(ListTile), findsNothing);
          await t.tap(find.text('Try again'));
          await h.flush(t);
          expect(find.text('Original chat'), findsOneWidget);
          expect(writes, 0);
          expect(reads, 2);
          expect(t.takeException(), isNull);
        },
        (r) async {
          writes++;
          return h.reply(receipt(r));
        },
        read: (r) async => ++reads == 1
            ? h.reply(invalid)
            : h.reply({
                'data': [
                  {'public_id': 'chat', 'title': 'Original chat'},
                ],
              }),
      );
    });
  }
  for (final mismatch in [
    'empty',
    'recipient',
    'client',
    'sender',
    'kind',
    'post',
  ]) {
    testWidgets('share does not claim Sent for $mismatch receipt', (t) async {
      var closed = false;
      await fixture(
        t,
        () async {
          await t.tap(find.text('Original chat'));
          await h.flush(t);
          expect(closed, isFalse);
          expect(find.textContaining('Sent to'), findsNothing);
          expect(find.text('Original chat'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        (r) async {
          final data = receipt(r);
          final message = data['message'] as Map<String, dynamic>;
          switch (mismatch) {
            case 'empty':
              return h.reply({});
            case 'recipient':
              message['conversation_id'] = 'other';
            case 'client':
              message['client_id'] = 'another';
            case 'sender':
              message['sender'] = {'public_id': 'other'};
            case 'kind':
              message['kind'] = 'text';
            case 'post':
              message['shared_post'] = {'public_id': 'other-post'};
          }
          return h.reply(data);
        },
        closed: () => closed = true,
      );
    });
  }
}

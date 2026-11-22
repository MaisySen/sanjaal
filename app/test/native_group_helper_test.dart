// Offline native-helper rehearsal with a held inbox refresh, not device proof.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/main.dart' show buildTheme;

import 'upload_center_test.dart' as h;
import '../integration_test/native_group_journey.dart';

void main() {
  setUpAll(() async {
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
      await (FontLoader(p.$1)..addFont(
            Future.value(ByteData.sublistView(File(p.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  testWidgets(
    'native group helper waits for inbox read and completes member changes',
    (t) async {
      t.view.physicalSize = const Size(402, 874);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const me = '20000000-0000-4000-8000-000000000001';
      const asha = '20000000-0000-4000-8000-000000000002';
      const bikram = '20000000-0000-4000-8000-000000000003';
      const group = '10000000-0000-4000-8000-000000000001';
      final people = [
        {
          'public_id': me,
          'username': 'synthetic_member',
          'name': 'Synthetic Member',
        },
        {'public_id': asha, 'username': 'asha_e2e', 'name': 'Asha Gurung'},
        {'public_id': bikram, 'username': 'bikram_e2e', 'name': 'Bikram Test'},
      ];
      var removed = false, transferred = false, created = false;
      var creates = 0, removals = 0, handoffs = 0, inboxReads = 0;
      final heldInbox = Completer<http.Response>();
      final sent = <Map<String, dynamic>>[];
      final captures = <String>[];
      Map<String, dynamic> snapshot() => {
        'public_id': group,
        'type': 'group',
        'title': 'Native group review',
        'my_role': transferred ? 'member' : 'owner',
        'ownership_revision':
            (transferred
                ? 'c'
                : removed
                ? 'b'
                : 'a') *
            64,
        'members': [
          for (final person in people)
            if (!removed || person['public_id'] != bikram)
              {
                ...person,
                'group_role': person['public_id'] == (transferred ? asha : me)
                    ? 'owner'
                    : 'member',
              },
        ],
      };
      await h.fixture(
        t,
        (s, _) async {
          s.user = people.first;
          s.groupOwnershipEnabled = true;
          s.groupMemberRemovalEnabled = true;
          final renderKey = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: renderKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(
                  Brightness.light,
                  fontFamily: 'Roboto',
                  fontFamilyFallback: ['NotoDev'],
                ),
                home: ChatsPage(session: s),
              ),
            ),
          );
          await h.flush(t);
          await t.tap(find.text('Asha Gurung'));
          await h.flush(t);
          await t.pageBack();
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 200));
          }
          await t.tap(find.widgetWithText(TextButton, 'Live rooms'));
          await h.flush(t);
          await t.pageBack();
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 200));
          }
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  w.tooltip == 'New chat' &&
                  w.onPressed == null,
            ),
            findsOneWidget,
          );
          var waits = 0;
          Future<void> waitUntil(bool Function() ready) async {
            waits++;
            for (var i = 0; i < 100; i++) {
              // The old helper taps the disabled entry before this read settles.
              if (!heldInbox.isCompleted) {
                heldInbox.complete(h.json({'data': [], 'next_cursor': null}));
              }
              await t.pump(const Duration(milliseconds: 200));
              t.view.viewInsets = FakeViewPadding(
                bottom: t.testTextInput.isVisible ? 300 : 0,
              );
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 2)),
              );
              if (ready()) return;
            }
            throw TestFailure(
              'Group helper wait $waits did not settle. Visible: ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList()}',
            );
          }

          try {
            await nativeGroupJourney(
              t,
              s,
              waitUntil: waitUntil,
              capture: (name) async {
                captures.add(name);
                final folder =
                    Platform.environment['SANJAAL_GROUP_HELPER_WIDGET_OUTPUT'];
                if (folder != null) {
                  await t.runAsync(() async {
                    final boundary =
                        renderKey.currentContext!.findRenderObject()
                            as RenderRepaintBoundary;
                    final image = await boundary.toImage(pixelRatio: 2);
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    Directory(folder).createSync(recursive: true);
                    File('$folder/widget_$name.png')
                        .writeAsBytesSync(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
              },
              stage: (_) async {},
            );
            expect(captures, [
              'ios_group_created',
              'ios_group_remove_confirm',
              'ios_group_removed',
              'ios_group_owner_confirm',
              'ios_group_transferred',
              'ios_group_member_role',
            ]);
            expect([creates, removals, handoffs], [1, 1, 1]);
            expect(sent.length, 2);
            expect(transferred, isTrue);
            expect(removed, isTrue);
            expect(t.takeException(), isNull);
          } finally {
            if (!heldInbox.isCompleted) {
              heldInbox.complete(h.json({'data': []}));
            }
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 4));
          }
        },
        respond: (r) async {
          final path = r.url.path;
          if (path.endsWith('/users/search')) {
            final query = r.url.queryParameters['q'];
            return h.json({
              'users': people.where((p) => p['username'] == query).toList(),
            });
          }
          if (path.endsWith('/conversations')) {
            if (r.method == 'POST') {
              creates++;
              created = true;
              final body = jsonDecode(r.body) as Map;
              expect(body['usernames'], ['asha_e2e', 'bikram_e2e']);
              return h.json({'conversation': snapshot()});
            }
            if (++inboxReads == 2) return heldInbox.future;
            return h.json({
              'data': created
                  ? [snapshot()]
                  : [
                      {
                        'public_id': 'direct',
                        'type': 'direct',
                        'title': 'Asha Gurung',
                        'members': people.take(2).toList(),
                      },
                    ],
              'next_cursor': null,
            });
          }
          if (path.endsWith('/conversations/$group/messages')) {
            if (r.method == 'POST') {
              final body = jsonDecode(r.body) as Map;
              final message = <String, dynamic>{
                'public_id': 'message-${sent.length}',
                'seq': sent.length + 1,
                'sender': people.first,
                'kind': 'text',
                'body': body['body'],
                'client_id': body['client_id'],
                'created_at': '2026-11-22T00:00:00Z',
              };
              sent.add(message);
              return h.json({'message': message});
            }
            return h.json({'data': sent, 'typing': [], 'has_more': false});
          }
          if (path.endsWith('/conversations/$group') && r.method == 'GET') {
            return h.json({'conversation': snapshot()});
          }
          if (r.method == 'POST' && path.endsWith('/member-removals')) {
            expect(jsonDecode(r.body), {
              'member_id': bikram,
              'ownership_revision': 'a' * 64,
            });
            removals++;
            removed = true;
            return h.json({'conversation': snapshot()});
          }
          if (r.method == 'POST' && path.endsWith('/ownership')) {
            expect(jsonDecode(r.body), {
              'member_id': asha,
              'ownership_revision': 'b' * 64,
            });
            handoffs++;
            transferred = true;
            return h.json({'conversation': snapshot()});
          }
          if (path.endsWith('/messages') && path.contains('/direct/')) {
            return h.json({'data': [], 'typing': []});
          }
          if (path.endsWith('/rooms') && r.method == 'GET') {
            return h.json({'data': []});
          }
          return h.json({});
        },
      );
    },
  );
}

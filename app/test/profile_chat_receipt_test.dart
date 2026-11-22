// Synthetic profile-to-chat receipts only. No live creation or message read.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'upload_center_test.dart' as h;
import 'profile_identity_read_test.dart' as identity;
import 'profile_journey_test.dart' as p;

const recovery =
    'Could not verify this chat. Refresh the profile and try again.';
Map<String, dynamic> conversation() => {
  'public_id': 'created-chat',
  'type': 'direct',
  'title': 'Selected member',
  'members': [
    {'public_id': 'me', 'username': 'fixture'},
    {'public_id': 'asha', 'username': 'asha'},
  ],
};
VoidCallback message(WidgetTester t) => t
    .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, t_('Message')))
    .onPressed!;
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
  for (final shape in [
    'wrong recipient',
    'wrong current member',
    'group',
    'missing members',
    'blank ID',
    'missing type',
    'nonstrings ID',
    'wrong target username',
    'duplicate target',
    'extra member',
    'members map',
    'malformed member',
    'missing owner username',
    'response list',
    'conversation scalar',
  ]) {
    testWidgets(
      'profile Message rejects $shape before opening or reading chat',
      (t) async {
        var writes = 0, reads = 0;
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(
              MaterialApp(
                home: UserProfilePage(session: s, username: 'asha'),
              ),
            );
            await h.flush(t);
            final old = message(t);
            await t.tap(find.text('Message'));
            await h.flush(t);
            expect(find.byType(ChatPage), findsNothing);
            expect(find.text(recovery), findsOneWidget);
            expect(find.text('8'), findsNWidgets(3));
            expect(
              t
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Message'),
                  )
                  .onPressed,
              isNull,
            );
            old();
            await h.flush(t);
            expect(writes, 1);
            expect(reads, 0);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              writes++;
              if (shape == 'response list') {
                return h.json([]);
              }
              if (shape == 'conversation scalar') {
                return h.json({'conversation': 1});
              }
              final value = conversation();
              if (shape == 'wrong recipient') {
                value['members'] = [
                  {'public_id': 'me', 'username': 'fixture'},
                  {'public_id': 'changed-person', 'username': 'asha'},
                ];
              }
              if (shape == 'wrong current member') {
                value['members'] = [
                  {'public_id': 'changed-owner', 'username': 'fixture'},
                  {'public_id': 'asha', 'username': 'asha'},
                ];
              }
              if (shape == 'group') {
                value['type'] = 'group';
              }
              if (shape == 'missing members') {
                value.remove('members');
              }
              if (shape == 'blank ID') {
                value['public_id'] = ' ';
              }
              if (shape == 'missing type') {
                value.remove('type');
              }
              if (shape == 'nonstrings ID') {
                value['public_id'] = 123;
              }
              if (shape == 'wrong target username') {
                value['members'] = [
                  {'public_id': 'me', 'username': 'fixture'},
                  {'public_id': 'asha', 'username': 'changed-name'},
                ];
              }
              if (shape == 'duplicate target') {
                value['members'] = [
                  {'public_id': 'asha', 'username': 'asha'},
                  {'public_id': 'asha', 'username': 'asha'},
                ];
              }
              if (shape == 'extra member') {
                value['members'] = [
                  ...value['members'],
                  {'public_id': 'third', 'username': 'third'},
                ];
              }
              if (shape == 'members map') {
                value['members'] = {};
              }
              if (shape == 'malformed member') {
                value['members'] = [
                  'bad',
                  {'public_id': 'asha', 'username': 'asha'},
                ];
              }
              if (shape == 'missing owner username') {
                value['members'] = [
                  {'public_id': 'me'},
                  {'public_id': 'asha', 'username': 'asha'},
                ];
              }
              return h.json({'conversation': value});
            }
            if (r.url.path.endsWith('/users/asha')) {
              return h.json({'user': identity.person('asha', 'asha', 8)});
            }
            if (r.url.path.contains('/conversations/')) {
              reads++;
            }
            return h.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  for (final reverse in [false, true]) {
    testWidgets(
      'verified direct receipt opens once and returns with member order $reverse',
      (t) async {
        var writes = 0, reads = 0;
        final response = Completer<http.Response>();
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(
              MaterialApp(
                home: UserProfilePage(session: s, username: 'asha'),
              ),
            );
            await h.flush(t);
            final old = message(t);
            old();
            old();
            await h.flush(t);
            final pendingWrites = writes;
            final pendingDisabled =
                t
                    .widget<OutlinedButton>(
                      find.widgetWithText(OutlinedButton, 'Message'),
                    )
                    .onPressed ==
                null;
            final value = conversation();
            if (reverse) {
              value['members'] = (value['members'] as List).reversed.toList();
            }
            response.complete(h.json({'conversation': value}));
            await h.flush(t);
            expect(pendingWrites, 1);
            expect(pendingDisabled, isTrue);
            expect(find.byType(ChatPage), findsOneWidget);
            expect(reads, greaterThanOrEqualTo(1));
            await t.pageBack();
            await t.pumpAndSettle();
            await h.flush(t);
            expect(find.byType(ChatPage), findsNothing);
            expect(message(t), isNotNull);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              writes++;
              expect(jsonDecode(r.body), {
                'type': 'direct',
                'username': 'asha',
              });
              return response.future;
            }
            if (r.url.path.endsWith('/users/asha')) {
              return h.json({'user': identity.person('asha', 'asha', 8)});
            }
            if (r.url.path.contains('/conversations/')) {
              reads++;
            }
            return h.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  for (final status in [200, 422, 503]) {
    testWidgets(
      'chat failure $status needs profile read before explicit next attempt',
      (t) async {
        var writes = 0, profileReads = 0;
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(
              MaterialApp(
                home: UserProfilePage(session: s, username: 'asha'),
              ),
            );
            await h.flush(t);
            final old = message(t);
            old();
            await h.flush(t);
            expect(find.text(recovery), findsOneWidget);
            old();
            await h.flush(t);
            expect(writes, 1);
            await t.tap(find.text('Try again'));
            await h.flush(t);
            expect(profileReads, 2);
            expect(writes, 1);
            expect(find.text(recovery), findsNothing);
            await t.tap(find.text('Message'));
            await h.flush(t);
            expect(writes, 2);
            expect(find.byType(ChatPage), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              return ++writes == 1
                  ? h.json(
                      status == 200
                          ? {'conversation': {}}
                          : {'message': 'Synthetic rejected or unavailable'},
                      status,
                    )
                  : h.json({'conversation': conversation()});
            }
            if (r.url.path.endsWith('/users/asha')) {
              profileReads++;
              return h.json({'user': identity.person('asha', 'asha', 8)});
            }
            return h.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  testWidgets(
    'a superseded profile read retires pending chat navigation and releases busy state',
    (t) async {
      var profileReads = 0, chatReads = 0;
      final response = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              home: UserProfilePage(session: s, username: 'asha'),
            ),
          );
          await h.flush(t);
          final refresh = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Refresh profile',
                ),
              )
              .onPressed!;
          message(t)();
          await h.flush(t);
          refresh();
          await h.flush(t);
          response.complete(h.json({'conversation': conversation()}));
          await h.flush(t);
          expect(profileReads, 2);
          expect(find.byType(ChatPage), findsNothing);
          expect(chatReads, 0);
          expect(message(t), isNotNull);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            return response.future;
          }
          if (r.url.path.endsWith('/users/asha')) {
            profileReads++;
            return h.json({'user': identity.person('asha', 'asha', 8)});
          }
          if (r.url.path.contains('/conversations/')) {
            chatReads++;
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );
  testWidgets('retained Message stays inert after a verified blocked refresh', (
    t,
  ) async {
    var profileReads = 0, writes = 0;
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            home: UserProfilePage(session: s, username: 'asha'),
          ),
        );
        await h.flush(t);
        final old = message(t);
        await t.tap(find.byTooltip('Refresh profile'));
        await h.flush(t);
        old();
        await h.flush(t);
        expect(writes, 0);
        expect(find.byType(ChatPage), findsNothing);
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.method == 'POST') {
          writes++;
          return h.json({'conversation': conversation()});
        }
        if (r.url.path.endsWith('/users/asha')) {
          return h.json({
            'user': {
              ...identity.person('asha', 'asha', 8),
              'blocked': ++profileReads > 1,
            },
          });
        }
        return h.json({'data': [], 'next_cursor': null});
      },
    );
  });
  for (final retire in ['same-member login', 'disposal']) {
    for (final failure in [false, true]) {
      testWidgets(
        'late chat ${failure ? 'error' : 'valid receipt'} after $retire stays silent',
        (t) async {
          final response = Completer<http.Response>();
          var chatReads = 0;
          await h.fixture(
            t,
            (s, c) async {
              await t.pumpWidget(
                MaterialApp(
                  home: UserProfilePage(session: s, username: 'asha'),
                ),
              );
              await h.flush(t);
              message(t)();
              await h.flush(t);
              if (retire == 'same-member login') {
                await s.login('fixture', 'not-a-password');
              } else {
                await t.pumpWidget(const SizedBox());
              }
              response.complete(
                failure
                    ? h.json({'message': 'Old chat error'}, 503)
                    : h.json({'conversation': conversation()}),
              );
              await h.flush(t);
              expect(find.byType(ChatPage), findsNothing);
              expect(find.text(recovery), findsNothing);
              expect(find.text('Old chat error'), findsNothing);
              expect(chatReads, 0);
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
                return response.future;
              }
              if (r.url.path.endsWith('/users/asha')) {
                return h.json({'user': identity.person('asha', 'asha', 8)});
              }
              if (r.url.path.contains('/conversations/')) {
                chatReads++;
              }
              return h.json({'data': [], 'next_cursor': null});
            },
          );
        },
      );
    }
  }
  testWidgets(
    'chat recovery cannot enable a replacement member at the same username',
    (t) async {
      var profileReads = 0, writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              home: UserProfilePage(session: s, username: 'asha'),
            ),
          );
          await h.flush(t);
          final old = message(t);
          old();
          await h.flush(t);
          await t.tap(find.text('Try again'));
          await h.flush(t);
          old();
          await h.flush(t);
          expect(find.text('Profile could not be loaded.'), findsOneWidget);
          expect(find.text('8'), findsNWidgets(3));
          expect(writes, 1);
          expect(find.byType(ChatPage), findsNothing);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            writes++;
            return h.json({'conversation': {}});
          }
          if (r.url.path.endsWith('/users/asha')) {
            return h.json({
              'user': identity.person(
                ++profileReads == 1 ? 'asha' : 'reassigned',
                'asha',
                profileReads == 1 ? 8 : 999,
              ),
            });
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'chat verification failure and profile recovery fit narrow large text $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var writes = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await t.ensureVisible(find.text(t_('Message')));
            await t.tap(find.text(t_('Message')));
            await p.flush(t);
            expect(find.text(t_(recovery)), findsOneWidget);
            expect(find.text(t_('Try again')), findsOneWidget);
            expect(t.takeException(), isNull);
            await p.shot(t, 'profile_chat_failure_$lang');
            await t.ensureVisible(find.text(t_('Message')));
            await t.pumpAndSettle();
            await p.shot(t, 'profile_chat_failure_actions_$lang');
            await t.ensureVisible(find.text(t_('Try again')));
            await t.pumpAndSettle();
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(find.text(t_(recovery)), findsNothing);
            expect(message(t), isNotNull);
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          language: lang,
          brightness: lang == 'ne' ? Brightness.dark : Brightness.light,
          scale: 1.8,
          respond: (r) async {
            if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
              writes++;
              return p.json({
                'conversation': {...conversation(), 'members': []},
              });
            }
            if (r.url.path.endsWith('/users/asha')) {
              return p.json({'user': identity.person('asha', 'asha', 8)});
            }
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
}

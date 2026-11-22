// Synthetic search selections and create receipts only. No live chat creation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'new_chat_journey_test.dart' as n;
import 'upload_center_test.dart' as h;

import 'package:sanjaal/ui.dart' show t_;

Map<String, dynamic> conversation() => {
  'public_id': 'created-chat',
  'type': 'direct',
  'title': 'Selected member',
  'members': [
    {'public_id': 'me', 'username': 'fixture'},
    {'public_id': 'a', 'username': 'asha'},
  ],
};
void main() {
  additionalCases();
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
  ]) {
    testWidgets('New chat does not return an inconsistent $shape receipt', (
      t,
    ) async {
      var writes = 0;
      await n.setup(
        t,
        () async {
          await n.search(t, 'asha');
          await t.tap(find.text('Asha Gurung'));
          await n.flush(t);
          await t.pumpAndSettle();
          expect(writes, 1);
          expect(find.byType(NewChatPage), findsOneWidget);
          expect(
            find.text(
              'The chat may already exist. Check Chats before starting it again.',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            writes++;
            final value = conversation();
            if (shape == 'wrong recipient') {
              value['members'] = [
                {'public_id': 'me', 'username': 'fixture'},
                {'public_id': 'replacement', 'username': 'asha'},
              ];
            }
            if (shape == 'wrong current member') {
              value['members'] = [
                {'public_id': 'replacement', 'username': 'fixture'},
                {'public_id': 'a', 'username': 'asha'},
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
            return n.reply({'conversation': value});
          }
          return n.reply({
            'users': [n.people.first],
          });
        },
      );
    });
  }
  for (final clear in [true, false]) {
    testWidgets(
      'stale search selection cannot create after ${clear ? 'clearing' : 'replacement'}',
      (t) async {
        var writes = 0;
        await n.setup(
          t,
          () async {
            await n.search(t, 'asha');
            final old = t.widget<ListTile>(find.byType(ListTile)).onTap!;
            await n.search(t, clear ? '' : 'other');
            old();
            await n.flush(t);
            await t.pumpAndSettle();
            expect(writes, 0);
            expect(find.byType(NewChatPage), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          (r) async {
            if (r.method == 'POST') {
              writes++;
              return n.reply({'conversation': conversation()});
            }
            return n.reply({
              'users': r.url.queryParameters['q'] == 'asha'
                  ? [n.people.first]
                  : [
                      {
                        'public_id': 'replacement',
                        'username': 'asha',
                        'name': 'Replacement member',
                      },
                    ],
            });
          },
        );
      },
    );
  }
}

void additionalCases() {
  for (final shape in ['valid', 'reversed', 'wrong person']) {
    testWidgets('actual inbox only opens $shape direct receipt when verified', (
      t,
    ) async {
      var posts = 0, chatReads = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: ChatsPage(session: s)));
          await h.flush(t);
          await t.tap(find.byTooltip('New chat'));
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'asha');
          await h.flush(t);
          await t.tap(find.text('Asha Gurung'));
          await h.flush(t);
          await t.pumpAndSettle();
          await h.flush(t);
          expect(posts, 1);
          if (shape == 'wrong person') {
            expect(find.byType(NewChatPage), findsOneWidget);
            expect(find.byType(ChatPage), findsNothing);
            expect(chatReads, 0);
          } else {
            expect(find.byType(NewChatPage), findsNothing);
            expect(find.byType(ChatPage), findsOneWidget);
            expect(chatReads, greaterThanOrEqualTo(1));
            await t.pageBack();
            await t.pumpAndSettle();
            await h.flush(t);
            expect(find.byType(ChatPage), findsNothing);
            expect(find.byType(ChatsPage), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'POST' && r.url.path.endsWith('/conversations')) {
            posts++;
            expect(jsonDecode(r.body), {'type': 'direct', 'username': 'asha'});
            final value = conversation();
            if (shape == 'reversed') {
              value['members'] = (value['members'] as List).reversed.toList();
            }
            if (shape == 'wrong person') {
              value['members'] = [
                {'public_id': 'me', 'username': 'fixture'},
                {'public_id': 'replacement', 'username': 'asha'},
              ];
            }
            return h.json({'conversation': value});
          }
          if (r.url.path.endsWith('/users/search')) {
            return h.json({
              'users': [n.people.first],
            });
          }
          if (r.url.path.contains('/conversations/')) {
            chatReads++;
          }
          return h.json({'data': [], 'next_cursor': null});
        },
      );
    });
  }
  for (final group in [false, true]) {
    for (final shape in [
      'missing',
      'blank',
      'numeric',
      'duplicate ID',
      'duplicate username',
    ]) {
      testWidgets(
        '${group ? 'group' : 'direct'} search rejects $shape identity without selectable rows',
        (t) async {
          var posts = 0;
          await n.setup(
            t,
            () async {
              if (group) {
                await t.tap(find.byTooltip('New group'));
                await n.flush(t);
              }
              await n.search(t, 'asha');
              expect(
                find.text('Could not load members. Try again.'),
                findsOneWidget,
              );
              expect(find.byType(ListTile), findsNothing);
              expect(find.byType(Checkbox), findsNothing);
              expect(posts, 0);
              expect(t.takeException(), isNull);
            },
            (r) async {
              if (r.method == 'POST') {
                posts++;
              }
              final person = Map<String, dynamic>.from(n.people.first);
              if (shape == 'missing') {
                person.remove('public_id');
              }
              if (shape == 'blank') {
                person['public_id'] = ' ';
              }
              if (shape == 'numeric') {
                person['public_id'] = 1;
              }
              return n.reply({
                'users': [
                  person,
                  if (shape == 'duplicate ID')
                    {...person, 'username': 'another'},
                  if (shape == 'duplicate username')
                    {...person, 'public_id': 'another'},
                ],
              });
            },
          );
        },
      );
    }
  }
  testWidgets(
    'retained search callback cannot alter a pending or uncertain direct request',
    (t) async {
      var posts = 0, searches = 0;
      final response = Completer<http.Response>();
      await n.setup(
        t,
        () async {
          await n.search(t, 'asha');
          final oldRow = t.widget<ListTile>(find.byType(ListTile)).onTap!;
          final oldQuery = t
              .widget<TextField>(find.byType(TextField))
              .onChanged!;
          oldRow();
          await n.flush(t);
          oldQuery('replacement');
          oldRow();
          await n.flush(t);
          final pendingPosts = posts, pendingSearches = searches;
          response.complete(n.reply({'conversation': {}}));
          await n.flush(t);
          oldQuery('replacement');
          oldRow();
          await n.flush(t);
          expect(pendingPosts, 1);
          expect(pendingSearches, 1);
          expect(posts, 1);
          expect(searches, 1);
          expect(
            find.text(
              'The chat may already exist. Check Chats before starting it again.',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            posts++;
            return response.future;
          }
          searches++;
          return n.reply({
            'users': [n.people.first],
          });
        },
      );
    },
  );
  testWidgets('retained row after disposal is inert', (t) async {
    var posts = 0;
    await n.setup(
      t,
      () async {
        await n.search(t, 'asha');
        final old = t.widget<ListTile>(find.byType(ListTile)).onTap!;
        await t.pumpWidget(const SizedBox());
        old();
        await n.flush(t);
        expect(posts, 0);
        expect(t.takeException(), isNull);
      },
      (r) async {
        if (r.method == 'POST') {
          posts++;
        }
        return n.reply({
          'users': [n.people.first],
        });
      },
    );
  });
  testWidgets(
    'current replacement row is still selectable after rejecting an old row',
    (t) async {
      var posts = 0;
      await n.setup(
        t,
        () async {
          await n.search(t, 'asha');
          final old = t.widget<ListTile>(find.byType(ListTile)).onTap!;
          await n.search(t, 'replacement');
          old();
          await n.flush(t);
          expect(posts, 0);
          await t.tap(find.text('Replacement member'));
          await n.flush(t);
          await t.pumpAndSettle();
          expect(posts, 1);
          expect(find.byType(NewChatPage), findsNothing);
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            posts++;
            return n.reply({
              'conversation': {
                ...conversation(),
                'members': [
                  {'public_id': 'me', 'username': 'fixture'},
                  {'public_id': 'replacement', 'username': 'asha'},
                ],
              },
            });
          }
          return n.reply({
            'users': r.url.queryParameters['q'] == 'asha'
                ? [n.people.first]
                : [
                    {
                      'public_id': 'replacement',
                      'username': 'asha',
                      'name': 'Replacement member',
                    },
                  ],
          });
        },
      );
    },
  );
  testWidgets(
    'explicit 422 rejection retains current selection for an explicit retry',
    (t) async {
      var posts = 0;
      await n.setup(
        t,
        () async {
          await n.search(t, 'asha');
          await t.tap(find.text('Asha Gurung'));
          await n.flush(t);
          expect(find.text('Check the details and try again.'), findsOneWidget);
          await t.tap(find.text('Asha Gurung'));
          await n.flush(t);
          await t.pumpAndSettle();
          expect(posts, 2);
          expect(find.byType(NewChatPage), findsNothing);
          expect(t.takeException(), isNull);
        },
        (r) async => r.method == 'POST'
            ? (++posts == 1
                  ? n.reply({'message': 'Synthetic rejection'}, 422)
                  : n.reply({'conversation': conversation()}))
            : n.reply({
                'users': [n.people.first],
              }),
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'unverified direct receipt recovery stays usable narrow large text $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var posts = 0;
        await n.setup(
          t,
          () async {
            await n.search(t, 'asha');
            await t.ensureVisible(find.text('Asha Gurung'));
            await t.tap(find.text('Asha Gurung'));
            await n.flush(t);
            await t.pumpAndSettle();
            final back = find.text(t_('Back to Chats'));
            await t.ensureVisible(back);
            await t.pumpAndSettle();
            expect(posts, 1);
            expect(t.takeException(), isNull);
            await t.runAsync(() async {
              final boundary = t.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('newchat-shot')),
              );
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory('test/renders').createSync(recursive: true);
              File('test/renders/new_chat_direct_receipt_$lang.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
            });
            await t.tap(back);
            await n.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(NewChatPage), findsNothing);
            expect(posts, 1);
            expect(t.takeException(), isNull);
          },
          (r) async {
            if (r.method == 'POST') {
              posts++;
              return n.reply({
                'conversation': {...conversation(), 'members': []},
              });
            }
            return n.reply({
              'users': [n.people.first],
            });
          },
          lang: lang,
          mode: lang == 'ne' ? Brightness.dark : Brightness.light,
          big: true,
        );
      },
    );
  }
}

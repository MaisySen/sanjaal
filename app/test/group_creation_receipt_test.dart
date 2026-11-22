// Synthetic group creation receipts only. No live group or membership operation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'new_chat_journey_test.dart' as n;

import 'package:sanjaal/ui.dart' show t_;

Map<String, dynamic> conversation() => {
  'public_id': 'created-group',
  'type': 'group',
  'title': 'Sydney Nepali meetup',
  'my_role': 'owner',
  'members': [
    {'public_id': 'me', 'username': 'fixture'},
    {'public_id': 'a', 'username': 'asha'},
  ],
};
void main() {
  visualCases();
  for (final many in [false, true]) {
    for (final reverse in [false, true]) {
      testWidgets(
        'matching group receipt accepts members many=$many reverse=$reverse',
        (t) async {
          var posts = 0;
          await n.setup(
            t,
            () async {
              await n.group(t);
              if (many) {
                await t.tap(find.text('Bikash Thapa'));
                await n.flush(t);
              }
              await t.tap(find.text('Create group (${many ? 2 : 1})'));
              await n.flush(t);
              await t.pumpAndSettle();
              expect(posts, 1);
              expect(find.byType(NewChatPage), findsNothing);
              expect(t.takeException(), isNull);
            },
            (r) async {
              if (r.method == 'POST') {
                posts++;
                final value = conversation();
                if (many) {
                  value['members'] = [...value['members'], n.people.last];
                }
                if (reverse) {
                  value['members'] = (value['members'] as List).reversed
                      .toList();
                }
                return n.reply({'conversation': value});
              }
              return n.reply({'users': n.people});
            },
          );
        },
      );
    }
  }
  for (final shape in [
    'wrong type',
    'wrong selected member',
    'missing owner',
    'extra member',
    'missing members',
    'wrong title',
    'blank ID',
    'wrong role',
    'wrong username',
    'duplicate target',
    'member scalar',
    'numeric ID',
    'missing type',
    'missing title',
    'members map',
  ]) {
    testWidgets('group creation rejects $shape without handing it to Chats', (
      t,
    ) async {
      var posts = 0;
      await n.setup(
        t,
        () async {
          await n.group(t);
          await t.tap(find.text('Create group (1)'));
          await n.flush(t);
          await t.pumpAndSettle();
          expect(posts, 1);
          expect(find.byType(NewChatPage), findsOneWidget);
          expect(
            find.text(
              'The chat may already exist. Check Chats before starting it again.',
            ),
            findsOneWidget,
          );
          expect(find.text('Sydney Nepali meetup'), findsOneWidget);
          expect(find.byType(InputChip), findsOneWidget);
          expect(
            t
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Create group (1)'),
                )
                .onPressed,
            isNull,
          );
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            posts++;
            final value = conversation();
            if (shape == 'wrong type') {
              value['type'] = 'direct';
            }
            if (shape == 'wrong selected member') {
              value['members'] = [
                {'public_id': 'me', 'username': 'fixture'},
                {'public_id': 'replacement', 'username': 'asha'},
              ];
            }
            if (shape == 'missing owner') {
              value['members'] = [
                {'public_id': 'a', 'username': 'asha'},
              ];
            }
            if (shape == 'extra member') {
              value['members'] = [
                ...value['members'],
                {'public_id': 'extra', 'username': 'extra'},
              ];
            }
            if (shape == 'missing members') {
              value.remove('members');
            }
            if (shape == 'wrong title') {
              value['title'] = 'Another plan';
            }
            if (shape == 'blank ID') {
              value['public_id'] = ' ';
            }
            if (shape == 'wrong role') {
              value['my_role'] = 'member';
            }
            if (shape == 'wrong username') {
              value['members'] = [
                {'public_id': 'me', 'username': 'fixture'},
                {'public_id': 'a', 'username': 'another'},
              ];
            }
            if (shape == 'duplicate target') {
              value['members'] = [
                {'public_id': 'a', 'username': 'asha'},
                {'public_id': 'a', 'username': 'asha'},
              ];
            }
            if (shape == 'member scalar') {
              value['members'] = [
                false,
                {'public_id': 'a', 'username': 'asha'},
              ];
            }
            if (shape == 'numeric ID') {
              value['public_id'] = 1;
            }
            if (shape == 'missing type') {
              value.remove('type');
            }
            if (shape == 'missing title') {
              value.remove('title');
            }
            if (shape == 'members map') {
              value['members'] = {};
            }
            return n.reply({'conversation': value});
          }
          return n.reply({'users': n.people});
        },
      );
    });
  }
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
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'inconsistent group receipt recovery fits narrow large text $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var posts = 0;
        await n.setup(
          t,
          () async {
            await t.tap(find.byTooltip(t_('New group')));
            await n.flush(t);
            await t.enterText(
              find.byType(TextField).first,
              'Sydney Nepali meetup',
            );
            await n.search(t, 'asha');
            await t.ensureVisible(find.text('Asha Gurung'));
            await t.tap(find.text('Asha Gurung'));
            await n.flush(t);
            await t.tap(find.byType(FilledButton));
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
              File('test/renders/group_receipt_recovery_$lang.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
            });
            await t.tap(back);
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
                'conversation': {...conversation(), 'members': []},
              });
            }
            return n.reply({'users': n.people});
          },
          lang: lang,
          mode: lang == 'ne' ? Brightness.dark : Brightness.light,
          big: true,
        );
      },
    );
  }
}

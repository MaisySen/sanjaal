// Synthetic route stacks, callbacks and HTTP only. No live chat creation.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/chat_pages.dart';

import 'new_chat_journey_test.dart' as n;
import 'new_chat_receipt_test.dart' as receipt;
import 'upload_center_test.dart' as h;

import 'package:sanjaal/ui.dart' show t_;

void main() {
  additionalCases();
  for (final pending in [true, false]) {
    testWidgets(
      '${pending ? 'pending result' : 'retained Back'} cannot pop a covering route',
      (t) async {
        final response = Completer<http.Response>();
        var posts = 0;
        await n.setup(
          t,
          () async {
            await n.search(t, 'asha');
            await t.tap(find.text('Asha Gurung'));
            await n.flush(t);
            VoidCallback? back;
            if (!pending) {
              back = t
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Back to Chats'),
                  )
                  .onPressed!;
            }
            final nav = Navigator.of(t.element(find.byType(NewChatPage)));
            nav.push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Covering route')),
                  body: const Text('Keep this route'),
                ),
              ),
            );
            await t.pumpAndSettle();
            if (pending) {
              response.complete(
                n.reply({'conversation': receipt.conversation()}),
              );
            } else {
              back!();
            }
            await n.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Keep this route'), findsOneWidget);
            await t.pageBack();
            await t.pumpAndSettle();
            expect(
              find.text(
                'The chat may already exist. Check Chats before starting it again.',
              ),
              findsOneWidget,
            );
            await t.tap(find.text('Back to Chats'));
            await n.flush(t);
            await t.pumpAndSettle();
            expect(find.byType(NewChatPage), findsNothing);
            expect(posts, 1);
            expect(t.takeException(), isNull);
          },
          (r) async {
            if (r.method == 'POST') {
              posts++;
              return pending ? response.future : n.reply({'conversation': {}});
            }
            return n.reply({
              'users': [n.people.first],
            });
          },
        );
      },
    );
  }
  testWidgets('duplicate Back callbacks only pop their own route', (t) async {
    await h.fixture(
      t,
      (s, c) async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Root fixture')),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Parent route')),
          ),
        );
        await h.flush(t);
        nav.currentState!.push(
          MaterialPageRoute(builder: (_) => NewChatPage(session: s)),
        );
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'asha');
        await h.flush(t);
        await t.tap(find.text('Asha Gurung'));
        await h.flush(t);
        final back = t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Back to Chats'),
            )
            .onPressed!;
        back();
        back();
        await h.flush(t);
        await t.pumpAndSettle();
        expect(find.text('Parent route'), findsOneWidget);
        expect(find.text('Root fixture'), findsNothing);
        expect(t.takeException(), isNull);
      },
      respond: (r) async => r.method == 'POST'
          ? h.json({'conversation': {}})
          : h.json({
              'users': [n.people.first],
            }),
    );
  });
  testWidgets(
    'a completed handoff cannot issue another POST before its pop frame',
    (t) async {
      var posts = 0;
      final response = Completer<http.Response>();
      await n.setup(
        t,
        () async {
          await n.search(t, 'asha');
          final row = t.widget<ListTile>(find.byType(ListTile)).onTap!;
          row();
          await n.flush(t);
          response.complete(n.reply({'conversation': receipt.conversation()}));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          row();
          await n.flush(t);
          await t.pumpAndSettle();
          expect(posts, 1);
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            return ++posts == 1
                ? response.future
                : n.reply({'message': 'Second request'}, 503);
          }
          return n.reply({
            'users': [n.people.first],
          });
        },
      );
    },
  );
}

void additionalCases() {
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
  testWidgets('covered row and query callbacks cannot begin new requests', (
    t,
  ) async {
    var posts = 0, searches = 0;
    await n.setup(
      t,
      () async {
        await n.search(t, 'asha');
        final oldRow = t.widget<ListTile>(find.byType(ListTile)).onTap!;
        final oldQuery = t.widget<TextField>(find.byType(TextField)).onChanged!;
        final nav = Navigator.of(t.element(find.byType(NewChatPage)));
        nav.push(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
        await t.pumpAndSettle();
        oldRow();
        oldQuery('another');
        await n.flush(t);
        await t.pumpAndSettle();
        expect(posts, 0);
        expect(searches, 1);
        expect(find.text('Cover'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
      (r) async {
        if (r.method == 'POST') {
          posts++;
          return n.reply({'conversation': {}});
        }
        searches++;
        return n.reply({
          'users': [n.people.first],
        });
      },
    );
  });
  testWidgets('a cover inserted during the completion frame cannot be popped', (
    t,
  ) async {
    final response = Completer<http.Response>();
    await n.setup(
      t,
      () async {
        await n.search(t, 'asha');
        await t.tap(find.text('Asha Gurung'));
        await n.flush(t);
        final nav = Navigator.of(t.element(find.byType(NewChatPage)));
        response.complete(n.reply({'conversation': receipt.conversation()}));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        nav.push(
          MaterialPageRoute(
            builder: (_) =>
                Scaffold(appBar: AppBar(), body: const Text('Frame cover')),
          ),
        );
        await n.flush(t);
        await t.pumpAndSettle();
        expect(find.text('Frame cover'), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(
          find.text(
            'The chat may already exist. Check Chats before starting it again.',
          ),
          findsOneWidget,
        );
        await t.tap(find.text('Back to Chats'));
        await n.flush(t);
        await t.pumpAndSettle();
        expect(find.byType(NewChatPage), findsNothing);
        expect(t.takeException(), isNull);
      },
      (r) async => r.method == 'POST'
          ? response.future
          : n.reply({
              'users': [n.people.first],
            }),
    );
  });
  for (final retire in ['same-member login', 'disposal']) {
    testWidgets('$retire before the pop frame retires completion', (t) async {
      final response = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          final nav = GlobalKey<NavigatorState>();
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Text('Parent')),
            ),
          );
          nav.currentState!.push(
            MaterialPageRoute(builder: (_) => NewChatPage(session: s)),
          );
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'asha');
          await h.flush(t);
          await t.tap(find.text('Asha Gurung'));
          await h.flush(t);
          response.complete(h.json({'conversation': receipt.conversation()}));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          if (retire == 'same-member login') {
            await s.login('fixture', 'not-a-password');
          } else {
            await t.pumpWidget(
              const MaterialApp(home: Scaffold(body: Text('Replacement'))),
            );
          }
          await h.flush(t);
          await t.pumpAndSettle();
          if (retire == 'same-member login') {
            expect(find.byType(NewChatPage), findsOneWidget);
            expect(
              find.textContaining('another signed-in session'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Replacement'), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
        respond: (r) async => r.method == 'POST'
            ? response.future
            : h.json({
                'users': [n.people.first],
              }),
      );
    });
  }
  testWidgets(
    'covered group completion keeps its plan without a second creation',
    (t) async {
      var posts = 0;
      final response = Completer<http.Response>();
      await n.setup(
        t,
        () async {
          await n.group(t);
          await t.tap(find.text('Create group (1)'));
          await n.flush(t);
          final nav = Navigator.of(t.element(find.byType(NewChatPage)));
          nav.push(
            MaterialPageRoute(
              builder: (_) =>
                  Scaffold(appBar: AppBar(), body: const Text('Group cover')),
            ),
          );
          await t.pumpAndSettle();
          response.complete(
            n.reply({
              'conversation': {
                ...receipt.conversation(),
                'type': 'group',
                'title': 'Sydney Nepali meetup',
                'my_role': 'owner',
              },
            }),
          );
          await n.flush(t);
          await t.pumpAndSettle();
          expect(find.text('Group cover'), findsOneWidget);
          await t.pageBack();
          await t.pumpAndSettle();
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
          await t.tap(find.text('Back to Chats'));
          await n.flush(t);
          await t.pumpAndSettle();
          expect(posts, 1);
          expect(find.byType(NewChatPage), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
          expect(t.takeException(), isNull);
        },
        (r) async {
          if (r.method == 'POST') {
            posts++;
            return response.future;
          }
          return n.reply({'users': n.people});
        },
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'covered completion recovery is readable and leaves its route $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var posts = 0;
        final response = Completer<http.Response>();
        await n.setup(
          t,
          () async {
            await n.search(t, 'asha');
            await t.tap(find.text('Asha Gurung'));
            await n.flush(t);
            final nav = Navigator.of(t.element(find.byType(NewChatPage)));
            nav.push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(),
                  body: const Text('Visual cover'),
                ),
              ),
            );
            await t.pumpAndSettle();
            response.complete(
              n.reply({'conversation': receipt.conversation()}),
            );
            await n.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Visual cover'), findsOneWidget);
            await t.pageBack();
            await t.pumpAndSettle();
            final back = find.text(t_('Back to Chats'));
            await t.ensureVisible(back);
            await t.pumpAndSettle();
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
              File('test/renders/new_chat_covered_return_$lang.png')
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
              return response.future;
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

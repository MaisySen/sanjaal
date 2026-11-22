// Synthetic profile moderation and route stacks only. No live member actions.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/profile_pages.dart';

import 'profile_journey_test.dart' as p;

void Function(String) menu(WidgetTester t) => t
    .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
    .onSelected!;
Map<String, dynamic> person(bool blocked) => {
  ...p.person(),
  'blocked': blocked,
};
Future<void> cover(WidgetTester t) async {
  Navigator.of(t.element(find.byType(UserProfilePage))).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Covering route')),
        body: const Text('Keep this route'),
      ),
    ),
  );
  await p.flush(t);
}

void main() {
  for (final action in ['report', 'block']) {
    for (final covered in [false, true]) {
      testWidgets(
        '$action confirmation cannot pop ${covered ? 'a cover' : 'the profile twice'}',
        (t) async {
          var writes = 0;
          await p.fixture(
            t,
            (s) => UserProfilePage(session: s, username: 'asha'),
            () async {
              menu(t)(action);
              await p.flush(t);
              final callback = action == 'report'
                  ? t
                        .widget<SimpleDialogOption>(
                          find.widgetWithText(SimpleDialogOption, 'Spam'),
                        )
                        .onPressed!
                  : t
                        .widget<FilledButton>(
                          find.widgetWithText(FilledButton, 'Block'),
                        )
                        .onPressed!;
              if (covered) {
                await cover(t);
                callback();
                await p.flush(t);
                await t.pumpAndSettle();
                expect(find.text('Keep this route'), findsOneWidget);
                expect(writes, 0);
              } else {
                callback();
                callback();
                await p.flush(t);
                if (action == 'report') {
                  expect(writes, 0);
                  await t.tap(find.text('Send report'));
                  await p.flush(t);
                }
                await t.pumpAndSettle();
                if (action == 'report') {
                  expect(find.byType(UserProfilePage), findsOneWidget);
                }
                expect(writes, 1);
                expect(
                  find.text('Create fixture'),
                  action == 'block' ? findsOneWidget : findsNothing,
                );
              }
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.method != 'GET') {
                writes++;
                return p.json(
                  action == 'block'
                      ? {'blocked': true}
                      : {'message': 'Recorded'},
                );
              }
              return r.url.path.endsWith('/users/asha')
                  ? p.json({'user': person(false)})
                  : p.json({'data': [], 'next_cursor': null});
            },
          );
        },
      );
    }
  }
  for (final action in ['report', 'block']) {
    testWidgets('$action cannot stack a second profile confirmation', (
      t,
    ) async {
      await p.fixture(
        t,
        (s) => UserProfilePage(session: s, username: 'asha'),
        () async {
          final old = menu(t);
          old(action);
          await p.flush(t);
          old(action);
          await p.flush(t);
          expect(
            find.byType(
              action == 'report' ? SimpleDialog : AlertDialog,
              skipOffstage: false,
            ),
            findsOneWidget,
          );
        },
        respond: (r) async => r.url.path.endsWith('/users/asha')
            ? p.json({'user': person(false)})
            : p.json({'data': [], 'next_cursor': null}),
      );
    });
    testWidgets('$action pending request locks retained profile menu', (
      t,
    ) async {
      final response = Completer<http.Response>();
      var writes = 0;
      await p.fixture(
        t,
        (s) => UserProfilePage(session: s, username: 'asha'),
        () async {
          final old = menu(t);
          old(action);
          await p.flush(t);
          await t.tap(find.text(action == 'report' ? 'Spam' : 'Block'));
          await p.flush(t);
          if (action == 'report') {
            await t.tap(find.text('Send report'));
          }
          await p.flush(t);
          old(action);
          await p.flush(t);
          final dialogs = find
              .byType(
                action == 'report' ? SimpleDialog : AlertDialog,
                skipOffstage: false,
              )
              .evaluate()
              .length;
          response.complete(
            p.json(
              action == 'block' ? {'blocked': true} : {'message': 'Recorded'},
              action == 'block' ? 200 : 201,
            ),
          );
          await p.flush(t);
          expect(writes, 1);
          expect(dialogs, 0);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method != 'GET') {
            writes++;
            return response.future;
          }
          return r.url.path.endsWith('/users/asha')
              ? p.json({'user': person(false)})
              : p.json({'data': [], 'next_cursor': null});
        },
      );
    });
  }
  testWidgets('pending Unblock serializes retained writes and dialogs', (
    t,
  ) async {
    final response = Completer<http.Response>();
    var writes = 0;
    await p.fixture(
      t,
      (s) => UserProfilePage(session: s, username: 'asha'),
      () async {
        final old = menu(t);
        old('unblock');
        old('unblock');
        old('report');
        await p.flush(t);
        final pendingWrites = writes;
        final dialogs = find
            .byType(SimpleDialog, skipOffstage: false)
            .evaluate()
            .length;
        response.complete(p.json({'blocked': false}));
        await p.flush(t);
        expect(pendingWrites, 1);
        expect(dialogs, 0);
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.method != 'GET') {
          writes++;
          return response.future;
        }
        return r.url.path.endsWith('/users/asha')
            ? p.json({'user': person(writes == 0)})
            : p.json({'data': [], 'next_cursor': null});
      },
    );
  });
  testWidgets('covered profile cannot start a retained menu action', (t) async {
    await p.fixture(
      t,
      (s) => UserProfilePage(session: s, username: 'asha'),
      () async {
        final old = menu(t);
        await cover(t);
        old('report');
        await p.flush(t);
        expect(find.byType(SimpleDialog, skipOffstage: false), findsNothing);
        expect(find.text('Keep this route'), findsOneWidget);
      },
      respond: (r) async => r.url.path.endsWith('/users/asha')
          ? p.json({'user': person(false)})
          : p.json({'data': [], 'next_cursor': null}),
    );
  });
  testWidgets('block completion cannot pop a covering route', (t) async {
    final response = Completer<http.Response>();
    var writes = 0;
    await p.fixture(
      t,
      (s) => UserProfilePage(session: s, username: 'asha'),
      () async {
        menu(t)('block');
        await p.flush(t);
        await t.tap(find.text('Block'));
        await p.flush(t);
        await cover(t);
        response.complete(p.json({'blocked': true}));
        await p.flush(t);
        expect(find.text('Keep this route'), findsOneWidget);
        await t.pageBack();
        await p.flush(t);
        expect(find.byType(UserProfilePage), findsOneWidget);
        expect(writes, 1);
        expect(t.takeException(), isNull);
      },
      respond: (r) async {
        if (r.method == 'POST') {
          writes++;
          return response.future;
        }
        return r.url.path.endsWith('/users/asha')
            ? p.json({'user': person(writes > 0)})
            : p.json({'data': [], 'next_cursor': null});
      },
    );
  });
  for (final action in ['block', 'unblock']) {
    testWidgets('retained $action cannot act on changed blocked state', (
      t,
    ) async {
      var reads = 0, writes = 0;
      await p.fixture(
        t,
        (s) => UserProfilePage(session: s, username: 'asha'),
        () async {
          final old = menu(t);
          await t.tap(find.byTooltip('Refresh profile'));
          await p.flush(t);
          old(action);
          await p.flush(t);
          expect(writes, 0);
          expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
        },
        respond: (r) async {
          if (r.method != 'GET') {
            writes++;
            return p.json({'blocked': false});
          }
          return r.url.path.endsWith('/users/asha')
              ? p.json({
                  'user': person((++reads == 1) == (action == 'unblock')),
                })
              : p.json({'data': [], 'next_cursor': null});
        },
      );
    });
  }
}

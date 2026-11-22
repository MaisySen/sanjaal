// Synthetic moderation requests, recovery reads, logins and route stacks only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show t_;

import 'profile_journey_test.dart' as p;
import 'profile_menu_ownership_test.dart' as m;

bool menuEnabled(WidgetTester t) => t
    .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
    .enabled;
bool followEnabled(WidgetTester t) =>
    t
        .widget<FilledButton>(find.widgetWithText(FilledButton, t_('Follow')))
        .onPressed !=
    null;
Future<void> choose(WidgetTester t, String action) async {
  await t.tap(find.byType(PopupMenuButton<String>));
  await p.flush(t);
  await t.tap(find.text(t_(action)));
  await p.flush(t);
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
  for (final failWrite in [false, true]) {
    for (final failRead in [false, true]) {
      testWidgets(
        'Unblock ${failWrite ? 'unknown' : 'success'} with ${failRead ? 'failed' : 'valid'} read never resends',
        (t) async {
          final response = Completer<http.Response>(),
              refresh = Completer<http.Response>();
          var writes = 0, reads = 0;
          await p.fixture(
            t,
            (s) => UserProfilePage(session: s, username: 'asha'),
            () async {
              final old = m.menu(t);
              await choose(t, 'Unblock');
              expect(menuEnabled(t), isFalse);
              expect(find.byType(LinearProgressIndicator), findsOneWidget);
              response.complete(
                failWrite
                    ? p.json({'message': 'Uncertain fixture response'}, 503)
                    : p.json({'blocked': false}),
              );
              await p.flush(t);
              old('unblock');
              old('report');
              await p.flush(t);
              expect(writes, 1);
              expect(reads, 2);
              expect(menuEnabled(t), isFalse);
              refresh.complete(
                failRead
                    ? p.json({'message': 'Fixture read failed'}, 503)
                    : p.json({'user': m.person(false)}),
              );
              await p.flush(t);
              if (failRead) {
                expect(find.text('Asha Gurung'), findsOneWidget);
                expect(menuEnabled(t), isFalse);
                expect(followEnabled(t), isFalse);
                old('unblock');
                old('report');
                await p.flush(t);
                expect(writes, 1);
                await t.tap(find.text('Try again'));
                await p.flush(t);
                expect(reads, 3);
              }
              expect(writes, 1);
              expect(followEnabled(t), isTrue);
              expect(menuEnabled(t), isTrue);
              expect(find.byType(LinearProgressIndicator), findsNothing);
              expect(t.takeException(), isNull);
            },
            respond: (r) async {
              if (r.method == 'DELETE') {
                writes++;
                return response.future;
              }
              if (r.url.path.endsWith('/users/asha')) {
                reads++;
                return reads == 2
                    ? refresh.future
                    : p.json({'user': m.person(reads == 1)});
              }
              return p.json({'data': [], 'next_cursor': null});
            },
          );
        },
      );
    }
  }
  for (final failRead in [false, true]) {
    testWidgets(
      'uncertain block reconciles ${failRead ? 'failed read before retry' : 'current blocked state'} without another POST',
      (t) async {
        var reads = 0, writes = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await choose(t, 'Block');
            await t.tap(find.text('Block'));
            await p.flush(t);
            expect(find.byType(UserProfilePage), findsOneWidget);
            expect(writes, 1);
            expect(reads, 2);
            expect(followEnabled(t), isFalse);
            if (failRead) {
              expect(menuEnabled(t), isFalse);
              await t.tap(find.text('Try again'));
              await p.flush(t);
            }
            expect(menuEnabled(t), isTrue);
            expect(followEnabled(t), isFalse);
            expect(writes, 1);
            expect(find.text('@asha is blocked.'), findsNothing);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'POST') {
              writes++;
              return p.json({'message': 'Fixture reply lost'}, 503);
            }
            if (r.url.path.endsWith('/users/asha')) {
              reads++;
              return reads == 2 && failRead
                  ? p.json({'message': 'Fixture read unavailable'}, 503)
                  : p.json({'user': m.person(reads > 1)});
            }
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  for (final action in ['report', 'block']) {
    testWidgets(
      '$action cancel through actual menu unlocks without a profile reread',
      (t) async {
        var reads = 0, writes = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await choose(t, action == 'report' ? 'Report' : 'Block');
            if (action == 'block') {
              await t.tap(find.text('Cancel'));
            } else {
              Navigator.of(t.element(find.byType(SimpleDialog))).pop();
            }
            await p.flush(t);
            await t.pumpAndSettle();
            expect(menuEnabled(t), isTrue);
            expect(followEnabled(t), isTrue);
            expect(reads, 1);
            expect(writes, 0);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method != 'GET') writes++;
            if (r.url.path.endsWith('/users/asha')) {
              reads++;
              return p.json({'user': m.person(false)});
            }
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
    testWidgets('$action confirmation belongs to its original verified read', (
      t,
    ) async {
      var reads = 0, writes = 0;
      await p.fixture(
        t,
        (s) => UserProfilePage(session: s, username: 'asha'),
        () async {
          final refresh = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Refresh profile',
                ),
              )
              .onPressed!;
          m.menu(t)(action);
          await p.flush(t);
          refresh();
          await p.flush(t);
          await t.tap(find.text(action == 'report' ? 'Spam' : 'Block'));
          await p.flush(t);
          await t.pumpAndSettle();
          expect(reads, 2);
          expect(writes, 0);
          expect(menuEnabled(t), isTrue);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method != 'GET') {
            writes++;
            return p.json({'blocked': true});
          }
          if (r.url.path.endsWith('/users/asha')) {
            reads++;
            return p.json({'user': m.person(reads > 1)});
          }
          return p.json({'data': [], 'next_cursor': null});
        },
      );
    });
    testWidgets(
      '$action covered confirmation requires a new explicit choice after return',
      (t) async {
        var writes = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            m.menu(t)(action);
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
            await m.cover(t);
            callback();
            await p.flush(t);
            await t.pumpAndSettle();
            expect(find.text('Keep this route'), findsOneWidget);
            expect(writes, 0);
            await t.pageBack();
            await p.flush(t);
            await t.pump(const Duration(milliseconds: 450));
            await t.pump();
            expect(writes, 0);
            await t.tap(find.text(action == 'report' ? 'Spam' : 'Block'));
            await p.flush(t);
            await t.pumpAndSettle();
            expect(writes, 1);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method != 'GET') {
              writes++;
              return p.json(
                action == 'block' ? {'blocked': true} : {'message': 'Recorded'},
              );
            }
            return r.url.path.endsWith('/users/asha')
                ? p.json({'user': m.person(false)})
                : p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
  for (final action in ['report', 'block', 'unblock']) {
    for (final retirement in ['same-member login', 'disposal']) {
      for (final fail in [false, true]) {
        testWidgets(
          '$action late ${fail ? 'error' : 'success'} after $retirement neither rereads nor closes another route',
          (t) async {
            final response = Completer<http.Response>();
            var writes = 0, reads = 0;
            late Session session;
            await p.fixture(
              t,
              (s) {
                session = s;
                return UserProfilePage(session: s, username: 'asha');
              },
              () async {
                m.menu(t)(action);
                await p.flush(t);
                if (action != 'unblock') {
                  await t.tap(find.text(action == 'report' ? 'Spam' : 'Block'));
                  await p.flush(t);
                }
                expect(writes, 1);
                if (retirement == 'same-member login') {
                  await session.login('fixture', 'not-a-password');
                  await p.flush(t);
                } else {
                  await t.pumpWidget(const SizedBox());
                }
                response.complete(
                  fail
                      ? p.json({'message': 'Old moderation result'}, 503)
                      : p.json({'blocked': action == 'block'}),
                );
                await p.flush(t);
                expect(reads, 1);
                expect(writes, 1);
                expect(find.textContaining('is blocked.'), findsNothing);
                expect(find.text('Report submitted.'), findsNothing);
                expect(find.text('Could not load this.'), findsNothing);
                expect(t.takeException(), isNull);
              },
              respond: (r) async {
                if (r.method != 'GET') {
                  writes++;
                  return response.future;
                }
                if (r.url.path.endsWith('/users/asha')) {
                  reads++;
                  return p.json({'user': m.person(action == 'unblock')});
                }
                return p.json({'data': [], 'next_cursor': null});
              },
            );
          },
        );
      }
    }
  }
  for (final language in ['en', 'ne']) {
    testWidgets(
      'pending Unblock and failed recovery remain readable at narrow large text $language',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final response = Completer<http.Response>();
        var writes = 0, reads = 0;
        await p.fixture(
          t,
          (s) => UserProfilePage(session: s, username: 'asha'),
          () async {
            await choose(t, 'Unblock');
            expect(find.byType(LinearProgressIndicator), findsOneWidget);
            expect(menuEnabled(t), isFalse);
            expect(find.text('Asha Gurung'), findsOneWidget);
            expect(followEnabled(t), isFalse);
            await p.shot(t, 'profile_menu_pending_$language');
            response.complete(p.json({'blocked': false}));
            await p.flush(t);
            expect(find.text(t_('Could not load this.')), findsOneWidget);
            expect(menuEnabled(t), isFalse);
            expect(find.text('Asha Gurung'), findsOneWidget);
            expect(followEnabled(t), isFalse);
            await p.shot(t, 'profile_menu_recovery_$language');
            await t.ensureVisible(find.text(t_('Try again')));
            await t.tap(find.text(t_('Try again')));
            await p.flush(t);
            expect(writes, 1);
            expect(reads, 3);
            expect(menuEnabled(t), isTrue);
            expect(followEnabled(t), isTrue);
            expect(t.takeException(), isNull);
          },
          language: language,
          brightness: language == 'en' ? Brightness.light : Brightness.dark,
          scale: 1.8,
          respond: (r) async {
            if (r.method == 'DELETE') {
              writes++;
              return response.future;
            }
            if (r.url.path.endsWith('/users/asha')) {
              reads++;
              return reads == 2
                  ? p.json({'message': 'Fixture recovery unavailable'}, 503)
                  : p.json({'user': m.person(reads == 1)});
            }
            return p.json({'data': [], 'next_cursor': null});
          },
        );
      },
    );
  }
}

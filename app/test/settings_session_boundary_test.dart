// Synthetic login transitions only. No real account or moderation effects.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/notifications_page.dart';

import 'upload_center_test.dart' as h;

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
  for (final lang in ['en', 'ne']) {
    for (final signedOut in [false, true]) {
      testWidgets(
        'retired settings boundary readable at narrow large text $lang signedOut=$signedOut',
        (t) async {
          prefs.lang = lang;
          addTearDown(() => prefs.lang = 'en');
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await h.fixture(
            t,
            (s, c) async {
              final key = GlobalKey();
              await t.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildTheme(
                      Brightness.dark,
                      fontFamily: 'Roboto',
                      fontFamilyFallback: ['NotoDev'],
                    ),
                    builder: (context, w) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(1.8)),
                      child: w!,
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BlockedPage(session: s),
                            ),
                          ),
                          child: const Text('Open blocked people'),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await h.flush(t);
              await t.tap(find.text('Open blocked people'));
              await t.pumpAndSettle();
              await h.flush(t);
              if (signedOut) {
                s.user = null;
                s.notifyListeners();
              } else {
                await s.login('fixture', 'not-a-password');
              }
              await h.flush(t);
              expect(t.takeException(), isNull);
              expect(find.text('@private-blocked'), findsNothing);
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
                      'test/renders/settings-boundary',
                )..createSync(recursive: true);
                File(
                  '${out.path}/retired-$lang-${signedOut ? 'signed-out' : 'current-account'}.png',
                ).writeAsBytesSync(data!.buffer.asUint8List());
              });
              await t.pageBack();
              await t.pumpAndSettle();
              expect(find.text('Open blocked people'), findsOneWidget);
              expect(t.takeException(), isNull);
            },
            respond: (_) async => h.json({
              'data': [
                {'username': 'private-blocked'},
              ],
            }),
          );
        },
      );
    }
  }

  for (final lang in ['en', 'ne']) {
    for (final signedOut in [false, true]) {
      testWidgets(
        'Back from nested notification settings returns to live root $lang signedOut=$signedOut',
        (t) async {
          prefs.lang = lang;
          addTearDown(() => prefs.lang = 'en');
          await h.fixture(t, (s, c) async {
            await t.pumpWidget(
              MaterialApp(
                home: ListenableBuilder(
                  listenable: s,
                  builder: (context, _) => Scaffold(
                    body: Column(
                      children: [
                        Text(
                          s.user == null
                              ? 'Sign-in entry'
                              : 'Current account: ${s.user!['username']}',
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsPage(session: s),
                            ),
                          ),
                          child: const Text('Open settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await h.flush(t);
            await t.tap(find.text('Open settings'));
            await t.pumpAndSettle();
            await t.enterText(find.byType(TextField), 'notifications');
            await t.pump();
            await t.tap(find.text(t_('Notifications')));
            await t.pumpAndSettle();
            if (signedOut) {
              s.user = null;
              s.notifyListeners();
            } else {
              s.user = {'public_id': 'other', 'username': 'other'};
              s.notifyListeners();
            }
            await h.flush(t);
            expect(
              find.text(
                t_(
                  signedOut ? "You're signed out. Go back to sign in." : 'This screen is from an earlier sign-in. Go back to continue.',
                ),
              ),
              findsOneWidget,
            );
            await t.tap(
              find.text(t_(signedOut ? 'Back to sign in' : 'Back to account')),
            );
            await t.pumpAndSettle();
            expect(find.byType(SettingsPage), findsNothing);
            expect(
              find.text(signedOut ? 'Sign-in entry' : 'Current account: other'),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
          });
        },
      );
    }
  }

  for (final same in [false, true]) {
    testWidgets(
      'old blocked route and retained callback cannot unblock after ${same ? 'same-member login' : 'account change'}',
      (t) async {
        var writes = 0;
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
            await h.flush(t);
            final stale = t
                .widget<TextButton>(find.widgetWithText(TextButton, 'Unblock'))
                .onPressed!;
            if (same) {
              await s.login('fixture', 'not-a-password');
            } else {
              s.user = {'public_id': 'other', 'username': 'other'};
              s.notifyListeners();
            }
            await h.flush(t);
            stale();
            await h.flush(t);
            expect(writes, 0);
            expect(find.text('@private-blocked'), findsNothing);
            expect(find.textContaining('earlier sign-in'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'DELETE') {
              writes++;
              return h.json({});
            }
            return h.json({
              'data': [
                {'username': 'private-blocked'},
              ],
            });
          },
        );
      },
    );
    testWidgets(
      'old settings signout callback cannot sign out a replacement ${same ? 'login' : 'account'}',
      (t) async {
        await h.fixture(t, (s, c) async {
          await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'logout');
          await t.pump();
          final row = t.widget<ListTile>(
            find.widgetWithText(ListTile, 'Sign out'),
          );
          if (same) {
            await s.login('fixture', 'not-a-password');
          } else {
            s.user = {'public_id': 'other', 'username': 'other'};
            s.notifyListeners();
          }
          await h.flush(t);
          final owner = s.user!['public_id'];
          row.onTap!();
          await h.flush(t);
          expect(s.user?['public_id'], owner);
          expect(find.textContaining('earlier sign-in'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      },
    );
  }
  testWidgets(
    'notification settings retires and retained Activity callback cannot open a replacement account',
    (t) async {
      await h.fixture(t, (s, c) async {
        await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'notifications');
        await t.pump();
        await t.tap(find.text('Notifications'));
        await t.pumpAndSettle();
        final row = t.widget<ListTile>(
          find.widgetWithText(ListTile, 'Activity'),
        );
        await s.login('fixture', 'not-a-password');
        await h.flush(t);
        row.onTap!();
        await t.pumpAndSettle();
        expect(find.byType(NotificationsPage), findsNothing);
        expect(find.textContaining('earlier sign-in'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'blocked screen rejects replacement Session object even for the same member',
    (t) async {
      var reads = 0, writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          Widget page(Session session) =>
              MaterialApp(home: BlockedPage(session: session));
          await t.pumpWidget(page(s));
          await h.flush(t);
          final stale = t
              .widget<TextButton>(find.widgetWithText(TextButton, 'Unblock'))
              .onPressed!;
          final replacement = Session();
          await replacement.login('fixture', 'not-a-password');
          await t.pumpWidget(page(replacement));
          await h.flush(t);
          stale();
          await h.flush(t);
          expect(reads, 1);
          expect(writes, 0);
          expect(find.text('@private-blocked'), findsNothing);
          expect(find.textContaining('earlier sign-in'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'DELETE') {
            writes++;
            return h.json({});
          }
          reads++;
          return h.json({
            'data': [
              {'username': 'private-blocked'},
            ],
          });
        },
      );
    },
  );
  testWidgets(
    'retired blocked route never revives when the original member returns',
    (t) async {
      var writes = 0;
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
          await h.flush(t);
          final original = s.user;
          final stale = t
              .widget<TextButton>(find.widgetWithText(TextButton, 'Unblock'))
              .onPressed!;
          s.user = {'public_id': 'other', 'username': 'other'};
          s.notifyListeners();
          await h.flush(t);
          s.user = original;
          s.notifyListeners();
          await h.flush(t);
          stale();
          await h.flush(t);
          expect(writes, 0);
          expect(find.text('@private-blocked'), findsNothing);
          expect(find.textContaining('earlier sign-in'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
        respond: (r) async {
          if (r.method == 'DELETE') {
            writes++;
            return h.json({});
          }
          return h.json({
            'data': [
              {'username': 'private-blocked'},
            ],
          });
        },
      );
    },
  );
  testWidgets('current Settings still signs out on an explicit tap', (t) async {
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
      await h.flush(t);
      await t.enterText(find.byType(TextField), 'logout');
      await t.pump();
      await t.tap(find.text('Sign out'));
      await h.flush(t);
      expect(s.user, isNull);
      expect(t.takeException(), isNull);
    });
  });
  for (final fail in [false, true]) {
    testWidgets(
      'pending unblock ${fail ? 'failure' : 'success'} cannot reload or surface private state for replacement login',
      (t) async {
        var reads = 0, writes = 0;
        final response = Completer<http.Response>();
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
            await h.flush(t);
            await t.tap(find.text('Unblock'));
            await h.flush(t);
            expect(writes, 1);
            await s.login('fixture', 'not-a-password');
            await h.flush(t);
            response.complete(
              fail
                  ? h.json({'message': 'Private old failure'}, 503)
                  : h.json({}),
            );
            await h.flush(t);
            expect(reads, 1);
            expect(find.text('@private-blocked'), findsNothing);
            expect(find.text('Private old failure'), findsNothing);
            expect(find.textContaining('earlier sign-in'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
          respond: (r) async {
            if (r.method == 'DELETE') {
              writes++;
              return response.future;
            }
            reads++;
            return h.json({
              'data': [
                {'username': 'private-blocked'},
              ],
            });
          },
        );
      },
    );
  }
  testWidgets('pending old blocked read never reveals list after new login', (
    t,
  ) async {
    final response = Completer<http.Response>();
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(MaterialApp(home: BlockedPage(session: s)));
      await h.flush(t);
      await s.login('fixture', 'not-a-password');
      await h.flush(t);
      response.complete(
        h.json({
          'data': [
            {'username': 'private-blocked'},
          ],
        }),
      );
      await h.flush(t);
      expect(find.text('@private-blocked'), findsNothing);
      expect(find.textContaining('earlier sign-in'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, respond: (_) => response.future);
  });
}

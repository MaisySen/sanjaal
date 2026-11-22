// Synthetic own-profile navigation only. No live profile or settings changes.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

import 'profile_journey_test.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/feed_page.dart' show SavedPage;

import 'upload_center_test.dart' as h;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

VoidCallback action(WidgetTester t, String name) => name == 'Settings'
    ? t
          .widget<IconButton>(
            find.byWidgetPredicate((w) => w is IconButton && w.tooltip == name),
          )
          .onPressed!
    : t
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, name))
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
  testWidgets(
    'own-profile compose callback is single-flight and retires after login',
    (t) async {
      var opens = 0;
      final pending = Completer<void>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              home: MePage(
                session: s,
                onCompose: () async {
                  opens++;
                  await pending.future;
                },
              ),
            ),
          );
          await h.flush(t);
          final open = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Post',
                ),
              )
              .onPressed!;
          open();
          open();
          await t.pump();
          expect(opens, 1);
          pending.complete();
          await t.pump();
          open();
          await t.pump();
          expect(opens, 2);
          await s.login('fixture', 'not-a-password');
          await h.flush(t);
          open();
          await t.pump();
          expect(opens, 2);
        },
        respond: (r) async => r.url.path.contains('/users/')
            ? h.json({
                'user': {'public_id': 'me', 'username': 'fixture'},
              })
            : h.json({'data': []}),
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'retired own profile remains readable narrow large text $lang',
      (t) async {
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await h.fixture(
          t,
          (s, c) async {
            await t.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('review'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildTheme(
                    lang == 'en' ? Brightness.light : Brightness.dark,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: ['NotoDev'],
                  ),
                  builder: (context, w) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.8)),
                    child: w!,
                  ),
                  home: MePage(session: s),
                ),
              ),
            );
            await h.flush(t);
            await s.login('fixture', 'not-a-password');
            await h.flush(t);
            expect(find.text('@fixture'), findsNothing);
            expect(t.takeException(), isNull);
            await p.shot(t, 'own_profile_retired_$lang');
          },
          respond: (r) async => r.url.path.contains('/users/')
              ? h.json({
                  'user': {'public_id': 'me', 'username': 'fixture'},
                })
              : h.json({'data': []}),
        );
      },
    );
  }

  for (final name in ['Settings', 'Edit profile', 'Saved']) {
    for (final same in [false, true]) {
      testWidgets(
        'retained own-profile $name callback rejects ${same ? 'same login' : 'other member'}',
        (t) async {
          await h.fixture(
            t,
            (s, c) async {
              final routes = Routes();
              await t.pumpWidget(
                MaterialApp(
                  navigatorObservers: [routes],
                  home: MePage(session: s),
                ),
              );
              await h.flush(t);
              final old = action(t, name);
              if (same) {
                await s.login('fixture', 'not-a-password');
              } else {
                s.user = {'public_id': 'other', 'username': 'other'};
                s.notifyListeners();
              }
              await h.flush(t);
              old();
              await t.pumpAndSettle();
              await h.flush(t);
              expect(routes.pushes, 1);
              expect(find.byType(SettingsPage), findsNothing);
              expect(find.byType(EditProfilePage), findsNothing);
              expect(find.byType(SavedPage), findsNothing);
              expect(t.takeException(), isNull);
            },
            respond: (r) async => r.url.path.contains('/users/')
                ? h.json({
                    'user': {
                      'public_id': 'me',
                      'username': 'fixture',
                      'posts_count': 7,
                      'followers_count': 4,
                      'following_count': 3,
                    },
                  })
                : h.json({'data': []}),
          );
        },
      );
    }
    testWidgets('own-profile $name opens once and can reopen after Back', (
      t,
    ) async {
      await h.fixture(
        t,
        (s, c) async {
          final routes = Routes();
          await t.pumpWidget(
            MaterialApp(
              navigatorObservers: [routes],
              home: MePage(session: s),
            ),
          );
          await h.flush(t);
          final open = action(t, name);
          open();
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 2);
          await t.pageBack();
          await t.pumpAndSettle();
          await h.flush(t);
          action(t, name)();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, 3);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
        respond: (r) async => r.url.path.contains('/users/')
            ? h.json({
                'user': {
                  'public_id': 'me',
                  'username': 'fixture',
                  'posts_count': 7,
                  'followers_count': 4,
                  'following_count': 3,
                },
              })
            : h.json({'data': []}),
      );
    });
  }
  testWidgets(
    'return from edit does not lock settings behind a pending count refresh',
    (t) async {
      var reads = 0;
      final pending = Completer<http.Response>();
      await h.fixture(
        t,
        (s, c) async {
          await t.pumpWidget(MaterialApp(home: MePage(session: s)));
          await h.flush(t);
          action(t, 'Edit profile')();
          await t.pumpAndSettle();
          await t.pageBack();
          await h.flush(t);
          expect(reads, 2);
          action(t, 'Settings')();
          await t.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);
          pending.complete(
            h.json({
              'user': {
                'public_id': 'me',
                'username': 'fixture',
                'posts_count': 8,
                'followers_count': 4,
                'following_count': 3,
              },
            }),
          );
          await h.flush(t);
          await t.pageBack();
          await t.pumpAndSettle();
        },
        respond: (r) async => r.url.path.contains('/users/')
            ? (++reads == 1
                  ? h.json({
                      'user': {
                        'public_id': 'me',
                        'username': 'fixture',
                        'posts_count': 7,
                        'followers_count': 4,
                        'following_count': 3,
                      },
                    })
                  : pending.future)
            : h.json({'data': []}),
      );
    },
  );
  testWidgets('pending own-profile read stays hidden after account switch', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    await h.fixture(
      t,
      (s, c) async {
        await t.pumpWidget(MaterialApp(home: MePage(session: s)));
        await h.flush(t);
        s.user = {'public_id': 'other', 'username': 'other'};
        s.notifyListeners();
        await t.pump();
        pending.complete(
          h.json({
            'user': {
              'public_id': 'me',
              'username': 'fixture',
              'posts_count': 9876,
              'followers_count': 1234,
              'following_count': 4321,
            },
          }),
        );
        await h.flush(t);
        expect(find.text('9.8K'), findsNothing);
        expect(find.text('@other'), findsNothing);
        expect(find.textContaining('earlier sign-in'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
      respond: (r) async => r.url.path.contains('/users/')
          ? pending.future
          : h.json({'data': []}),
    );
  });
}

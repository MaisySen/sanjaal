// Synthetic Home entry routes. No account/provider writes or real compose.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'profile_journey_test.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/feed_page.dart';

import 'upload_center_test.dart' as h;

class Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

VoidCallback action(WidgetTester t, String label) => t
    .widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label),
    )
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
  for (final lang in ['en', 'ne']) {
    testWidgets('retired Home remains readable narrow large text $lang', (
      t,
    ) async {
      prefs.lang = lang;
      addTearDown(() => prefs.lang = 'en');
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await h.fixture(t, (s, c) async {
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
              home: FeedPage(session: s, onCompose: () async {}),
            ),
          ),
        );
        await h.flush(t);
        await s.login('fixture', 'not-a-password');
        await h.flush(t);
        expect(find.text('Sanjaal'), findsNothing);
        expect(find.text(t_('Back to account')), findsOneWidget);
        expect(t.takeException(), isNull);
        await p.shot(t, 'home_retired_$lang');
      });
    });
  }
  for (final retired in [false, true]) {
    testWidgets(
      'Following empty destination respects ownership retired=$retired',
      (t) async {
        await h.fixture(t, (s, c) async {
          final routes = Routes();
          await t.pumpWidget(
            MaterialApp(
              navigatorObservers: [routes],
              home: FeedPage(session: s, onCompose: () async {}),
            ),
          );
          await h.flush(t);
          await t.tap(find.text('Following'));
          await h.flush(t);
          await t.pumpAndSettle();
          final open = t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Find people'),
              )
              .onPressed!;
          if (retired) {
            await s.login('fixture', 'not-a-password');
            await h.flush(t);
          }
          open();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(routes.pushes, retired ? 1 : 2);
          expect(t.takeException(), isNull);
          if (!retired) {
            await t.pageBack();
            await t.pumpAndSettle();
          }
        });
      },
    );
  }

  for (final label in ['Search', 'Notifications']) {
    for (final same in [false, true]) {
      testWidgets(
        'retained Home $label rejects ${same ? 'same-member login' : 'other account'}',
        (t) async {
          await h.fixture(t, (s, c) async {
            final routes = Routes();
            await t.pumpWidget(
              MaterialApp(
                navigatorObservers: [routes],
                home: FeedPage(session: s, onCompose: () async {}),
              ),
            );
            await h.flush(t);
            final old = action(t, label);
            if (same) {
              await s.login('fixture', 'not-a-password');
            } else {
              s.user = {'public_id': 'other', 'username': 'other'};
              s.notifyListeners();
            }
            await h.flush(t);
            old();
            await h.flush(t);
            await t.pumpAndSettle();
            expect(routes.pushes, 1);
            expect(t.takeException(), isNull);
          });
        },
      );
    }
    testWidgets('Home $label opens once and reopens after Back', (t) async {
      await h.fixture(t, (s, c) async {
        final routes = Routes();
        await t.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: FeedPage(session: s, onCompose: () async {}),
          ),
        );
        await h.flush(t);
        final open = action(t, label);
        open();
        open();
        await h.flush(t);
        await t.pumpAndSettle();
        expect(routes.pushes, 2);
        await t.pageBack();
        await t.pumpAndSettle();
        open();
        await h.flush(t);
        await t.pumpAndSettle();
        expect(routes.pushes, 3);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    });
  }
  testWidgets('Home compose is single flight and retained callback retires', (
    t,
  ) async {
    var opens = 0;
    final pending = Completer<void>();
    await h.fixture(t, (s, c) async {
      await t.pumpWidget(
        MaterialApp(
          home: FeedPage(
            session: s,
            onCompose: () async {
              opens++;
              await pending.future;
            },
          ),
        ),
      );
      await h.flush(t);
      final open = action(t, 'Post');
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
    });
  });
}

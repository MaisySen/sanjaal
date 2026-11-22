// Real root/shell/routes, synthetic accounts only. No native media or live auth.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/glass_nav.dart';
import 'package:sanjaal/feed_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/reels_page.dart';
import 'package:sanjaal/session_recovery.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart';

http.Response reply(Object value) => http.Response(jsonEncode(value), 200);
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 25)),
  );
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

Map<String, dynamic> reel(String owner) => {
  'public_id': 'reel-$owner',
  'kind': 'reel',
  'body': 'Reel for $owner',
  'media': [],
  'author': {'public_id': 'author', 'username': 'author'},
  'likes_count': 0,
  'comments_count': 0,
};
void main() {
  setUpAll(() async {
    for (final font in [
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
      final loader = FontLoader(font.$1)
        ..addFont(
          File(font.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    prefs.lang = 'en';
  });
  for (final lang in ['en', 'ne']) {
    for (final signedOut in [false, true]) {
      for (final mode in [Brightness.light, Brightness.dark]) {
        testWidgets(
          'Reels shared recovery narrow large text $lang signedOut=$signedOut ${mode.name}',
          (t) async {
            prefs.lang = lang;
            t.view.physicalSize = const Size(320, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            var writes = 0;
            String owner = 'old';
            await http.runWithClient(
              () async {
                final s = Session(unregisterPush: (_) async {});
                await s.login('fixture', 'not-a-password');
                final key = GlobalKey(), nav = GlobalKey<NavigatorState>();
                await t.pumpWidget(
                  RepaintBoundary(
                    key: key,
                    child: MaterialApp(
                      navigatorKey: nav,
                      debugShowCheckedModeBanner: false,
                      theme: buildTheme(
                        mode,
                        fontFamily: 'Roboto',
                        fontFamilyFallback: ['NotoDev'],
                      ),
                      builder: (context, w) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: const TextScaler.linear(1.8)),
                        child: w!,
                      ),
                      home: ListenableBuilder(
                        listenable: s,
                        builder: (context, _) => Scaffold(
                          body: Text(
                            s.user == null
                                ? 'Current sign-in entry'
                                : 'Current root: ${s.user!['public_id']}',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                nav.currentState!.push(
                  MaterialPageRoute(
                    builder: (_) => ReelsPage(session: s, active: true),
                  ),
                );
                await flush(t);
                await t.pumpAndSettle();
                expect(find.text('Reel for old'), findsOneWidget);
                if (signedOut) {
                  await s.logout();
                } else {
                  owner = 'new';
                  await s.login('fixture', 'not-a-password');
                }
                await t.pumpAndSettle();
                final generation = s.generation, identity = s.user;
                expect(find.byType(SessionRecoveryView), findsOneWidget);
                expect(find.text('Reel for old'), findsNothing);
                expect(find.textContaining('sign in again'), findsNothing);
                final button = find.widgetWithText(
                  FilledButton,
                  t_(signedOut ? 'Back to sign in' : 'Back to account'),
                );
                expect(button.hitTestable(), findsOneWidget);
                expect(t.getSize(button).height, greaterThanOrEqualTo(44));
                expect(t.getBottomRight(button).dy, lessThanOrEqualTo(640));
                expect(t.takeException(), isNull);
                await t.runAsync(() async {
                  final image =
                      await (key.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage(pixelRatio: 2);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  File(
                    '/downloads/sanjaal-discovery-review/reels-recovery-$lang-${signedOut ? 'out' : 'account'}-${mode.name}.png',
                  ).writeAsBytesSync(bytes!.buffer.asUint8List());
                  image.dispose();
                });
                await t.tap(button);
                await t.pumpAndSettle();
                expect(find.byType(ReelsPage), findsNothing);
                expect(
                  find.text(
                    signedOut ? 'Current sign-in entry' : 'Current root: new',
                  ),
                  findsOneWidget,
                );
                expect(s.generation, generation);
                expect(identical(s.user, identity), isTrue);
                expect(writes, 0);
                expect(t.takeException(), isNull);
                await t.pumpWidget(const SizedBox());
              },
              () => MockClient((r) async {
                if (r.url.path.endsWith('/oauth/token')) {
                  return reply({'access_token': 'fixture', 'expires_in': 3600});
                }
                if (r.url.path.endsWith('/auth/me')) {
                  return reply({
                    'user': {'public_id': owner, 'username': owner},
                  });
                }
                if (r.method != 'GET') writes++;
                return reply({
                  'data': [reel(owner)],
                  'next_cursor': null,
                });
              }),
            );
          },
        );
      }
    }
  }
  for (final cover in ['none', 'settings', 'saved']) {
    final covered = cover != 'none';
    for (final change in ['same', 'other', 'logout']) {
      testWidgets(
        'actual app root recovers Reels $change cover=$cover without replacing new session',
        (t) async {
          var owner = 'old', writes = 0, homeReads = 0;
          final pendingGrant = Completer<http.Response>();
          var delayGrant = false;
          await http.runWithClient(
            () async {
              await t.pumpWidget(const SanjaalApp());
              await flush(t);
              await t.pumpAndSettle();
              final s = t.widget<AuthPage>(find.byType(AuthPage)).session;
              await s.login('fixture', 'not-a-password');
              await flush(t);
              await t.pumpAndSettle();
              await t.tap(
                find.descendant(
                  of: find.byType(GlassNavBar),
                  matching: find.byTooltip('Reels'),
                ),
              );
              await t.pumpAndSettle();
              expect(find.text('Reel for old'), findsOneWidget);
              if (covered) {
                final context = t.element(find.byType(ReelsPage));
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SettingsPage(session: s)),
                );
                await t.pumpAndSettle();
                if (cover == 'saved') {
                  await t.enterText(find.byType(TextField), 'saved');
                  await t.pump();
                  await t.tap(find.text('Saved'));
                  await t.pumpAndSettle();
                  expect(find.byType(SavedPage), findsOneWidget);
                }
              }
              if (change == 'logout') {
                await s.logout();
                await flush(t);
              } else {
                if (change == 'other') owner = 'new';
                delayGrant = true;
                final before = homeReads;
                final oldViewGeneration = s.accountViewGeneration;
                final login = s.login('fixture', 'not-a-password');
                await t.pump();
                expect(s.accountViewGeneration, oldViewGeneration);
                expect(
                  find.byType(HomeShell),
                  findsNothing,
                  reason: 'old shell must quiesce during replacement authentication',
                );
                expect(
                  homeReads,
                  before,
                  reason: 'new shell must not prefetch before replacement auth finishes',
                );
                pendingGrant.complete(
                  reply({'access_token': 'replacement', 'expires_in': 3600}),
                );
                await login;
                await flush(t);
              }
              final generation = s.generation, identity = s.user;
              await t.pumpAndSettle();
              if (covered) {
                expect(find.byType(SessionRecoveryView), findsOneWidget);
                await t.tap(
                  find.widgetWithText(
                    FilledButton,
                    change == 'logout' ? 'Back to sign in' : 'Back to account',
                  ),
                );
                await t.pumpAndSettle();
              }
              if (change == 'logout') {
                expect(find.byType(AuthPage), findsOneWidget);
                expect(find.byType(HomeShell), findsNothing);
              } else {
                expect(find.byType(HomeShell), findsOneWidget);
                expect(find.byType(SessionRecoveryView), findsNothing);
                await t.tap(
                  find.descendant(
                    of: find.byType(GlassNavBar),
                    matching: find.byTooltip('Reels'),
                  ),
                );
                await t.pumpAndSettle();
                expect(find.text('Reel for $owner'), findsOneWidget);
              }
              expect(s.generation, generation);
              expect(identical(s.user, identity), isTrue);
              expect(writes, 0);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
              await t.pump(const Duration(seconds: 5));
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return delayGrant
                    ? pendingGrant.future
                    : reply({'access_token': 'fixture', 'expires_in': 3600});
              }
              if (r.url.path.endsWith('/auth/me')) {
                return reply({
                  'user': {'public_id': owner, 'username': owner},
                });
              }
              if (r.method != 'GET') writes++;
              if (r.url.path.endsWith('/home')) {
                homeReads++;
                return reply({
                  'posts': {'data': [], 'next_cursor': null},
                  'stories': {'data': []},
                  'unread_messages': 0,
                });
              }
              if (r.url.path.endsWith('/posts')) {
                return reply({
                  'data': r.url.queryParameters['kind'] == 'reel'
                      ? [reel(owner)]
                      : [],
                  'next_cursor': null,
                });
              }
              return reply({
                'data': [],
                'next_cursor': null,
                'unread_messages': 0,
                'balance': 0,
                'entries': [],
              });
            }),
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}

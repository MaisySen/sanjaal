// Synthetic replacement authentication with actual app root. No live accounts.
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/main.dart';

http.Response reply(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final f in [
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
      final loader = FontLoader(
        f.$1,
      )..addFont(File(f.$2).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  tearDown(() => prefs.lang = 'en');
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final identityFailure in ['service', 'malformed features']) {
    testWidgets(
      'unverified replacement $identityFailure never reopens old shell and can retry current grant',
      (t) async {
        var grants = 0, meReads = 0, homeReads = 0;
        bool failIdentity = false;
        await http.runWithClient(
          () async {
            await t.pumpWidget(const SanjaalApp());
            await flush(t);
            final s = t.widget<AuthPage>(find.byType(AuthPage)).session;
            await s.login('old', 'not-a-password');
            await flush(t);
            expect(find.byType(HomeShell), findsOneWidget);
            expect(homeReads, 1);
            failIdentity = true;
            await expectLater(
              s.login('new', 'not-a-password'),
              throwsA(isA<ApiError>()),
            );
            await flush(t);
            expect(
              find.byType(HomeShell),
              findsNothing,
              reason: 'new grant with unresolved identity cannot keep old account shell',
            );
            expect(find.byType(RestoreSessionPage), findsOneWidget);
            failIdentity = false;
            await t.tap(find.text('Try again'));
            await flush(t);
            expect(find.byType(RestoreSessionPage), findsNothing);
            expect(find.byType(HomeShell), findsOneWidget);
            expect(s.user?['public_id'], 'new');
            expect(
              grants,
              2,
              reason: 'recovery uses current grant, not another password or stale refresh',
            );
            expect(meReads, 3);
            expect(homeReads, 2);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              grants++;
              return reply({
                'access_token': grants == 1 ? 'old-fixture' : 'new-fixture',
                'expires_in': 3600,
              });
            }
            if (r.url.path.endsWith('/auth/me')) {
              meReads++;
              if (failIdentity) {
                return identityFailure == 'service'
                    ? reply({'message': 'fixture unavailable'}, 503)
                    : reply({
                        'user': {'public_id': 'new', 'username': 'new'},
                        'features': [],
                      });
              }
              return reply({
                'user': {
                  'public_id': grants == 1 ? 'old' : 'new',
                  'username': grants == 1 ? 'old' : 'new',
                },
              });
            }
            if (r.url.path.endsWith('/posts')) {
              homeReads++;
              return reply({'data': [], 'next_cursor': null});
            }
            return reply({
              'data': [],
              'next_cursor': null,
              'unread_messages': 0,
            });
          }),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  for (final outcome in ['success', 'failure']) {
    test(
      'late identity recovery $outcome cannot overwrite or retire a replacement login',
      () async {
        final pending = Completer<http.Response>();
        var grants = 0, meReads = 0;
        await http.runWithClient(
          () async {
            final s = Session();
            await s.login('old', 'not-a-password');
            await expectLater(
              s.login('unverified', 'not-a-password'),
              throwsA(isA<ApiError>()),
            );
            expect(s.accountViewNeedsRefresh, isTrue);
            final recovery = s.recoverAccountView();
            await Future<void>.delayed(Duration.zero);
            expect(s.recoveringAccount, isTrue);
            await s.recoverAccountView();
            expect(meReads, 3, reason: 'duplicate recovery must not overlap');
            await s.login('new', 'not-a-password');
            final generation = s.generation, identity = s.user;
            pending.complete(
              reply(
                outcome == 'success'
                    ? {
                        'user': {'public_id': 'old', 'username': 'old'},
                      }
                    : {'message': 'old failure'},
                outcome == 'success' ? 200 : 503,
              ),
            );
            await recovery;
            expect(s.user?['public_id'], 'new');
            expect(identical(s.user, identity), isTrue);
            expect(s.generation, generation);
            expect(s.restoreError, isNull);
            expect(s.recoveringAccount, isFalse);
            expect(s.accountViewNeedsRefresh, isFalse);
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              grants++;
              return reply({
                'access_token': 'fixture-$grants',
                'expires_in': 3600,
              });
            }
            meReads++;
            if (meReads == 2) {
              return reply({'message': 'fixture unavailable'}, 503);
            }
            if (meReads == 3) return pending.future;
            return reply({
              'user': {
                'public_id': grants == 1 ? 'old' : 'new',
                'username': 'fixture',
              },
            });
          }),
        );
      },
    );
  }
  test('failed replacement grant can revalidate prior grant without clearing credentials', () async {
    var grants = 0, reads = 0;
    await http.runWithClient(
      () async {
        final s = Session();
        await s.login('old', 'not-a-password');
        await expectLater(
          s.login('rejected', 'not-a-password'),
          throwsA(isA<ApiError>()),
        );
        expect(s.accountViewNeedsRefresh, isTrue);
        expect(s.restoreError, isNotNull);
        await expectLater(
          s.call('POST', '/users/new/follow'),
          throwsA(isA<ApiError>()),
        );
        expect(s.mediaHeadersFor('$apiBase/media/fixture'), isEmpty);
        await expectLater(
          s.capturePushRemoval()('fixture-device-token'),
          throwsA(isA<ApiError>()),
        );
        await s.recoverAccountView();
        expect(s.user?['public_id'], 'old');
        expect(s.accountViewNeedsRefresh, isFalse);
        expect(s.restoreError, isNull);
        expect(grants, 2);
        expect(reads, 2);
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) {
          grants++;
          return grants == 1
              ? reply({'access_token': 'old-fixture', 'expires_in': 3600})
              : reply({'error': 'invalid_grant'}, 400);
        }
        reads++;
        expect(r.headers['Authorization'], 'Bearer old-fixture');
        return reply({
          'user': {'public_id': 'old', 'username': 'old'},
        });
      }),
    );
  });
  test('failed identity retry retains recovery and explicit logout still reaches signed-out state', () async {
    var grants = 0, reads = 0;
    await http.runWithClient(
      () async {
        final s = Session(unregisterPush: (_) async {});
        await s.login('old', 'not-a-password');
        await expectLater(
          s.login('new', 'not-a-password'),
          throwsA(isA<ApiError>()),
        );
        final generation = s.generation;
        await s.recoverAccountView();
        expect(s.restoreError, isNotNull);
        expect(s.generation, generation);
        expect(s.accountViewNeedsRefresh, isTrue);
        expect(grants, 2);
        expect(reads, 3);
        await s.logout();
        expect(s.user, isNull);
        expect(s.restoreError, isNull);
        expect(s.accountViewNeedsRefresh, isFalse);
        expect(s.recoveringAccount, isFalse);
        expect(s.authenticating, isFalse);
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/oauth/token')) {
          grants++;
          return reply({'access_token': 'fixture-$grants', 'expires_in': 3600});
        }
        reads++;
        return reads == 1
            ? reply({
                'user': {'public_id': 'old', 'username': 'old'},
              })
            : reply({'message': 'fixture offline'}, 503);
      }),
    );
  });
  for (final invalid in <Object>[
    {},
    {'user': {}},
    {
      'user': {'public_id': 42},
    },
    {
      'user': {'public_id': '  '},
    },
  ]) {
    test(
      'malformed identity never becomes a current account view $invalid',
      () async {
        var meReads = 0;
        await http.runWithClient(
          () async {
            final s = Session();
            await expectLater(
              s.login('fixture', 'not-a-password'),
              throwsA(isA<ApiError>()),
            );
            expect(s.user, isNull);
            expect(s.accountViewNeedsRefresh, isTrue);
            expect(s.restoreError, isNotNull);
            await s.recoverAccountView();
            expect(s.user?['public_id'], 'verified');
            expect(s.accountViewNeedsRefresh, isFalse);
            expect(s.restoreError, isNull);
            expect(meReads, 2);
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/oauth/token')) {
              return reply({'access_token': 'fixture', 'expires_in': 3600});
            }
            meReads++;
            return reply(
              meReads == 1
                  ? invalid
                  : {
                      'user': {'public_id': 'verified', 'username': 'verified'},
                    },
            );
          }),
        );
      },
    );
  }
  for (final lang in ['en', 'ne']) {
    for (final mode in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'unverified identity retry remains accessible at narrow large text $lang ${mode.name}',
        (t) async {
          prefs.lang = lang;
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          var reads = 0;
          await http.runWithClient(
            () async {
              final s = Session();
              await expectLater(
                s.login('fixture', 'not-a-password'),
                throwsA(isA<ApiError>()),
              );
              s.loading = false; // Actual root restore has already completed before sign-in.
              final key = GlobalKey();
              await t.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
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
                    home: RestoreSessionPage(session: s),
                  ),
                ),
              );
              await t.pumpAndSettle();
              final retry = find.widgetWithText(
                OutlinedButton,
                t_('Try again'),
              );
              await t.ensureVisible(retry);
              await t.pumpAndSettle();
              expect(retry.hitTestable(), findsOneWidget);
              expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
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
                  '/downloads/sanjaal-discovery-review/account-retry-$lang-${mode.name}.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
              await t.tap(retry);
              await t.pumpAndSettle();
              expect(reads, 2);
              expect(s.user?['public_id'], 'verified');
              expect(s.accountViewNeedsRefresh, isFalse);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            },
            () => MockClient((r) async {
              if (r.url.path.endsWith('/oauth/token')) {
                return reply({'access_token': 'fixture', 'expires_in': 3600});
              }
              reads++;
              return reads == 1
                  ? reply({'message': 'fixture unavailable'}, 503)
                  : reply({
                      'user': {'public_id': 'verified', 'username': 'verified'},
                    });
            }),
          );
        },
      );
    }
  }
}

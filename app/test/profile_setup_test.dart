// Offline signup, account and profile fixtures. No real signup or media request.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/profile_setup_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;
import 'profile_journey_test.dart' as p;

// Unlike the shared upload fixture, this forwards every non-GET account
// request so zero-write assertions cannot accidentally swallow profile saves.
Future<void> fixture(
  WidgetTester t,
  Future<void> Function(Session) run, {
  Future<http.Response> Function(http.Request)? respond,
}) async {
  SharedPreferences.setMockInitialValues({});
  await http.runWithClient(
    () async {
      final session = Session();
      await session.login('fixture', 'not-a-password');
      await h.flush(t);
      await run(session);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    },
    () => MockClient((r) async {
      if (r.url.path.endsWith('/oauth/token')) {
        return h.json({'access_token': 'fixture', 'expires_in': 3600});
      }
      if (r.method == 'GET' && r.url.path.endsWith('/auth/me')) {
        return h.json({
          'user': {'public_id': 'me', 'username': 'fixture'},
        });
      }
      return respond == null ? h.json({'data': []}) : respond(r);
    }),
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
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
      final loader = FontLoader(f.$1)
        ..addFont(
          Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  testWidgets(
    'registration alone offers optional setup and Continue never saves',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var signups = 0, writes = 0;
      await fixture(
        t,
        (s) async {
          expect(s.profileSetupPending, isFalse);
          await s.register(
            'new@fixture.invalid',
            'newmember',
            'fixture-password',
          );
          expect(s.profileSetupPending, isTrue);
          await t.pumpWidget(
            MaterialApp(
              home: ListenableBuilder(
                listenable: s,
                builder: (_, child) => s.profileSetupPending
                    ? ProfileSetupPage(session: s)
                    : const Scaffold(body: Text('Main app')),
              ),
            ),
          );
          await h.flush(t);
          expect(find.text('This is optional.'), findsNothing);
          expect(find.textContaining('This is optional.'), findsOneWidget);
          await t.tap(find.text('Continue to Sanjaal'));
          await h.flush(t);
          expect(s.profileSetupPending, isFalse);
          expect(find.text('Main app'), findsOneWidget);
          expect(signups, 1);
          expect(writes, 0);
        },
        respond: (r) async {
          if (r.url.path.endsWith('/dbconnections/signup')) {
            signups++;
            return h.json({});
          }
          if (r.method != 'GET') writes++;
          return h.json({'data': []});
        },
      );
    },
  );
  testWidgets(
    'normal login and replacement login never resurrect optional setup',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await fixture(t, (s) async {
        expect(s.profileSetupPending, isFalse);
        await s.register(
          'new@fixture.invalid',
          'newmember',
          'fixture-password',
        );
        expect(s.profileSetupPending, isTrue);
        await s.login('replacement', 'fixture-password');
        expect(s.profileSetupPending, isFalse);
        await t.runAsync(s.logout);
        expect(s.profileSetupPending, isFalse);
      }, respond: (_) async => h.json({}));
    },
  );
  testWidgets('retained Continue cannot dismiss a newer registration offer', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await fixture(t, (s) async {
      await s.register('new@fixture.invalid', 'newmember', 'fixture-password');
      await t.pumpWidget(MaterialApp(home: ProfileSetupPage(session: s)));
      await h.flush(t);
      final old = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue to Sanjaal'),
          )
          .onPressed!;
      await s.register(
        'newer@fixture.invalid',
        'newermember',
        'fixture-password',
      );
      await h.flush(t);
      expect(s.profileSetupPending, isTrue);
      old();
      await h.flush(t);
      expect(s.profileSetupPending, isTrue);
      expect(find.text('Make your profile yours'), findsNothing);
    }, respond: (_) async => h.json({}));
  });
  testWidgets(
    'explicit Edit uses real editor and cancellation keeps offer without a write',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var writes = 0;
      await fixture(
        t,
        (s) async {
          await s.register(
            'new@fixture.invalid',
            'newmember',
            'fixture-password',
          );
          await t.pumpWidget(MaterialApp(home: ProfileSetupPage(session: s)));
          await h.flush(t);
          await t.tap(find.text('Add a name or photo'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(EditProfilePage), findsOneWidget);
          await t.pageBack();
          await h.flush(t);
          await t.pumpAndSettle();
          expect(s.profileSetupPending, isTrue);
          expect(writes, 0);
        },
        respond: (r) async {
          if (!r.url.path.endsWith('/dbconnections/signup') &&
              r.method != 'GET') {
            writes++;
          }
          return h.json({});
        },
      );
    },
  );
  testWidgets('failed automatic sign-in after signup does not offer setup', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final session = Session();
    await http.runWithClient(
      () async {
        await expectLater(
          session.register(
            'new@fixture.invalid',
            'newmember',
            'fixture-password',
          ),
          throwsA(isA<AccountCreatedSignInRequired>()),
        );
        expect(session.profileSetupPending, isFalse);
        expect(session.user, isNull);
      },
      () => MockClient(
        (r) async => r.url.path.endsWith('/dbconnections/signup')
            ? h.json({})
            : h.json({'error': 'invalid_grant'}, 400),
      ),
    );
  });
  testWidgets(
    'restoring credentials does not recreate completed or skipped setup',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'refresh_token': 'fixture-refresh',
      });
      final session = Session();
      await http.runWithClient(
        () async {
          await session.restore();
          expect(session.user?['public_id'], 'restored-id');
          expect(session.profileSetupPending, isFalse);
        },
        () => MockClient(
          (r) async => r.url.path.endsWith('/oauth/token')
              ? h.json({'access_token': 'fixture', 'expires_in': 3600})
              : h.json({
                  'user': {'public_id': 'restored-id', 'username': 'restored'},
                }),
        ),
      );
    },
  );
  testWidgets(
    'explicit profile save persists through real editor without forcing completion',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      var writes = 0;
      final s = Session();
      await http.runWithClient(
        () async {
          await s.register(
            'new@fixture.invalid',
            'newmember',
            'fixture-password',
          );
          await t.pumpWidget(MaterialApp(home: ProfileSetupPage(session: s)));
          await h.flush(t);
          await t.tap(find.text('Add a name or photo'));
          await h.flush(t);
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const ValueKey('profile-name')));
          await t.enterText(
            find.byKey(const ValueKey('profile-name')),
            'New name',
          );
          await t.tap(find.text('Save'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(writes, 1);
          expect(find.byType(EditProfilePage), findsNothing);
          expect(s.user?['name'], 'New name');
          expect(s.profileSetupPending, isTrue);
          await t.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/dbconnections/signup')) return h.json({});
          if (r.url.path.endsWith('/oauth/token')) {
            return h.json({'access_token': 'fixture', 'expires_in': 3600});
          }
          if (r.method == 'PATCH') {
            expect(r.url.path, endsWith('/auth/me'));
            writes++;
            return h.json({
              'user': {
                'public_id': 'me',
                'username': 'fixture',
                'name': 'New name',
                'bio': '',
              },
            });
          }
          return h.json({
            'user': {
              'public_id': 'me',
              'username': 'fixture',
              'name': 'Fixture',
              'bio': '',
            },
          });
        }),
      );
    },
  );
  for (final status in [400, 503]) {
    testWidgets('failed signup $status never offers setup', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await fixture(t, (s) async {
        await expectLater(
          s.register('new@fixture.invalid', 'newmember', 'fixture-password'),
          throwsA(isA<ApiError>()),
        );
        expect(s.profileSetupPending, isFalse);
      }, respond: (_) async => h.json({}, status));
    });
  }
  testWidgets(
    'actual app registration opens setup before feed and Continue reaches main app',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({'onboarded': true});
      FlutterSecureStorage.setMockInitialValues({});
      var signups = 0;
      await http.runWithClient(
        () async {
          await t.pumpWidget(const SanjaalApp(fontFamily: 'Roboto'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(AuthPage), findsOneWidget);
          await t.ensureVisible(find.text('Create an account'));
          await t.tap(find.text('Create an account'));
          await t.pumpAndSettle();
          await t.enterText(
            find.byType(TextFormField).at(0),
            'new@fixture.invalid',
          );
          await t.enterText(find.byType(TextFormField).at(1), 'newmember');
          await t.enterText(
            find.byType(TextFormField).at(2),
            'fixture-password',
          );
          await t.ensureVisible(find.text('Create account'));
          await t.tap(find.text('Create account'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(signups, 1);
          expect(find.byType(ProfileSetupPage), findsOneWidget);
          expect(find.byType(HomeShell), findsNothing);
          await t.ensureVisible(find.text('Continue to Sanjaal'));
          await t.tap(find.text('Continue to Sanjaal'));
          await h.flush(t);
          await t.pumpAndSettle();
          expect(find.byType(HomeShell), findsOneWidget);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 5));
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/dbconnections/signup')) {
            signups++;
            return h.json({});
          }
          if (r.url.path.endsWith('/oauth/token')) {
            return h.json({'access_token': 'fixture', 'expires_in': 3600});
          }
          if (r.url.path.endsWith('/auth/me')) {
            return h.json({
              'user': {
                'public_id': 'new-id',
                'username': 'newmember',
                'name': 'newmember',
              },
            });
          }
          return h.json({
            'data': [],
            'next_cursor': null,
            'unread_messages': 0,
            'balance': 0,
            'entries': [],
          });
        }),
      );
    },
  );
  for (final lang in ['en', 'ne']) {
    testWidgets(
      'optional setup fits narrow large text and Continue remains reachable $lang',
      (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        prefs.lang = lang;
        addTearDown(() => prefs.lang = 'en');
        await fixture(t, (s) async {
          await s.register(
            'new@fixture.invalid',
            'newmember',
            'fixture-password',
          );
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
                home: ProfileSetupPage(session: s),
              ),
            ),
          );
          await h.flush(t);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(
            find.text(t_('Add a name or photo')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.text(t_('Continue to Sanjaal')).hitTestable(),
            findsOneWidget,
          );
          await p.shot(t, 'optional_setup_$lang');
          await t.ensureVisible(
            find.text(
              t_('You can change your profile later from Edit profile.'),
            ),
          );
          await t.pumpAndSettle();
          expect(
            find.text(t_('Continue to Sanjaal')).hitTestable(),
            findsOneWidget,
          );
          await p.shot(t, 'optional_setup_continue_$lang');
        }, respond: (_) async => h.json({}));
      },
    );
  }
}

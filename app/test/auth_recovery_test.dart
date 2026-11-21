// Offline fixtures only. No Auth0, email delivery, credentials or real accounts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/auth_failure.dart';
import 'package:sanjaal/password_recovery_page.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/ui.dart' show prefs;

void main() {
  setUpAll(() async {
    for (final f in [('Roboto', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
      ('MaterialIcons', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf')]) {
      final loader = FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())));
      await loader.load();
    }
  });
  test('auth UI excludes arbitrary provider and runtime content', () {
    for (final e in [ApiError('provider diagnostic fixture'), StateError('fixture path'),
      const SocketException('fixture host'), ApiError('<html>fixture</html>', 503)]) {
      expect(authFailureMessage(e), 'Sign in failed. Try again.');
      expect(authFailureMessage(e, registering: true), 'Could not create your account. Try again.');
    }
    expect(authFailureMessage(ApiError('fixture', 429)), 'Too many attempts. Wait a moment, then try again.');
  });

  for (final status in [200, 404]) {
    test('recovery status $status is neutral and does not sign in', () async {
      final session = Session();
      var requests = 0;
      await http.runWithClient(() async {
        await session.requestPasswordReset(' fixture@example.com ');
        expect(session.user, isNull);
        await expectLater(session.requestPasswordReset('other@example.com'), throwsA(isA<ApiError>()));
        expect(requests, 1);
      }, () => MockClient((r) async {
        requests++;
        expect(r.url.scheme, 'https');
        expect(r.url.host, auth0Domain);
        expect(r.url.path, '/dbconnections/change_password');
        expect(r.method, 'POST');
        expect(jsonDecode(r.body), {
          'client_id': auth0ClientId, 'email': 'fixture@example.com',
          'connection': 'Username-Password-Authentication',
        });
        expect(r.headers.keys.any((h) => h.toLowerCase() == 'authorization'), isFalse);
        return http.Response('provider prose must not appear in UI', status);
      }));
    });
  }
  for (final status in [400, 401, 429, 500]) {
    test('recovery status $status is not a success and hides provider prose', () async {
      await http.runWithClient(() async {
        await expectLater(Session().requestPasswordReset('fixture@example.com'),
          throwsA(isA<ApiError>().having((e) => e.message, 'safe message',
            status == 429 ? 'Too many attempts. Wait a moment, then try again.' : 'Could not send the reset link. Try again.')));
      }, () => MockClient((_) async => http.Response('fixture provider diagnostic', status)));
    });
  }
  test('recovery blocks double requests and invalid email without touching session', () async {
    var requests = 0;
    final pending = Completer<http.Response>();
    final session = Session();
    await http.runWithClient(() async {
      await expectLater(session.requestPasswordReset('not-an-email'), throwsA(isA<ApiError>()));
      final first = session.requestPasswordReset('fixture@example.com');
      await expectLater(session.requestPasswordReset('fixture@example.com'), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      final sent = requests;
      pending.complete(http.Response('fixture', 200));
      await first;
      expect(sent, 1);
    }, () => MockClient((_) { requests++; return pending.future; }));
  });
  for (final code in ['invalid_grant', 'unsupported_grant_type']) {
    test('grant maps $code without displaying provider prose', () async {
      await http.runWithClient(() async {
        await expectLater(Session().login('fixture', 'x'), throwsA(isA<ApiError>().having(
          (e) => e.message, 'safe message', code == 'invalid_grant' ? 'Wrong email or password.' : 'Sign in failed. Try again.')));
      }, () => MockClient((_) async => http.Response(jsonEncode({'error': code,
        'error_description': 'fixture provider diagnostic'}), 400)));
    });
  }
  test('successful registration followed by failed sign-in is not called account creation failure', () async {
    await http.runWithClient(() async {
      await expectLater(_CreatedAccountSession().register('fixture@example.com', 'fixture', 'fixture-value'),
        throwsA(isA<ApiError>().having((e) => e.message, 'acknowledgement',
          'Your account was created. Sign in to continue.')));
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
  test('recovery transport failure does not claim the email was sent', () async {
    await http.runWithClient(() async {
      await expectLater(Session().requestPasswordReset('fixture@example.com'),
        throwsA(isA<ApiError>().having((e) => e.message, 'safe message',
          'No connection. Check your internet and try again.')));
    }, () => MockClient((_) async => throw const SocketException('fixture host')));
  });
  testWidgets('sign-in accepts an existing nonempty short password and preserves fields on failure', (t) async {
    final session = _ShortPasswordSession();
    await t.pumpWidget(MaterialApp(home: AuthPage(session: session)));
    await t.enterText(find.byType(TextFormField).first, 'fixture');
    await t.enterText(find.byType(TextFormField).last, 'x');
    await t.ensureVisible(find.byType(FilledButton));
    await t.tap(find.byType(FilledButton)); await t.pumpAndSettle();
    expect(session.password, 'x');
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(t.widget<EditableText>(find.byType(EditableText).first).controller.text, 'fixture');
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, 'x');
  });
  testWidgets('recovery validates email and suppresses a late result after leaving', (t) async {
    final pending = Completer<http.Response>(); var count = 0;
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp(home: PasswordRecoveryPage(session: Session(), initialEmail: 'username')));
      await t.tap(find.text('Send reset link')); await t.pump();
      expect(find.text('Enter a valid email'), findsOneWidget); expect(count, 0);
      await t.enterText(find.byType(TextFormField), 'fixture@example.com');
      await t.tap(find.text('Send reset link')); await t.pump();
      expect(count, 1); expect(t.widget<TextFormField>(find.byType(TextFormField)).enabled, isFalse);
      await t.pumpWidget(const SizedBox());
      pending.complete(http.Response('fixture', 200)); await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }, () => MockClient((_) { count++; return pending.future; }));
  });
  for (final lang in ['en', 'ne']) {
    for (final sent in [false, true]) {
      testWidgets('recovery small screen large text $lang sent=$sent', (t) async {
        prefs.lang = lang; addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640); t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await http.runWithClient(() async {
          await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark, fontFamily: 'Roboto'),
            builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(1.8), viewInsets: const EdgeInsets.only(bottom: 220)), child: w!),
            home: RepaintBoundary(key: const ValueKey('recovery-capture'),
              child: PasswordRecoveryPage(session: Session(), initialEmail: 'fixture@example.com'))));
          await t.pumpAndSettle();
          final button = find.byType(FilledButton);
          await t.ensureVisible(button); await t.pumpAndSettle();
          if (sent) { await t.tap(button); await t.pumpAndSettle(); }
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.byType(FilledButton)); await t.pumpAndSettle();
          expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('recovery-capture')));
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            Directory('test/renders').createSync(recursive: true);
            File('test/renders/recovery_${lang}_${sent ? 'sent' : 'form'}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
          });
          await t.pumpWidget(const SizedBox()); await t.pumpAndSettle();
        }, () => MockClient((_) async => http.Response('fixture', 200)));
      });
    }
  }
}
class _ShortPasswordSession extends Session {
  String? password;
  @override Future<void> login(String id, String password) async {
    this.password = password;
    throw ApiError('Wrong email or password.');
  }
}

class _CreatedAccountSession extends Session {
  @override Future<void> login(String id, String password) async {
    throw ApiError('fixture sign-in failure');
  }
}

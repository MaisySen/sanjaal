// Synthetic platform-channel and account fixtures. No email app, message or deletion.
import 'dart:async';
import 'dart:io';

import 'profile_journey_test.dart' as p;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/settings_page.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

import 'upload_center_test.dart' as h;

const mailChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  visualMailRecoveryTests();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mailChannel, null);
    prefs.lang = 'en';
  });
  for (final deletion in [false, true]) {
    testWidgets('mail composer platform failure recovers deletion=$deletion', (
      t,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mailChannel, (_) async {
            throw PlatformException(
              code: 'unavailable',
              message: 'fixture only',
            );
          });
      await h.fixture(t, (s, c) async {
        await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
        await h.flush(t);
        await t.enterText(
          find.byType(TextField),
          deletion ? 'Delete my account' : 'Contact us',
        );
        await t.pump();
        await t.tap(
          find.widgetWithText(
            ListTile,
            deletion ? 'Delete my account' : 'Contact us',
          ),
        );
        await h.flush(t);
        expect(t.takeException(), isNull);
        expect(
          find.text(
            deletion
                ? 'Email contact@fintex.au to request account deletion.'
                : 'Email contact@fintex.au for help.',
          ),
          findsOneWidget,
        );
      });
    });
  }
  testWidgets(
    'mail composer rejects repeated contact and deletion launches until completion',
    (t) async {
      final answer = Completer<bool>();
      final launched = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mailChannel, (call) async {
            launched.add((call.arguments as Map)['url'] as String);
            return answer.future;
          });
      await h.fixture(t, (s, c) async {
        await t.pumpWidget(MaterialApp(home: SettingsPage(session: s)));
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'Contact us');
        await t.pump();
        final contact = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Contact us'))
            .onTap!;
        contact();
        contact();
        await t.enterText(find.byType(TextField), 'Delete my account');
        await t.pump();
        final deletion = t
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Delete my account'),
            )
            .onTap!;
        deletion();
        await h.flush(t);
        expect(launched, hasLength(1));
        answer.complete(true);
        await h.flush(t);
        deletion();
        await h.flush(t);
        expect(launched, hasLength(2));
        final uri = Uri.parse(launched.last);
        expect(uri.scheme, 'mailto');
        expect(uri.path, 'contact@fintex.au');
        expect(uri.queryParameters['subject'], 'Delete my Sanjaal account');
        expect(uri.queryParameters['body'], contains('Username: fixture'));
        expect(t.takeException(), isNull);
      });
    },
  );
  for (final retire in [false, true]) {
    testWidgets(
      'mail completion stays with owning route and session retire=$retire',
      (t) async {
        final answer = Completer<bool>();
        var launches = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(mailChannel, (_) async {
              launches++;
              return answer.future;
            });
        final nav = GlobalKey<NavigatorState>();
        await h.fixture(t, (s, c) async {
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: SettingsPage(session: s),
            ),
          );
          await h.flush(t);
          await t.enterText(find.byType(TextField), 'Contact us');
          await t.pump();
          final contact = t
              .widget<ListTile>(find.widgetWithText(ListTile, 'Contact us'))
              .onTap!;
          contact();
          await h.flush(t);
          if (retire) {
            await s.login('fixture', 'not-a-password');
            await h.flush(t);
          } else {
            unawaited(
              nav.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Cover route')),
                ),
              ),
            );
            await t.pumpAndSettle();
          }
          answer.complete(false);
          await h.flush(t);
          expect(find.text('Email contact@fintex.au for help.'), findsNothing);
          contact();
          await h.flush(t);
          expect(launches, 1);
          expect(find.text('Email contact@fintex.au for help.'), findsNothing);
          expect(t.takeException(), isNull);
        });
      },
    );
  }
}

void visualMailRecoveryTests() {
  for (final lang in ['en', 'ne']) {
    for (final deletion in [false, true]) {
      testWidgets(
        'unavailable mail fallback fits narrow large text $lang deletion=$deletion',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          var launches = 0;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(mailChannel, (_) async {
                launches++;
                return false;
              });
          await p.fixture(
            t,
            (s) => SettingsPage(session: s),
            () async {
              await t.enterText(
                find.byType(TextField),
                deletion ? 'delete' : 'support',
              );
              await t.pump();
              if (deletion) {
                expect(
                  find.text(t_('Opens a draft in your email app')),
                  findsOneWidget,
                );
                expect(find.text('Sends a request by email'), findsNothing);
                expect(find.text('इमेलबाट अनुरोध पठाउँछ'), findsNothing);
              }
              final row = find.widgetWithText(
                ListTile,
                t_(deletion ? 'Delete my account' : 'Contact us'),
              );
              await t.tap(row);
              await h.flush(t);
              expect(
                find.text(
                  t_(
                    deletion
                        ? 'Email contact@fintex.au to request account deletion.'
                        : 'Email contact@fintex.au for help.',
                  ),
                ),
                findsOneWidget,
              );
              expect(t.takeException(), isNull);
              await p.shot(
                t,
                'mail_recovery_${lang}_${deletion ? 'deletion' : 'contact'}',
              );
              await t.tap(row);
              await h.flush(t);
              expect(launches, 2);
              expect(t.takeException(), isNull);
            },
            language: lang,
            scale: 1.8,
            brightness: lang == 'en' ? Brightness.light : Brightness.dark,
          );
        },
      );
    }
  }
  testWidgets(
    'covered settings callback rejects launch then reopens after Back',
    (t) async {
      var launches = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mailChannel, (_) async {
            launches++;
            return true;
          });
      final nav = GlobalKey<NavigatorState>();
      await h.fixture(t, (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: SettingsPage(session: s),
          ),
        );
        await h.flush(t);
        await t.enterText(find.byType(TextField), 'support');
        await t.pump();
        final contact = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Contact us'))
            .onTap!;
        unawaited(
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover route')),
            ),
          ),
        );
        await t.pumpAndSettle();
        contact();
        await h.flush(t);
        expect(launches, 0);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        contact();
        await h.flush(t);
        expect(launches, 1);
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'disposed settings absorbs late composer failure without showing on root',
    (t) async {
      final answer = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mailChannel, (_) => answer.future);
      final nav = GlobalKey<NavigatorState>();
      await h.fixture(t, (s, c) async {
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Root route')),
          ),
        );
        unawaited(
          nav.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => SettingsPage(session: s)),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'support');
        await t.pump();
        await t.tap(find.widgetWithText(ListTile, 'Contact us'));
        await h.flush(t);
        await t.pageBack();
        await t.pumpAndSettle();
        answer.completeError(
          PlatformException(code: 'unavailable', message: 'fixture only'),
        );
        await h.flush(t);
        expect(find.text('Root route'), findsOneWidget);
        expect(find.text('Email contact@fintex.au for help.'), findsNothing);
        expect(t.takeException(), isNull);
      });
    },
  );
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/onboarding_page.dart';
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/about_page.dart';
import 'package:sanjaal/language_settings_page.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pump();
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final f in [
      (
        'Roboto',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
    ]) {
      await (FontLoader(f.$1)..addFont(
            File(f.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  testWidgets(
    'language write rejection is visible and explicit retry persists without duplicate writes',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      var fail = true, writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getAll' ||
                call.method == 'getAllWithParameters') {
              return <String, Object>{};
            }
            if (call.method == 'setString') {
              writes++;
              return !fail;
            }
            throw StateError('Unexpected preference operation');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      SharedPreferences.resetStatic();
      prefs.lang = 'en';
      addTearDown(() => prefs.lang = 'en');
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, fontFamily: 'Roboto'),
          home: const LanguageSettingsPage(),
        ),
      );
      final tap = t
          .widget<ListTile>(find.widgetWithText(ListTile, 'नेपाली'))
          .onTap!;
      tap();
      tap();
      await flush(t);
      expect(writes, 1);
      expect(prefs.lang, 'ne');
      expect(
        find.text(
          t_(
            'Language changed for now, but could not be saved. Choose it again to retry.',
          ),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      fail = false;
      await t.tap(find.text('नेपाली'));
      await flush(t);
      expect(writes, 2);
      expect((await SharedPreferences.getInstance()).getString('lang'), 'ne');
      expect(
        find.text(
          t_(
            'Language changed for now, but could not be saved. Choose it again to retry.',
          ),
        ),
        findsNothing,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final registration in [false, true]) {
    testWidgets(
      'signed out root language change preserves ${registration ? 'registration' : 'sign in'} draft without submitting',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'theme': 'light',
          'lang': 'en',
          'onboarded': true,
        });
        FlutterSecureStorage.setMockInitialValues({});
        prefs.lang = 'en';
        await t.pumpWidget(const SanjaalApp(fontFamily: 'Roboto'));
        await flush(t);
        if (registration) {
          await t.tap(find.text('Create an account'));
          await flush(t);
        }
        final fields = find.byType(TextFormField);
        await t.enterText(fields.first, 'fixture@invalid.example');
        if (registration) await t.enterText(fields.at(1), 'fixture_user');
        await t.enterText(fields.last, 'synthetic-password');
        final show = find.byTooltip('Show password');
        await t.ensureVisible(show);
        await t.tap(show);
        await flush(t);
        expect(
          t
              .widget<EditableText>(
                find.descendant(
                  of: fields.last,
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isFalse,
        );
        // The root, not an isolated form, must retain editor state on locale changes.
        final language = find.text('Language');
        await t.ensureVisible(language);
        await t.tap(language);
        await flush(t);
        await t.tap(find.text('नेपाली'));
        await flush(t);
        await t.pageBack();
        await flush(t);
        expect(
          t.widget<TextFormField>(fields.first).controller!.text,
          'fixture@invalid.example',
        );
        expect(
          t.widget<TextFormField>(fields.last).controller!.text,
          'synthetic-password',
        );
        if (registration) {
          expect(
            t.widget<TextFormField>(fields.at(1)).controller!.text,
            'fixture_user',
          );
        }
        expect(
          t
              .widget<EditableText>(
                find.descendant(
                  of: fields.last,
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await flush(t);
      },
    );
  }
  for (final shape in [
    (390.0, 1.0, 'en', 'light'),
    (320.0, 1.8, 'ne', 'dark'),
  ]) {
    testWidgets(
      'actual welcome language legal return and signup ${shape.$1} ${shape.$3}',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'theme': shape.$4,
          'lang': 'en',
          'onboarded': false,
        });
        FlutterSecureStorage.setMockInitialValues({});
        prefs.lang = 'en';
        t.view.physicalSize = Size(shape.$1, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        t.platformDispatcher.textScaleFactorTestValue = shape.$2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: const SanjaalApp(fontFamily: 'Roboto'),
          ),
        );
        await flush(t);
        expect(find.byType(OnboardingPage), findsOneWidget);
        await t.tap(find.text('Language'));
        await flush(t);
        expect(find.byType(LanguageSettingsPage), findsOneWidget);
        await t.tap(find.text(shape.$3 == 'ne' ? 'नेपाली' : 'English'));
        await flush(t);
        await t.pageBack();
        await flush(t);
        expect(find.byType(OnboardingPage), findsOneWidget);
        expect(prefs.lang, shape.$3);
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/sj-welcome-options-${shape.$3}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        final legal = find.text(t_('About, privacy and terms'));
        await t.ensureVisible(legal);
        await t.tap(legal);
        await flush(t);
        expect(find.byType(AboutPage), findsOneWidget);
        expect(find.text(t_('Privacy')), findsOneWidget);
        await t.scrollUntilVisible(
          find.text(t_('Terms')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(t_('Terms')), findsOneWidget);
        await t.pageBack();
        await flush(t);
        expect(find.byType(OnboardingPage), findsOneWidget);
        expect(prefs.seenOnboarding, isFalse);
        final create = find.text(t_('Create an account'));
        await t.ensureVisible(create);
        await t.tap(create);
        await flush(t);
        expect(find.byType(AuthPage), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(
          (await SharedPreferences.getInstance()).getString('lang'),
          shape.$3,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await flush(t);
      },
    );
  }
}

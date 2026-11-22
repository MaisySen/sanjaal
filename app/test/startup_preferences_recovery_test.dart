import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/main.dart';
import 'package:sanjaal/onboarding_page.dart';
import 'package:sanjaal/ui.dart' show AppPrefs, prefs, t_;
import 'package:sanjaal/glass/glass_settings.dart';

Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pump();
  await t.pump();
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
    'actual root handles platform read failure and explicit retry reloads storage',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      var fail = true;
      var reads = 0;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'getAll' ||
                call.method == 'getAllWithParameters') {
              reads++;
              if (fail) {
                throw PlatformException(code: 'fixture_storage_read_failure');
              }
              return {
                'flutter.theme': 'light',
                'flutter.lang': 'en',
                'flutter.onboarded': false,
              };
            }
            throw StateError('Unexpected preference mutation ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      SharedPreferences.resetStatic();
      FlutterSecureStorage.setMockInitialValues({});
      prefs.lang = 'en';
      prefs.ready = false;
      await t.pumpWidget(const SanjaalApp(fontFamily: 'Roboto'));
      await flush(t);
      expect(t.takeException(), isNull);
      expect(
        find.text('Device preferences could not be loaded.'),
        findsOneWidget,
      );
      final before = reads;
      fail = false;
      final retry = t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Try again'),
          )
          .onPressed!;
      retry();
      retry();
      await flush(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(
        reads,
        before + 2,
        reason:
            'one new getInstance and one explicit reload, no duplicate retry',
      );
      expect(
        calls.every((c) => c == 'getAll' || c == 'getAllWithParameters'),
        isTrue,
      );
      expect(
        find.byType(RestoreSessionPage),
        findsOneWidget,
        reason: 'preference retry must not suppress the separate session restore failure',
      );
      await t.tap(find.text('Try again'));
      await flush(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await flush(t);
    },
  );
  test(
    'failed field reads do not publish partial preference snapshots',
    () async {
      SharedPreferences.setMockInitialValues({'theme': 'light', 'lang': 7});
      final p = AppPrefs()
        ..mode = ThemeMode.system
        ..lang = 'ne'
        ..seenOnboarding = true;
      var notifications = 0;
      p.addListener(() => notifications++);
      await expectLater(p.load(), throwsA(isA<TypeError>()));
      expect(p.mode, ThemeMode.system);
      expect(p.lang, 'ne');
      expect(p.ready, isFalse);
      expect(notifications, 0);
      SharedPreferences.setMockInitialValues({
        'glass_transparency': .9,
        'glass_reduced': 7,
      });
      final g = GlassSettings()
        ..transparency = .2
        ..reduced = true;
      await expectLater(g.load(), throwsA(isA<TypeError>()));
      expect(g.transparency, .2);
      expect(g.reduced, isTrue);
    },
  );
  for (final field in [
    'theme',
    'lang',
    'onboarded',
    'glass_transparency',
    'glass_reduced',
  ]) {
    testWidgets(
      'actual root recovers from unreadable $field without erasing storage',
      (t) async {
        SharedPreferences.setMockInitialValues({
          'theme': 'light',
          'lang': 'en',
          'onboarded': false,
          field: field == 'glass_transparency' ? 'bad' : 17,
          'unrelated': 'keep',
        });
        FlutterSecureStorage.setMockInitialValues({});
        prefs.lang = field == 'lang' ? 'ne' : 'en';
        prefs.ready = false;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: const SanjaalApp(fontFamily: 'Roboto'),
          ),
        );
        await flush(t);
        expect(t.takeException(), isNull);
        expect(
          find.text(t_('Device preferences could not be loaded.')),
          findsOneWidget,
        );
        expect(find.byType(OnboardingPage), findsNothing);
        final storage = await SharedPreferences.getInstance();
        expect(storage.get('unrelated'), 'keep');
        expect(storage.get(field), field == 'glass_transparency' ? 'bad' : 17);
        if (field == 'theme' || field == 'lang') {
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('/tmp/sj-preference-error-$field.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        // External repair is simulated. Retry must reread, not erase or replace defaults.
        SharedPreferences.setMockInitialValues({
          'theme': 'light',
          'lang': 'en',
          'onboarded': false,
          'unrelated': 'keep',
        });
        await t.tap(find.text(t_('Try again')));
        await flush(t);
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        expect(find.byType(OnboardingPage), findsOneWidget);
        expect(prefs.mode, ThemeMode.light);
        expect(
          (await SharedPreferences.getInstance()).getString('unrelated'),
          'keep',
        );
        await t.pumpWidget(const SizedBox());
        await flush(t);
      },
    );
  }
}

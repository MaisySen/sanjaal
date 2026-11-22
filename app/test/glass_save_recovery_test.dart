import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/glass/glass_settings.dart';
import 'package:sanjaal/appearance_settings_page.dart';
import 'package:sanjaal/ui.dart' show prefs, t_;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  void platform(Future<Object?> Function(MethodCall) handler) {
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  for (final reduced in [false, true]) {
    test(
      'glass ${reduced ? 'reduced' : 'transparency'} false write rejects',
      () async {
        platform((c) async {
          if (c.method == 'getAll' || c.method == 'getAllWithParameters') {
            return <String, Object>{};
          }
          return false;
        });
        final settings = GlassSettings();
        await expectLater(
          reduced ? settings.setReduced(true) : settings.setTransparency(.7),
          throwsStateError,
        );
      },
    );
  }
  test(
    'queued snapshots preserve newest intent after an earlier failed write',
    () async {
      final first = Completer<bool>();
      final writes = <Object?>[];
      var count = 0;
      platform((c) async {
        if (c.method == 'getAll' || c.method == 'getAllWithParameters') {
          return <String, Object>{};
        }
        writes.add((c.arguments as Map)['value']);
        count++;
        if (count == 1) return first.future;
        return true;
      });
      final settings = GlassSettings();
      final a = settings.setTransparency(.2);
      final rejected = expectLater(a, throwsStateError);
      final b = settings.setTransparency(.8);
      await Future<void>.delayed(Duration.zero);
      expect(writes, [.2]);
      expect(settings.transparency, .8);
      expect(settings.saving, isTrue);
      first.complete(false);
      await rejected;
      await b;
      expect(writes, [.2, false, .8, false]);
      expect(settings.saving, isFalse);
      expect(settings.saveFailed, isFalse);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getDouble('glass_transparency'), .8);
    },
  );
  testWidgets(
    'slider previews without writes then failure survives reopening and explicit retry',
    (t) async {
      var fail = true;
      final writes = <String>[];
      platform((c) async {
        if (c.method == 'getAll' || c.method == 'getAllWithParameters') {
          return <String, Object>{};
        }
        writes.add(c.method);
        return !fail;
      });
      prefs.lang = 'en';
      glassSettings.transparency = .5;
      glassSettings.reduced = false;
      Future<void> show() async {
        await t.pumpWidget(const MaterialApp(home: AppearanceSettingsPage()));
        await t.pumpAndSettle();
      }

      await show();
      final slider = t.widget<Slider>(find.byType(Slider));
      slider.onChanged!(.2);
      slider.onChanged!(.4);
      slider.onChanged!(.9);
      await t.pumpAndSettle();
      expect(writes, isEmpty);
      expect(glassSettings.transparency, .9);
      slider.onChangeEnd!(.9);
      await t.pumpAndSettle();
      expect(writes.length, 2);
      expect(
        find.text('Glass changed for now, but could not be saved.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await show();
      expect(
        find.text('Glass changed for now, but could not be saved.'),
        findsOneWidget,
      );
      fail = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(writes.length, 4);
      expect(glassSettings.saveFailed, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getDouble('glass_transparency'),
        .9,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending reduce-glass throw after leaving is caught and retry remains reachable',
    (t) async {
      final pending = Completer<Object?>();
      var first = true;
      platform((c) async {
        if (c.method == 'getAll' || c.method == 'getAllWithParameters') {
          return <String, Object>{};
        }
        if (first) {
          first = false;
          return pending.future;
        }
        return true;
      });
      prefs.lang = 'en';
      await t.pumpWidget(const MaterialApp(home: AppearanceSettingsPage()));
      await t.pumpAndSettle();
      t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
      await t.pump();
      await t.pumpWidget(const SizedBox());
      pending.completeError(PlatformException(code: 'unavailable'));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(glassSettings.reduced, isTrue);
      expect(glassSettings.saveFailed, isTrue);
      await t.pumpWidget(const MaterialApp(home: AppearanceSettingsPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(glassSettings.saveFailed, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('glass_reduced'),
        isTrue,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final language in ['en', 'ne']) {
    testWidgets(
      'glass failure controls remain reachable 320 large text $language',
      (t) async {
        platform((c) async {
          if (c.method == 'getAll' || c.method == 'getAllWithParameters') {
            return <String, Object>{};
          }
          return false;
        });
        prefs.lang = language;
        addTearDown(() => prefs.lang = 'en');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                language == 'en' ? Brightness.light : Brightness.dark,
                fontFamily: 'Roboto',
              ),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(1.8)),
                child: w!,
              ),
              home: const AppearanceSettingsPage(),
            ),
          ),
        );
        final slider = t.widget<Slider>(find.byType(Slider));
        slider.onChanged!(.75);
        slider.onChangeEnd!(.75);
        await t.pumpAndSettle();
        expect(
          find.text(t_('Glass changed for now, but could not be saved.')),
          findsOneWidget,
        );
        final retry = find.text(t_('Try again'));
        await t.ensureVisible(retry);
        await t.pumpAndSettle();
        expect(retry.hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/sj-glass-save-$language.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        final switchControl = find.byType(SwitchListTile);
        await t.ensureVisible(switchControl);
        await t.pumpAndSettle();
        expect(switchControl.hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

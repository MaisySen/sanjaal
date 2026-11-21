import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/appearance_settings_page.dart';

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
  test('theme write rejection does not pretend persistence', () async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll' ||
              call.method == 'getAllWithParameters') {
            return <String, Object>{};
          }
          if (call.method == 'setString') return false;
          throw StateError('Unexpected preference operation');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    SharedPreferences.resetStatic();
    await expectLater(prefs.setMode(ThemeMode.light), throwsStateError);
    expect(prefs.mode, ThemeMode.light);
  });
  for (final throwsError in [false, true]) {
    testWidgets(
      'theme save failure is caught and explicit retry works throws=$throwsError',
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
                if (fail && throwsError) {
                  throw PlatformException(code: 'unavailable');
                }
                return !fail;
              }
              throw StateError('Unexpected preference operation');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        SharedPreferences.resetStatic();
        prefs.lang = 'en';
        prefs.mode = ThemeMode.dark;
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
                throwsError ? Brightness.dark : Brightness.light,
                fontFamily: 'Roboto',
              ),
              builder: (context, w) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.8)),
                child: w!,
              ),
              home: const AppearanceSettingsPage(),
            ),
          ),
        );
        final tap = t
            .widget<ListTile>(find.widgetWithText(ListTile, 'Light'))
            .onTap!;
        tap();
        tap();
        await t.pumpAndSettle();
        expect(writes, 1);
        expect(prefs.mode, ThemeMode.light);
        expect(t.takeException(), isNull);
        expect(
          find.text(
            'Appearance changed for now, but could not be saved. Choose it again to retry.',
          ),
          findsOneWidget,
        );
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/sj-theme-save-${throwsError ? 'dark' : 'light'}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        fail = false;
        await t.tap(find.text('Light'));
        await t.pumpAndSettle();
        expect(writes, 2);
        expect(
          (await SharedPreferences.getInstance()).getString('theme'),
          'light',
        );
        expect(
          find.text(
            'Appearance changed for now, but could not be saved. Choose it again to retry.',
          ),
          findsNothing,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

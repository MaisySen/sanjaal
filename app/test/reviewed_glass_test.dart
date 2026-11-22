import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/main.dart' show buildTheme;
import 'package:sanjaal/auth_page.dart';
import 'package:sanjaal/api.dart';
import 'package:sanjaal/ui.dart' show prefs;
import 'package:sanjaal/glass/glass_action.dart';
import 'package:sanjaal/glass/glass_surface.dart';

void main() {
  setUpAll(() async {
    for (final pair in [
      (
        'Roboto',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      ('NotoDev', 'assets/fonts/NotoSansDevanagari.ttf'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final f = FontLoader(pair.$1)
        ..addFont(
          File(pair.$2).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await f.load();
    }
  });
  for (final lang in ['en', 'ne']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('current auth $lang ${brightness.name} large text', (
        t,
      ) async {
        prefs.lang = lang;
        addTearDown(() => prefs.lang = "en");
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(brightness, fontFamily: 'Roboto'),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
              home: AuthPage(session: Session()),
            ),
          ),
        );
        await t.pumpAndSettle();
        final sign = find.byType(FilledButton);
        await t.ensureVisible(sign);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, key, 'auth-$lang-${brightness.name}-top');
        await t.ensureVisible(find.byType(OutlinedButton));
        await t.pumpAndSettle();
        expect(find.byType(OutlinedButton).hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await capture(t, key, 'auth-$lang-${brightness.name}-social');
      });
    }
  }
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final highContrast in [false, true]) {
      testWidgets('glass states ${brightness.name} high=$highContrast', (
        t,
      ) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        var calls = 0;
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(brightness, fontFamily: 'Roboto'),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  highContrast: highContrast,
                  textScaler: TextScaler.linear(1.8),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 30),
                      GlassAction(
                        label: 'Continue with Google',
                        onPressed: () => calls++,
                      ),
                      const SizedBox(height: 20),
                      const GlassAction(label: 'Add coins', onPressed: null),
                      const SizedBox(height: 20),
                      const GlassAction(
                        label: 'Please confirm your account',
                        onPressed: null,
                        busy: true,
                      ),
                      const SizedBox(height: 20),
                      GlassSurface(
                        child: const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Readable secondary surface'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        expect(t.takeException(), isNull);
        expect(
          t
              .getSize(
                find.widgetWithText(FilledButton, 'Continue with Google'),
              )
              .height,
          greaterThanOrEqualTo(52),
        );
        await t.tap(find.text('Add coins'));
        expect(calls, 0);
        await t.tap(find.text('Continue with Google'));
        expect(calls, 1);
        if (highContrast) expect(find.byType(BackdropFilter), findsNothing);
        await capture(t, key, 'states-${brightness.name}-$highContrast');
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory(
      Platform.environment['REVIEW_RENDER_DIR'] ??
          'test/renders/reviewed-glass',
    )..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

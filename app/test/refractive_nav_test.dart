import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/glass/refractive_backdrop.dart';
import 'package:sanjaal/glass/refractive_glass.dart';
import 'package:sanjaal/glass/glass_settings.dart';
import 'package:sanjaal/main.dart' show buildTheme, HomeShell;
import 'package:sanjaal/glass_nav.dart';

import 'pr_matched_screens_test.dart' as fixture;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(() async {
    for (final entry in [
      (
        'Roboto',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        '/tmp/sj-flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final loader = FontLoader(entry.$1)
        ..addFont(
          Future.value(ByteData.sublistView(File(entry.$2).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final (width, scale, mode) in [
    (390.0, 1.0, Brightness.light),
    (320.0, 1.8, Brightness.dark),
  ]) {
    testWidgets(
      'real HomeShell navigation lens obeys preparation flag and accessibility fallback $width $scale ${mode.name}',
      (t) async {
        final prior = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = fixture.FrameVideo();
        addTearDown(() => VideoPlayerPlatform.instance = prior);
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.runAsync(() async {
          final codec = await ui.instantiateImageCodec(
            File('/downloads/sanjaal-highfidelity/mountain.jpg')
                .readAsBytesSync(),
          );
          fixture.frameImage = (await codec.getNextFrame()).image;
        });
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(mode, fontFamily: 'Roboto'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: HomeShell(session: fixture.FixtureSession()),
            ),
          ),
        );
        await flush(t);
        t.widget<GlassNavBar>(find.byType(GlassNavBar)).onSelected(1);
        await flush(t);
        await flush(t);
        await t.pump(const Duration(milliseconds: 500));
        expect(
          find.byType(LensBackdrop),
          refractiveGlassPrepared && ui.ImageFilter.isShaderFilterSupported
              ? findsOneWidget
              : findsNothing,
        );
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/sj-nav-lens-${refractiveGlassPrepared ? 'enabled' : 'disabled'}-${width.toInt()}-$scale-${mode.name}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        if (refractiveGlassPrepared && ui.ImageFilter.isShaderFilterSupported) {
          final shader = t
              .widget<LensBackdrop>(find.byType(LensBackdrop))
              .shader;
          await t.pump(const Duration(seconds: 4));
          await t.pump(const Duration(milliseconds: 200));
          expect(
            identical(
              shader,
              t.widget<LensBackdrop>(find.byType(LensBackdrop)).shader,
            ),
            isTrue,
          );
        }
        await t.runAsync(() => glassSettings.setReduced(true));
        await t.pump();
        expect(find.byType(LensBackdrop), findsNothing);
        await t.runAsync(() => glassSettings.setReduced(false));
        await t.pumpWidget(const SizedBox());
        await flush(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}

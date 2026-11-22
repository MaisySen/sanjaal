import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/glass/refractive_glass.dart';
import 'package:sanjaal/glass/refractive_backdrop.dart';

import 'support/lens_grid.dart' show Grid;

Future<void> settleLoad(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pump();
  await t.pump();
}

Widget scene({
  required bool enabled,
  bool reduced = false,
  bool highContrast = false,
  bool noMotion = false,
  bool rotate = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(
      highContrast: highContrast,
      disableAnimations: noMotion,
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: Grid()),
        Positioned(
          left: 20,
          top: 60,
          width: 300,
          height: 90,
          child: Transform.rotate(
            angle: rotate ? 0.1 : 0,
            child: RefractiveGlass(
              key: const ValueKey('owned'),
              enabled: enabled && !reduced,
              radius: 32,
              fallback: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    ),
  ),
);
void main() {
  testWidgets(
    'disabled surface never instantiates lens and explicit preparation flag owns one shader',
    (t) async {
      await t.pumpWidget(scene(enabled: false));
      await settleLoad(t);
      expect(find.byType(LensBackdrop), findsNothing);
      await t.pumpWidget(scene(enabled: true));
      await settleLoad(t);
      expect(
        find.byType(LensBackdrop),
        refractiveGlassPrepared && ui.ImageFilter.isShaderFilterSupported
            ? findsOneWidget
            : findsNothing,
      );
      if (refractiveGlassPrepared && ui.ImageFilter.isShaderFilterSupported) {
        final shader = t.widget<LensBackdrop>(find.byType(LensBackdrop)).shader;
        await t.pumpWidget(scene(enabled: true));
        await t.pump();
        expect(
          identical(
            shader,
            t.widget<LensBackdrop>(find.byType(LensBackdrop)).shader,
          ),
          isTrue,
        );
      }
      await t.pumpWidget(const SizedBox());
      await settleLoad(t);
      expect(t.takeException(), isNull);
    },
  );
  for (final mode in ['reduced', 'contrast', 'motion']) {
    testWidgets('$mode bypasses lens before and after loading', (t) async {
      await t.pumpWidget(scene(enabled: true));
      await settleLoad(t);
      await t.pumpWidget(
        scene(
          enabled: true,
          reduced: mode == 'reduced',
          highContrast: mode == 'contrast',
          noMotion: mode == 'motion',
        ),
      );
      await t.pump();
      expect(find.byType(LensBackdrop), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await settleLoad(t);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'load completing after route disposal does not allocate an attached filter',
    (t) async {
      await t.pumpWidget(scene(enabled: true));
      await t.pumpWidget(const SizedBox());
      await settleLoad(t);
      expect(find.byType(LensBackdrop), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'rotation unsupported by coordinate contract falls back to blur',
    (t) async {
      if (!refractiveGlassPrepared || !ui.ImageFilter.isShaderFilterSupported) {
        markTestSkipped('Needs Impeller');
        return;
      }
      await t.pumpWidget(scene(enabled: true, rotate: true));
      await settleLoad(t);
      final render = t.renderObject<RenderLensBackdrop>(
        find.byType(LensBackdrop),
      );
      expect(
        render.lastRect,
        isNull,
        reason: 'rotated geometry must not be mislabeled as a supported pill',
      );
      await t.pumpWidget(const SizedBox());
      await settleLoad(t);
      expect(t.takeException(), isNull);
    },
  );
}

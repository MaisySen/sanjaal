import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/glass/refractive_backdrop.dart';

import 'support/lens_grid.dart' show Grid, screenshot;

void main() {
  for (final retained in [false, true]) {
    for (final density in [1.0, 2.0, 3.0]) {
      testWidgets('composition-derived geometry dpr$density retained=$retained', (
        t,
      ) async {
        if (!ui.ImageFilter.isShaderFilterSupported) {
          markTestSkipped('Needs Impeller');
          return;
        }
        t.view.physicalSize = Size(360 * density, 240 * density);
        t.view.devicePixelRatio = density;
        addTearDown(t.view.reset);
        late ui.FragmentProgram program;
        await t.runAsync(() async {
          program = await ui.FragmentProgram.fromAsset(
            'shaders/glass_lens.frag',
          );
        });
        final shader = program.fragmentShader();
        final key = GlobalKey(), filterKey = GlobalKey();
        final shift = ValueNotifier(Offset.zero);
        bool enabled = false;
        Widget scene() => Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: Grid()),
                if (enabled)
                  Positioned(
                    left: 20,
                    top: 60,
                    width: 300,
                    height: 90,
                    child: ValueListenableBuilder<Offset>(
                      valueListenable: shift,
                      child: retained
                          ? RepaintBoundary(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(40),
                                child: LensBackdrop(
                                  key: filterKey,
                                  shader: shader,
                                  fallback: ui.ImageFilter.blur(
                                    sigmaX: 0,
                                    sigmaY: 0,
                                  ),
                                  radius: 40,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            )
                          : null,
                      builder: (_, delta, child) => Transform.translate(
                        offset: delta,
                        child:
                            child ??
                            ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: LensBackdrop(
                                key: filterKey,
                                shader: shader,
                                fallback: ui.ImageFilter.blur(
                                  sigmaX: 0,
                                  sigmaY: 0,
                                ),
                                radius: 40,
                                child: const SizedBox.expand(),
                              ),
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        await t.pumpWidget(scene());
        await t.pump();
        final input = await screenshot(t, key, density);
        enabled = true;
        await t.pumpWidget(scene());
        await t.pump();
        final render =
            filterKey.currentContext!.findRenderObject()! as RenderLensBackdrop;
        debugPrint(
          'FIRST density$density retained=$retained rect=${render.lastRect} paints=${render.paints}',
        );
        final initialPaints = render.paints;
        shift.value = const Offset(13, 29);
        await t.pump();
        debugPrint(
          'MOVED density$density retained=$retained rect=${render.lastRect} paints=${render.paints}',
        );
        if (retained) {
          expect(
            render.paints,
            initialPaints,
            reason: 'movement must update without repaint',
          );
        }
        final image = await screenshot(t, key, density);
        final data = await t.runAsync(
          () async => [
            (await input.toByteData())!,
            (await image.toByteData())!,
          ],
        );
        final a = data![0], b = data[1];
        final width = (360 * density).round();
        int changed(Rect r) {
          var n = 0;
          for (
            var y = (r.top * density).ceil();
            y < (r.bottom * density).floor();
            y++
          ) {
            for (
              var x = (r.left * density).ceil();
              x < (r.right * density).floor();
              x++
            ) {
              final i = (y * width + x) * 4;
              if (a.getUint32(i) != b.getUint32(i)) n++;
            }
          }
          return n;
        }

        final movedTop = changed(const Rect.fromLTRB(110, 90, 250, 98));
        final movedBottom = changed(const Rect.fromLTRB(110, 170, 250, 178));
        debugPrint('MOVED top=$movedTop bottom=$movedBottom');
        await t.runAsync(() async {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/sj-source-lens-geometry-probe-$retained-${density.toInt()}x.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
        expect(movedTop, greaterThan(20));
        expect(movedBottom, greaterThan(20));
        await t.runAsync(() async {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '/tmp/sj-source-lens-geometry-retained-$retained-${density.toInt()}x.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox());
        shift.dispose();
        shader.dispose();
        input.dispose();
        image.dispose();
      });
    }
  }
}

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Grid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += 5) {
      for (var x = 0.0; x < size.width; x += 5) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 5, 5),
          Paint()
            ..color = ((x ~/ 5 + y ~/ 5).isEven
                ? const Color(0xfff5bf37)
                : const Color(0xff254b88)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(Grid old) => false;
}

Future<ui.Image> screenshot(
  WidgetTester t,
  GlobalKey key,
  double density,
) async {
  late ui.Image image;
  await t.runAsync(() async {
    image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: density);
  });
  return image;
}

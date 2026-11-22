import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Default-off composition-aware lens preparation. Not device accepted.
class LensBackdrop extends SingleChildRenderObjectWidget {
  const LensBackdrop({
    super.key,
    required this.shader,
    required this.fallback,
    required super.child,
    this.radius = 32,
    this.strength = 4,
  });
  final ui.FragmentShader shader;
  final double radius, strength;
  final ui.ImageFilter fallback;
  @override
  RenderLensBackdrop createRenderObject(BuildContext context) =>
      RenderLensBackdrop(
        shader: shader,
        fallback: fallback,
        radius: radius,
        strength: strength,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderLensBackdrop renderObject,
  ) => renderObject.update(
    shader: shader,
    fallback: fallback,
    radius: radius,
    strength: strength,
  );
}

class RenderLensBackdrop extends RenderProxyBox {
  RenderLensBackdrop({
    required this._shader,
    required this._fallback,
    required this._radius,
    required this._strength,
  });
  ui.FragmentShader _shader;
  ui.ImageFilter _fallback;
  double _radius, _strength;
  int paints = 0;
  Rect? get lastRect => layer?.lastRect;
  @override
  bool get alwaysNeedsCompositing => child != null;
  @override
  LensLayer? get layer => super.layer as LensLayer?;
  void update({
    required ui.FragmentShader shader,
    required ui.ImageFilter fallback,
    required double radius,
    required double strength,
  }) {
    if (identical(_shader, shader) &&
        _fallback == fallback &&
        _radius == radius &&
        _strength == strength) {
      return;
    }
    _shader = shader;
    _fallback = fallback;
    _radius = radius;
    _strength = strength;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    layer ??= LensLayer();
    layer!
      ..shader = _shader
      ..bounds = (offset & size)
      ..fallback = _fallback
      ..radius = _radius
      ..strength = _strength;
    context.pushLayer(layer!, super.paint, offset);
  }
}

class LensLayer extends ContainerLayer {
  late ui.FragmentShader shader;
  Rect bounds = Rect.zero;
  Rect? lastRect;
  ui.ImageFilter fallback = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12);
  double radius = 32, strength = 4;
  int compositions = 0;
  @override
  bool get alwaysNeedsAddToScene => true;
  @override
  void addToScene(ui.SceneBuilder builder) {
    compositions++;
    final chain = <Layer>[];
    Layer? node = this;
    while (node != null) {
      chain.add(node);
      node = node.parent;
    }
    final matrix = Matrix4.identity();
    for (var i = chain.length - 1; i > 0; i--) {
      (chain[i] as ContainerLayer).applyTransform(chain[i - 1], matrix);
    }
    final m = matrix.storage;
    final supported =
        m.every((v) => v.isFinite) &&
        m[0] > 0 &&
        m[5] > 0 &&
        (m[0] - m[5]).abs() < 0.00001 &&
        [
          m[1],
          m[2],
          m[3],
          m[4],
          m[6],
          m[7],
          m[8],
          m[9],
          m[11],
        ].every((v) => v.abs() < 0.00001) &&
        (m[15] - 1).abs() < 0.00001;
    if (!supported) {
      lastRect = null;
      engineLayer = builder.pushBackdropFilter(
        fallback,
        oldLayer: engineLayer as ui.BackdropFilterEngineLayer?,
      );
      addChildrenToScene(builder);
      builder.pop();
      return;
    }
    final logical = MatrixUtils.transformRect(matrix, bounds);
    final rect = logical;
    final scale = matrix.getMaxScaleOnAxis();
    lastRect = rect;
    for (final item in [
      (2, rect.left),
      (3, rect.top),
      (4, rect.right),
      (5, rect.bottom),
      (6, radius * scale),
      (7, strength * scale),
      (8, 18 * scale),
    ]) {
      shader.setFloat(item.$1, item.$2);
    }
    engineLayer = builder.pushBackdropFilter(
      ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(shader),
        inner: fallback,
      ),
      oldLayer: engineLayer as ui.BackdropFilterEngineLayer?,
    );
    addChildrenToScene(builder);
    builder.pop();
  }
}

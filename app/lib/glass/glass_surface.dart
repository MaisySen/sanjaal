import 'dart:ui';
import 'glass_settings.dart';
import 'refractive_glass.dart';

import 'package:material_ui/material_ui.dart';

/// Reviewed material port from PR1. Tint and optical highlights are separate
/// paint layers. Opaque controls can use the same shape without blur.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.tint,
    this.opacity,
    this.minOpacity,
    this.blur = 12,
    this.opaque = false,
    this.refractive = false,
  });
  final Widget child;
  final double radius, blur;
  final double? opacity, minOpacity;
  final Color? tint;
  final bool opaque, refractive;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: glassSettings, builder: (context, _) {
    final scheme = Theme.of(context).colorScheme;
    final reduced =
        opaque || glassSettings.reduced ||
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final shape = BorderRadius.circular(radius);
    final base = tint ?? scheme.surface;
    final floor = minOpacity ?? (scheme.brightness == Brightness.light ? .55 : .70);
    final effectiveOpacity = (opacity ?? floor + (.92 - floor) * glassSettings.transparency).clamp(floor, 1.0);
    return ClipRRect(
      borderRadius: shape,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: reduced
                ? ColoredBox(color: base)
                : RefractiveGlass(
                    enabled: refractive,
                    radius: radius,
                    fallback: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: ColoredBox(
                      color: base.withValues(alpha: effectiveOpacity),
                    ),
                  ),
          ),
          if (!reduced)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: scheme.brightness == Brightness.light ? .10 : .04),
                        Colors.transparent,
                        Colors.black.withValues(alpha: scheme.brightness == Brightness.light ? .05 : 0),
                      ],
                      stops: const [0, .35, 1],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: shape,
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
            ),
          ),
          if (!reduced)
            Positioned(top: 0, left: radius * .5, right: radius * .5, height: 1,
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.white.withValues(alpha: .7), Colors.transparent]))))),
          Theme(data: Theme.of(context).copyWith(colorScheme: scheme.copyWith(onSurfaceVariant: scheme.onSurface)),
            child: DefaultTextStyle.merge(style: TextStyle(color: scheme.onSurface), child: IconTheme.merge(data: IconThemeData(color: scheme.onSurface), child: child))),
        ],
      ),
    );
  });
}

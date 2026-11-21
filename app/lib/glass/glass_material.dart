import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'glass_settings.dart';
import 'glass_tokens.dart';

/// The Liquid Glass surface. One recipe, used by every glass component.
///
/// How it is built, top to bottom:
///   1. A soft shadow under the whole shape, so floating glass lifts off
///      the paper behind it.
///   2. A ClipRRect with one consistent radius from GlassTokens.
///   3. A BackdropFilter with ImageFilter.blur, which blurs the content
///      behind the glass instead of just tinting over it.
///   4. A tinted fill: the brightness tint at the effective opacity. The
///      opacity comes from the Liquid Glass slider by default, and never
///      drops below the contrast floor in GlassTokens, so text over glass
///      stays legible.
///   5. A vertical light falloff: brighter at the top, slightly darker at
///      the bottom, which gives the surface depth.
///   6. A 1px bright top highlight, the specular edge iOS 27 adds.
///   7. A 1px darkened edge around the whole shape, the iOS 27 rim that
///      separates glass from what is behind it.
///   8. The child.
///
/// Reduce Transparency fallback: when the user turns on Reduce glass in
/// Settings, or when the platform reports Increase Contrast through
/// MediaQuery.highContrast, the blur, the gradients and the shadow all go
/// away and the surface becomes a solid card colour with a plain outline.
/// Flutter exposes no Reduce Transparency media query, so the in-app
/// switch in GlassSettings is the Reduce Transparency mechanism; see
/// glass_settings.dart.
class GlassMaterial extends StatelessWidget {
  const GlassMaterial({
    super.key,
    required this.child,
    this.tint,
    this.blur = GlassTokens.blurRegular,
    this.opacity,
    this.radius = GlassTokens.radiusCard,
    this.borderRadius,
    this.shadow = true,
  });

  final Widget child;

  /// Tint colour. Defaults to the brightness tint from GlassTokens.
  final Color? tint;

  /// Blur amount in logical pixels. Use the GlassTokens blur scale.
  final double blur;

  /// Tint opacity. When null, the Liquid Glass slider drives it. When set,
  /// it is clamped up to the contrast floor for the current brightness, so
  /// a caller can never make glass so clear that text over it fails 4.5:1.
  final double? opacity;

  /// Corner radius. One value for the whole shape. Ignored when
  /// [borderRadius] is set, for example a sheet that rounds only the top.
  final double radius;

  /// Full corner shape. When set, it replaces [radius].
  final BorderRadiusGeometry? borderRadius;

  /// Whether to draw the soft shadow under floating glass.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: glassSettings,
      builder: (context, _) {
        final brightness = Theme.of(context).brightness;
        final scheme = Theme.of(context).colorScheme;
        final reduced = glassSettings.reduceGlass || MediaQuery.highContrastOf(context);
        final baseTint = tint ?? GlassTokens.tintFor(brightness);
        final floor = brightness == Brightness.light ? GlassTokens.opacityFloorLight : GlassTokens.opacityFloorDark;
        final effectiveOpacity = (opacity ?? GlassTokens.opacityFor(glassSettings.transparency, brightness)).clamp(floor, 1.0);
        final shape = borderRadius ?? BorderRadius.circular(radius);

        if (reduced) {
          return Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: shape,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: child,
          );
        }

        final edge = GlassTokens.edgeFor(brightness);
        final highlight = GlassTokens.highlightFor(brightness);
        return Container(
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: shadow
                ? [BoxShadow(color: GlassTokens.shadowFor(brightness), blurRadius: 24, offset: const Offset(0, 8))]
                : null,
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Container(color: Colors.transparent),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: baseTint.withValues(alpha: effectiveOpacity),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: brightness == Brightness.light ? 0.10 : 0.16),
                        Colors.white.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: brightness == Brightness.light ? 0.05 : 0.0),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                    border: Border.all(color: edge, width: 1),
                    borderRadius: shape,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: radius * 0.5,
                  right: radius * 0.5,
                  height: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [highlight.withValues(alpha: 0.0), highlight, highlight.withValues(alpha: 0.0)],
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}

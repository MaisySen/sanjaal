import 'package:material_ui/material_ui.dart';
import '../ui.dart';
import 'glass_material.dart';
import 'glass_tokens.dart';

/// A glass button. Two variants, one accent pair, nothing else.
///
/// Primary is crimson glass: the Nepal crimson tint at high opacity over
/// the blur, white label. Secondary is clear glass: the brightness tint,
/// on-surface label. Both are 44px minimum height with a press ripple
/// inside the glass.
///
/// The radius is 8px from GlassTokens, benchmarked: Instagram buttons are
/// 8px, TikTok buttons 4px. A 16px button radius is the generic template
/// look. The label is 14px semibold, the Instagram button size.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.label, required this.onPressed, this.primary = true, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor = primary ? Colors.white : scheme.onSurface;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: labelColor), const SizedBox(width: 8)],
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor)),
        ],
      ),
    );
    final glass = GlassMaterial(
      radius: GlassTokens.radiusButton,
      blur: GlassTokens.blurLight,
      tint: primary ? brandRed : null,
      opacity: primary ? 0.88 : null,
      child: content,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GlassTokens.radiusButton),
        child: glass,
      ),
    );
  }
}

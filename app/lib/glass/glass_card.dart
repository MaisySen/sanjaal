import 'package:material_ui/material_ui.dart';
import 'glass_material.dart';
import 'glass_tokens.dart';

/// A glass content card. Two shapes, and the shape is chosen by what the
/// content is, not by habit.
///
/// The default is a media or wallet card: 20px radius, regular blur, 16px
/// padding. That is for things that are cards, like a balance card or a
/// gift card.
///
/// GlassCard.flush is the feed row: full bleed, no radius, no padding, a
/// hairline divider at the bottom. That is the Instagram rule. Feed posts,
/// DM rows and settings rows are full bleed rows, not boxes. Putting a post
/// inside a padded rounded box with a shadow is the single most generic
/// pattern in social apps, and it is what makes a feed look like a starter
/// template. Phase 2 applies flush to post cards, DM rows and wallet rows.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  const GlassCard.flush({super.key, required this.child, this.onTap}) : padding = EdgeInsets.zero;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  bool get _flush => padding == EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget card;
    if (_flush) {
      card = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      );
    } else {
      card = GlassMaterial(
        radius: GlassTokens.radiusCard,
        blur: GlassTokens.blurRegular,
        child: Padding(padding: padding, child: child),
      );
    }
    if (onTap == null) return card;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: _flush ? null : BorderRadius.circular(GlassTokens.radiusCard),
        child: card,
      ),
    );
  }
}

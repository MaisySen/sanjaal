import 'package:material_ui/material_ui.dart';
import 'glass_material.dart';
import 'glass_tokens.dart';

/// A glass modal sheet. 28px top radius, a drag handle, heavy blur so the
/// sheet stays legible over busy content. Use showGlassSheet instead of
/// showModalBottomSheet wherever a sheet opens in phase 2 and later.
///
/// heightFraction pins the sheet to a share of the viewport. TikTok
/// comments open at 60 percent of the viewport, so the comments sheet in
/// phase 3 passes 0.6. Leave it null and the sheet sizes to its content.
Future<T?> showGlassSheet<T>(BuildContext context, {required WidgetBuilder builder, double? heightFraction}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) {
      final sheet = GlassMaterial(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusSheet)),
        blur: GlassTokens.blurHeavy,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              builder(context),
            ],
          ),
        ),
      );
      if (heightFraction == null) return sheet;
      return SizedBox(height: MediaQuery.of(context).size.height * heightFraction, child: sheet);
    },
  );
}

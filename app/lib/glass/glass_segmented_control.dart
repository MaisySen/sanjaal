import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../ui.dart';
import 'glass_tokens.dart';

/// The feed switch: For you / Following, TikTok style.
///
/// This is deliberately not a pill segmented control. TikTok's top switch
/// is two text labels with a short underline bar under the active one, and
/// that is what the eye expects in a social feed. A glass pill here is the
/// generic pattern: it looks like a settings control, not a feed switch.
/// So this control is transparent: 16px labels, semibold when active,
/// secondary colour when not, and a 28px wide, 3px tall crimson underline
/// bar that slides between the labels in 200ms. Tapping gives a light
/// selection haptic, the same as the tab bar.
///
/// Implements PreferredSizeWidget so it can sit in a GlassAppBar bottom
/// slot. The glass behind it comes from the app bar itself.
class GlassSegmentedControl extends StatelessWidget implements PreferredSizeWidget {
  const GlassSegmentedControl({super.key, required this.labels, required this.selectedIndex, required this.onSelected});
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(i);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: i == selectedIndex ? FontWeight.w700 : FontWeight.w500,
                        color: i == selectedIndex ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: GlassMotion.segmentSlide,
                      curve: GlassMotion.spring,
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == selectedIndex ? brandRed : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

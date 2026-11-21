import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../ui.dart';
import 'glass_material.dart';
import 'glass_tokens.dart';

/// One destination in the floating tab bar.
class GlassTabDestination {
  const GlassTabDestination({required this.label, required this.icon, required this.selectedIcon, this.badgeCount = 0});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badgeCount;
}

/// The floating tab bar, iOS 27 style. A detached glass pill that floats
/// over the content instead of sitting on the bottom edge, with the same
/// five destinations, the same labels and the same unread badge as the
/// Material NavigationBar it replaces.
///
/// The inside of the pill is benchmarked against TikTok and Instagram, not
/// against Material: 24px icons, 10pt labels, a 2px icon to label gap, the
/// active icon filled, and a light selection haptic on every tap. TikTok
/// and Instagram both run 10pt tab labels; 11pt is what makes a tab bar
/// look like a starter template. The active tab gets a filled glass
/// capsule: a crimson tinted pill behind the icon and label. Search is
/// re-integrated into the bar, as in iOS 27: a circular glass search button
/// sits at the end of the pill and opens the search page. It is an action,
/// not a sixth tab, so the five tab structure does not change.
///
/// The parent positions this widget, floating, over the body: left and
/// right 16, bottom 12 plus the bottom safe area. Content scrolls under it.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.onSearch,
  });

  final List<GlassTabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return GlassMaterial(
      radius: GlassTokens.radiusPill,
      blur: GlassTokens.blurRegular,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _TabItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
            if (onSearch != null) ...[
              const SizedBox(width: 2),
              _SearchButton(onSearch: onSearch!),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.destination, required this.selected, required this.onTap});
  final GlassTabDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(selected ? destination.selectedIcon : destination.icon, size: 24, color: color),
            if (destination.badgeCount > 0)
              Positioned(
                right: -8,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: brandRed, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${destination.badgeCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          destination.label,
          style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
        ),
      ],
    );
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: GlassMotion.tabSwitch,
        curve: GlassMotion.spring,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassTokens.radiusPill),
        ),
        child: content,
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onSearch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

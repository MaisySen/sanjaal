import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'ph.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.selectedIcon, {this.badge = 0});
  final String label;
  final String icon;
  final String selectedIcon;
  final int badge;
}

/// Floating bar. Content scrolls under it (the Scaffold uses extendBody), the bar blurs
/// what is behind it. With Reduce Transparency on, it falls back to a solid surface.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.items, required this.index, required this.onSelected});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final reduce = MediaQuery.of(context).highContrast;
    final fill = dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.72);
    final edge = dark ? Colors.white.withValues(alpha: 0.24) : Colors.black.withValues(alpha: 0.10);
    final bar = Container(
      height: 64,
      decoration: BoxDecoration(
        color: reduce ? scheme.surfaceContainerHigh : fill,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: edge, width: 1),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(child: _Item(item: items[i], selected: i == index, onTap: () => onSelected(i))),
      ]),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: reduce ? bar : BackdropFilter(filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: bar),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.82);
    Widget icon = PhIcon(selected ? item.selectedIcon : item.icon, size: 26, color: color);
    if (item.badge > 0) {
      icon = Badge(label: Text(item.badge > 99 ? '99+' : '${item.badge}'), child: icon);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? scheme.onSurface.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(27),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              const SizedBox(height: 2),
              Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'ph.dart';
import 'ui.dart' show t_;
import 'glass/glass_surface.dart';
import 'glass/glass_settings.dart';

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
  const GlassNavBar({super.key, required this.items, required this.index, required this.onSelected, this.compact = false, this.immersive = false, this.onTouch, this.onSearch});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final bool compact, immersive;
  final VoidCallback? onTouch;
  final VoidCallback? onSearch;
  static double contentInset(BuildContext context) => (MediaQuery.textScalerOf(context).scale(14) > 20 ? 140 : 88) + MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: glassSettings, builder: (context, _) {
    final parentTheme = Theme.of(context);
    final scheme = immersive ? parentTheme.colorScheme.copyWith(brightness: Brightness.dark, primary: const Color(0xFFFF758A), surface: const Color(0xFF101114), onSurface: Colors.white, onSurfaceVariant: Colors.white, surfaceContainerHighest: Colors.white, outlineVariant: Colors.white24) : parentTheme.colorScheme;
    final edge = scheme.outlineVariant;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final largeBadge = largeText && items.any((item) => item.badge > 0);
    final collapsed = compact && !MediaQuery.of(context).accessibleNavigation && MediaQuery.textScalerOf(context).scale(14) < 20;
    final bar = AnimatedContainer(
      duration: largeText || MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
      height: collapsed ? 52 : (largeBadge ? 116 : largeText ? 92 : 56),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: edge, width: 1),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: SizedBox(height: largeBadge ? 76 : largeText ? 52 : (collapsed ? 50 : 54), child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(child: _Item(item: items[i], compact: true, selected: i == index, onTap: () => onSelected(i))),
          if (onSearch != null) IconButton(tooltip: t_('Search'), onPressed: onSearch, icon: PhIcon('magnifying-glass', size: 22, color: scheme.onSurfaceVariant), style: IconButton.styleFrom(minimumSize: const Size(44,44), backgroundColor: scheme.onSurface.withValues(alpha: .08))),
        ]))),
        if (largeText) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(items[index].label, maxLines: 1, style: TextStyle(fontSize: 12, height: 1.1, color: scheme.primary, fontWeight: FontWeight.w700))),
      ])),
    );
    return Theme(data: parentTheme.copyWith(colorScheme: scheme), child: SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Listener(
        onPointerDown: (_) => onTouch?.call(),
        child: Padding(
        padding: EdgeInsets.fromLTRB(collapsed ? 26 : 14, 0, collapsed ? 26 : 14, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: GlassSurface(refractive: true, radius: 32, blur: 12, minOpacity: .10, opacity: .22 + .26 * glassSettings.transparency, child: bar),
        ),
      )),
    ));
  });
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.selected, required this.onTap, required this.compact});
  final bool compact;
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurface;
    Widget icon = Stack(children: [
      Transform.translate(offset: const Offset(0, 1), child: Opacity(opacity: .45, child: PhIcon(selected ? item.selectedIcon : item.icon, size: 26, color: scheme.brightness == Brightness.light ? Colors.white : Colors.black))),
      PhIcon(selected ? item.selectedIcon : item.icon, size: 26, color: color),
    ]);
    if (item.badge > 0) {
      final label = Text(item.badge > 99 ? '99+' : '${item.badge}');
      icon = MediaQuery.textScalerOf(context).scale(14) > 20
          ? Stack(clipBehavior: Clip.none, children: [icon,
              Positioned(top: -30, left: -30, right: -30,
                child: Center(child: Badge(label: label))),
            ])
          : Badge(label: label, child: icon);
    }
    return Tooltip(message: item.label, child: Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? scheme.onSurface.withValues(alpha: .14) : Colors.transparent,
              borderRadius: BorderRadius.circular(27),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              if (!compact) const SizedBox(height: 2),
              if (!compact) Text(item.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.1, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
            ]),
          ),
        ),
      ),
    ));
  }
}

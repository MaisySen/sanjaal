import 'package:material_ui/material_ui.dart';
import 'glass_material.dart';
import 'glass_tokens.dart';

/// The glass app bar, iOS 27 style. A full width glass surface at the top
/// of a tab. Content scrolls under it and the blur keeps it legible.
///
/// Large title behaviour: when the content is at the top, the bar is tall
/// and shows the large title. When the content has scrolled under it, the
/// parent passes collapsed true and the bar becomes the uniform toolbar:
/// same glass surface, same actions, compact title. That is the iOS 27
/// uniform toolbar that appears when content scrolls under floating bars.
/// The collapse itself is a height change in this phase; animating the
/// height is a phase 6 motion item.
///
/// Implements PreferredSizeWidget so it can replace an AppBar in a Scaffold.
/// The bottom slot takes a PreferredSizeWidget, normally a
/// GlassSegmentedControl.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.largeTitle,
    this.actions = const [],
    this.bottom,
    this.collapsed = false,
  });

  /// Compact title, shown when collapsed.
  final Widget title;

  /// Large title, shown when expanded. Falls back to [title].
  final Widget? largeTitle;

  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  /// True when content has scrolled under the bar.
  final bool collapsed;

  static const double _compactHeight = 56;
  static const double _largeHeight = 100;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight((collapsed ? _compactHeight : _largeHeight) + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = collapsed ? _compactHeight : _largeHeight;
    return GlassMaterial(
      radius: 0,
      blur: GlassTokens.blurRegular,
      shadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: barHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: collapsed ? title : (largeTitle ?? title)),
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
                ],
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}

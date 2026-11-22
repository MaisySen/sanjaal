import 'package:material_ui/material_ui.dart';
import 'glass_surface.dart';

/// PR1's shared glass header, retaining AppBar navigation and accessibility.
class ReviewedAppBar extends AppBar {
  ReviewedAppBar({
    super.key,
    super.title,
    super.leading,
    super.actions,
    super.bottom,
    super.centerTitle,
    super.toolbarHeight,
    super.automaticallyImplyLeading,
    super.backgroundColor,
    super.foregroundColor,
    super.elevation,
    super.titleSpacing,
  }) : super(flexibleSpace: const GlassSurface(radius: 0, blur: 20, child: SizedBox.expand()));
}

/// Fixed short underline from PR1. TabBar still owns focus, swipe and semantics.
class PRSegmentIndicator extends Decoration {
  const PRSegmentIndicator(this.color);
  final Color color;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _SegmentPainter(color);
}
class _SegmentPainter extends BoxPainter {
  _SegmentPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final size = config.size;
    if (size == null) return;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(offset.dx + (size.width - 28) / 2, offset.dy + size.height - 4, 28, 3), const Radius.circular(999)), Paint()..color = color);
  }
}

import 'package:material_ui/material_ui.dart';
import 'glass_surface.dart';

/// Visual wrapper only. Keeps each caller's dismissal, drag and scroll policy.
Future<T?> showReviewedGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .4),
  builder: (context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: GlassSurface(radius: 0, blur: 32, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (showDragHandle == true) ...[
        const SizedBox(height: 8),
        Container(width: 36, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .4), borderRadius: BorderRadius.circular(999))),
        const SizedBox(height: 8),
      ],
      Flexible(child: Builder(builder: builder)),
    ])),
  ),
);

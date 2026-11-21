import 'package:material_ui/material_ui.dart';

import '../ui.dart' show brandRed;
import 'glass_surface.dart';

/// Shared action treatment. Uses real button semantics, wrapping labels and
/// explicit disabled/busy states. No authentication or network logic lives here.
class GlassAction extends StatelessWidget {
  const GlassAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.busy = false,
    this.compact = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, busy, compact;
  final Widget? icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !busy;
    final background = !enabled
        ? scheme.surfaceContainerHighest
        : primary
        ? brandRed
        : scheme.surface;
    final foreground = !enabled
        ? scheme.onSurfaceVariant
        : primary
        ? Colors.white
        : scheme.onSurface;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          const SizedBox(width: 10),
        ],
        if (!busy && icon != null) ...[icon!, const SizedBox(width: 8)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(foreground),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: WidgetStatePropertyAll(Size(44, compact ? 44 : 52)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20,
          vertical: compact ? 10 : 14,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      side: const WidgetStatePropertyAll(BorderSide.none),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      ),
    );
    return GlassSurface(
      radius: 8,
      tint: background,
      opaque: primary || !enabled,
      child: primary
          ? FilledButton(
              onPressed: enabled ? onPressed : null,
              style: style,
              child: content,
            )
          : OutlinedButton(
              onPressed: enabled ? onPressed : null,
              style: style,
              child: content,
            ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'ui.dart';

/// Bounded, scrollable recovery notice so large text and the IME cannot hide
/// the composer or force a RenderFlex overflow. New intent is never a send.
class UploadNotice extends StatelessWidget {
  const UploadNotice({super.key, required this.message, this.retry, this.openOriginal, this.prepareNew, this.newLabel});
  final String message;
  final VoidCallback? retry;
  final VoidCallback? openOriginal;
  final VoidCallback? prepareNew;
  final String? newLabel;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.45),
    child: Material(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: SingleChildScrollView(child: Text(t_(message)))),
        Wrap(spacing: 8, children: [
          if (openOriginal != null) TextButton(onPressed: openOriginal, child: Text(t_('Open original'))),
          if (retry != null) TextButton(onPressed: retry, child: Text(t_('Try again'))),
          if (prepareNew != null) TextButton(onPressed: prepareNew, child: Text(t_(newLabel ?? 'Prepare a new post'))),
        ]),
      ]),
    )),
  );
}

Future<bool> confirmNewUpload(BuildContext context) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(
  scrollable: true,
  title: Text(t_('Start a separate upload?')),
  content: Text(t_('The earlier attempt may already be posted. Check it first to avoid a duplicate. Your current draft will be kept.')),
  actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Cancel'))),
    TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Prepare new upload'))),
  ],
)) ?? false;

import 'package:material_ui/material_ui.dart';
import 'ui.dart' show t_, showInfo;

/// Keeps accidental route-back from discarding an in-memory creator draft.
/// This is not persistent draft storage, and never starts an upload.
class DraftExitGuard extends StatefulWidget {
  const DraftExitGuard({super.key, required this.hasChanges, required this.busy, required this.child, this.busyMessage = 'Your upload is still in progress.', this.title = 'Discard this draft?', this.message = 'Leaving will remove this draft from this screen.', this.keepLabel = 'Keep editing', this.discardLabel = 'Discard'});
  final bool hasChanges;
  final bool busy;
  final Widget child;
  final String busyMessage;
  final String title, message, keepLabel, discardLabel;
  @override
  State<DraftExitGuard> createState() => _DraftExitGuardState();
}

class _DraftExitGuardState extends State<DraftExitGuard> {
  bool asking = false;
  bool discard = false;
  Future<void> confirm() async {
    if (asking) return;
    if (widget.busy) {
      showInfo(context, t_(widget.busyMessage));
      return;
    }
    asking = true;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      scrollable: true,
      title: Text(t_(widget.title)),
      content: Text(t_(widget.message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_(widget.keepLabel))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_(widget.discardLabel))),
      ],
    ));
    asking = false;
    if (yes == true && mounted) {
      setState(() => discard = true);
      // Let PopScope publish the updated disposition before asking to leave.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: discard || (!widget.hasChanges && !widget.busy),
    onPopInvokedWithResult: (didPop, _) { if (!didPop) confirm(); },
    child: widget.child,
  );
}

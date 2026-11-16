import 'package:material_ui/material_ui.dart';
import 'ui.dart' show t_, showInfo;

/// Keeps accidental route-back from discarding an in-memory creator draft.
/// This is not persistent draft storage, and never starts an upload.
class DraftExitGuard extends StatefulWidget {
  const DraftExitGuard({super.key, required this.hasChanges, required this.busy, required this.child});
  final bool hasChanges;
  final bool busy;
  final Widget child;
  @override
  State<DraftExitGuard> createState() => _DraftExitGuardState();
}

class _DraftExitGuardState extends State<DraftExitGuard> {
  bool asking = false;
  bool discard = false;
  Future<void> confirm() async {
    if (asking) return;
    if (widget.busy) {
      showInfo(context, t_('Your upload is still in progress.'));
      return;
    }
    asking = true;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(t_('Discard this draft?')),
      content: Text(t_('Leaving will remove this draft from this screen.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t_('Keep editing'))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t_('Discard'))),
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

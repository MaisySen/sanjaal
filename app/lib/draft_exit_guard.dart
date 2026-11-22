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
  Route<dynamic>? _dialog;
  NavigatorState? _dialogNavigator;

  static void _retireDialog(Route<dynamic> dialog, NavigatorState navigator) {
    // Remove this exact dialog after build, never whichever route covers it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && dialog.isActive && identical(dialog.navigator, navigator)) {
        navigator.removeRoute(dialog);
      }
    });
  }

  @override
  void dispose() {
    final dialog = _dialog, navigator = _dialogNavigator;
    if (dialog != null && navigator != null) _retireDialog(dialog, navigator);
    super.dispose();
  }

  Future<void> confirm() async {
    if (!mounted || asking) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    if (widget.busy) {
      showInfo(context, t_(widget.busyMessage));
      return;
    }
    final navigator = Navigator.of(context);
    final configuration = widget;
    asking = true;
    var answered = false;
    try {
      final yes = await showDialog<bool>(context: context, builder: (c) {
        final dialog = ModalRoute.of(c)!;
        final dialogNavigator = Navigator.of(c);
        if (mounted) {
          _dialog = dialog;
          _dialogNavigator = dialogNavigator;
        } else {
          _retireDialog(dialog, dialogNavigator);
        }
        void finish(bool value) {
          if (!mounted || answered || !c.mounted || !dialog.isCurrent) return;
          answered = true;
          dialogNavigator.pop(value);
        }
        return AlertDialog(
          scrollable: true,
          title: Text(t_(configuration.title)),
          content: Text(t_(configuration.message)),
          actions: [
            TextButton(onPressed: () => finish(false), child: Text(t_(configuration.keepLabel))),
            TextButton(onPressed: () => finish(true), child: Text(t_(configuration.discardLabel))),
          ],
        );
      });
      _dialog = null;
      _dialogNavigator = null;
      if (yes != true || !mounted || !route.isCurrent) return;
      if (widget.busy) {
        showInfo(context, t_(widget.busyMessage));
        return;
      }
      setState(() => discard = true);
      // Let PopScope publish the disposition, then recheck the same route.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!route.isCurrent || widget.busy) {
        setState(() => discard = false);
        if (route.isCurrent && widget.busy) showInfo(context, t_(widget.busyMessage));
        return;
      }
      navigator.pop();
    } finally {
      asking = false;
      _dialog = null;
      _dialogNavigator = null;
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.busy && (discard || !widget.hasChanges),
    onPopInvokedWithResult: (didPop, _) { if (!didPop) confirm(); },
    child: widget.child,
  );
}

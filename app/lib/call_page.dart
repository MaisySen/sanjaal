import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'call_controller.dart';
import 'call_view.dart';
import 'ui.dart' show t_;

export 'call_view.dart';

/// A presentation of one call. A host-owned controller survives minimisation.
class CallPage extends StatefulWidget {
  const CallPage({
    super.key,
    required this.session,
    required this.conversationId,
    required this.title,
    required this.video,
    this.callId,
    this.controller,
    this.onMinimize,
    this.onEnd,
  });
  final Session session;
  final String conversationId, title;
  final bool video;
  final String? callId;
  final CallController? controller;
  final VoidCallback? onMinimize, onEnd;
  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallController call;
  late final bool ownsCall;
  bool _retired = false;
  @override
  void initState() {
    super.initState();
    ownsCall = widget.controller == null;
    call =
        widget.controller ??
        CallController(
          session: widget.session,
          conversationId: widget.conversationId,
          title: widget.title,
          video: widget.video,
          callId: widget.callId,
        );
    assert(
      identical(call.session, widget.session) &&
          call.conversationId == widget.conversationId,
    );
    call.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _end() {
    if (!mounted ||
        _retired ||
        !call.ownerMatches ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final end = widget.onEnd;
    if (end != null) {
      end();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void didUpdateWidget(covariant CallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        widget.conversationId != oldWidget.conversationId ||
        widget.callId != oldWidget.callId ||
        !identical(widget.controller, oldWidget.controller)) {
      _retired = true;
      call.close(endRemote: false);
    }
  }

  @override
  void dispose() {
    call.removeListener(_changed);
    if (ownsCall) call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired || !call.ownerMatches) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              t_(
                'This screen belongs to another signed-in session. Close it and sign in again to continue.',
              ),
            ),
          ),
        ),
      );
    }
    return PopScope<Object?>(
      canPop: widget.onMinimize == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onMinimize?.call();
      },
      child: CallView(
        title: call.title,
        status: call.presentation.status,
        failed: call.failed,
        video: call.video,
        muted: call.muted,
        camOn: call.camOn,
        tiles: call.connection.tiles,
        selfPreview: call.camOn ? call.connection.selfPreview : null,
        controlsBusy: call.mediaBusy || !call.presentation.mediaAvailable,
        onMute: () => call.changeMedia(camera: false),
        onCamera: () => call.changeMedia(camera: true),
        onMinimize: widget.onMinimize,
        onEnd: _end,
      ),
    );
  }
}

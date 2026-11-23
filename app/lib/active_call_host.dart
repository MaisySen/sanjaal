import 'dart:async';
import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'call_controller.dart';
import 'native_call_coordinator.dart';
import 'native_call_audio_policy.dart';
import 'call_page.dart';
import 'ph.dart';
import 'ui.dart' show t_, showInfo;

typedef CallFactory = CallController Function({
  required Session session,
  required String conversationId,
  required String title,
  required bool video,
  String? callId,
});

class ActiveCallHost extends StatefulWidget {
  const ActiveCallHost({
    super.key,
    required this.session,
    required this.navigatorKey,
    required this.child,
    this.createCall,
  });
  final Session session;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final CallFactory? createCall;
  static ActiveCallHostState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_CallScope>()?.host;
  static bool busy(BuildContext context) => maybeOf(context)?.busy ?? false;
  @override
  State<ActiveCallHost> createState() => ActiveCallHostState();
}

class _CallScope extends InheritedWidget {
  const _CallScope({required this.host, required super.child});
  final ActiveCallHostState host;
  @override
  bool updateShouldNotify(_CallScope oldWidget) => false;
}

class _CallTicket {
  _CallTicket(this.call);
  final CallController call;
  final done = Completer<void>();
  Route<void>? route;
  late VoidCallback listener;
}

class ActiveCallHostState extends State<ActiveCallHost> {
  _CallTicket? _current;
  bool _closing = false, _restartRequired = false;
  bool get busy => _current != null || _closing || _restartRequired;
  bool owns(Session session, String conversationId) =>
      _current != null &&
      identical(_current!.call.session, session) &&
      _current!.call.ownerMatches &&
      _current!.call.conversationId == conversationId;
  bool get _minimized => _current != null && _current!.route == null;

  Future<void> open(
    BuildContext source, {
    required Session session,
    required String conversationId,
    required String title,
    required bool video,
    String? callId,
  }) {
    if (!mounted ||
        !source.mounted ||
        ModalRoute.of(source)?.isCurrent == false ||
        !identical(session, widget.session) ||
        session.user == null) {
      return Future.value();
    }
    if (_restartRequired || _closing) {
      showInfo(
        source,
        t_(
          _restartRequired
              ? 'Call cleanup could not be confirmed. Force close Sanjaal, then reopen it before starting another call.'
              : 'Ending the previous call. Please wait.',
        ),
      );
      return Future.value();
    }
    final existing = _current;
    if (existing != null) {
      if (existing.call.ownerMatches &&
          existing.call.conversationId == conversationId) {
        _present(existing);
        return existing.done.future;
      }
      showInfo(source, t_('End the current call before starting another.'));
      return Future.value();
    }
    if (conversationId.trim().isEmpty ||
        widget.navigatorKey.currentState == null) {
      return Future.value();
    }
    final factory = widget.createCall;
    final call = factory == null
        ? CallController(
            session: session,
            conversationId: conversationId,
            title: title,
            video: video,
            callId: callId,
          )
        : factory(
            session: session,
            conversationId: conversationId,
            title: title,
            video: video,
            callId: callId,
          );
    final ticket = _CallTicket(call);
    ticket.listener = () {
      if (!mounted || !identical(_current, ticket)) return;
      if (!call.ownerMatches || call.closed) {
        unawaited(_finish(ticket, endRemote: call.ownerMatches));
      } else {
        setState(() {});
      }
    };
    call.addListener(ticket.listener);
    setState(() => _current = ticket);
    _present(ticket);
    return ticket.done.future;
  }

  /// Reserve the same single media slot used by foreground calls, without
  /// navigating or enabling camera from a system/background answer.
  CallController? reserveNative(NativeCallEvent event) {
    if (!mounted || busy || widget.session.nativeCallLease != event.lease ||
        widget.session.user?['public_id'] != event.owner) { return null; }
    final call = CallController(session: widget.session,
      conversationId: event.conversation, title: 'Sanjaal call', video: event.video,
      callId: event.call, startCamera: false,
      beforeConnect: NativeCallAudioPolicy.prepare,
      beforeRelease: () async {
        final retired=await const MethodChannel('au.fintex.sanjaal/incoming-calls').invokeMethod<bool>('complete', {
          'call':event.call,'generation':event.lease,'connected':false,
        });
        // A false result can mean native End already retired this exact call.
        // Audio policy still independently verifies system ownership release.
        if(retired==null) throw StateError('Native call retirement is unavailable');
      }, afterRelease: NativeCallAudioPolicy.release);
    final ticket = _CallTicket(call);
    ticket.listener = () {
      if (!mounted || !identical(_current, ticket)) return;
      if (!call.ownerMatches || call.closed) {
        unawaited(_finish(ticket, endRemote: call.ownerMatches));
      } else {
        setState(() {});
      }
    };
    call.addListener(ticket.listener);
    setState(() => _current = ticket);
    return call;
  }

  Future<void> releaseNative(CallController call) async {
    final ticket = _current;
    if (ticket == null || !identical(ticket.call, call)) return;
    // Authenticated remote actions belong to the native coordinator, never a
    // second implicit End here or one using a replacement login.
    await _finish(ticket, endRemote: false);
  }

  void _present(_CallTicket ticket) {
    if (!mounted ||
        !identical(_current, ticket) ||
        ticket.route != null ||
        !ticket.call.ownerMatches ||
        ticket.call.closed) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    final call = ticket.call;
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CallPage(
        session: call.session,
        conversationId: call.conversationId,
        title: call.title,
        video: call.video,
        controller: call,
        onMinimize: () => _minimize(ticket),
        onEnd: () => unawaited(_finish(ticket)),
      ),
    );
    ticket.route = route;
    try {
      unawaited(
        navigator.push<void>(route).then((_) {
          if (!mounted ||
              !identical(_current, ticket) ||
              !identical(ticket.route, route)) {
            return;
          }
          setState(() => ticket.route = null);
        }),
      );
      setState(() {});
    } catch (_) {
      unawaited(_finish(ticket));
    }
  }

  void _minimize(_CallTicket ticket) {
    final route = ticket.route;
    if (!mounted ||
        !identical(_current, ticket) ||
        route == null ||
        !route.isCurrent ||
        !ticket.call.ownerMatches) {
      return;
    }
    // Remove only this presentation, not whichever route may be above it.
    setState(() => ticket.route = null);
    if (route.isActive) widget.navigatorKey.currentState?.removeRoute(route);
  }

  Future<void> _finish(_CallTicket ticket, {bool endRemote = true}) async {
    if (!mounted || !identical(_current, ticket)) return;
    final route = ticket.route;
    ticket.route = null;
    ticket.call.removeListener(ticket.listener);
    setState(() {
      _current = null;
      _closing = true;
    });
    if (route?.isActive == true) {
      widget.navigatorKey.currentState?.removeRoute(route!);
    }
    var released = false;
    try {
      released = await ticket.call
          .close(endRemote: endRemote)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      /* Quarantine while a late native operation still owns capture. */
    }
    ticket.call.dispose();
    if (!ticket.done.isCompleted) ticket.done.complete();
    if (mounted) {
      setState(() {
        _closing = false;
        _restartRequired = !released;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ActiveCallHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) && _current != null) {
      final ticket = _current!;
      // The old call is closed locally, never with this replacement session.
      unawaited(_finish(ticket, endRemote: false));
    }
  }

  @override
  void dispose() {
    final ticket = _current;
    _current = null;
    if (ticket != null) {
      ticket.call.removeListener(ticket.listener);
      ticket.call.dispose();
      if (!ticket.done.isCompleted) ticket.done.complete();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _current;
    final minimized = _minimized && ticket!.call.ownerMatches;
    return _CallScope(
      host: this,
      child: Column(
        children: [
          if (minimized)
            SafeArea(
              bottom: false,
              child: ActiveCallBanner(
                call: ticket.call,
                onReturn: () => _present(ticket),
                onEnd: () => unawaited(_finish(ticket)),
              ),
            ),
          if (_closing || _restartRequired)
            SafeArea(
              bottom: false,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      t_(
                        _restartRequired
                            ? 'Call cleanup could not be confirmed. Force close Sanjaal, then reopen it before starting another call.'
                            : 'Ending the previous call. Please wait.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: minimized || _closing || _restartRequired
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.child,
                  )
                : widget.child,
          ),
        ],
      ),
    );
  }
}

class ActiveCallBanner extends StatelessWidget {
  const ActiveCallBanner({
    super.key,
    required this.call,
    required this.onReturn,
    required this.onEnd,
  });
  final CallController call;
  final VoidCallback onReturn, onEnd;
  @override
  Widget build(BuildContext context) {
    final ready =
        call.presentation.mediaAvailable && !call.mediaBusy && !call.failed;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight > 280 ? 280 : maxHeight),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('active-call-status-scroll'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        call.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(t_(call.presentation.status)),
                      ),
                      if (ready)
                        Wrap(
                          spacing: 12,
                          children: [
                            Text(
                              t_(
                                call.muted ? 'Microphone off' : 'Microphone on',
                              ),
                            ),
                            if (call.video)
                              Text(t_(call.camOn ? 'Camera on' : 'Camera off')),
                          ],
                        )
                      else
                        Text(
                          t_('Check microphone and camera state in the call.'),
                        ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton.icon(
                    onPressed: onReturn,
                    icon: const PhIcon('arrow-up-right'),
                    label: Text(t_('Return to call')),
                  ),
                  TextButton.icon(
                    onPressed: onEnd,
                    icon: const PhIcon('phone-x-fill'),
                    label: Text(t_('End call')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openCall(
  BuildContext context, {
  required Session session,
  required String conversationId,
  required String title,
  required bool video,
  String? callId,
}) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return Future.value();
  }
  final host = ActiveCallHost.maybeOf(context);
  if (host != null) {
    return host.open(
      context,
      session: session,
      conversationId: conversationId,
      title: title,
      video: video,
      callId: callId,
    );
  }
  // A standalone embedded screen can still own a traditional routed call.
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => CallPage(
        session: session,
        conversationId: conversationId,
        title: title,
        video: video,
        callId: callId,
      ),
    ),
  );
}

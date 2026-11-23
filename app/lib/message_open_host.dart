import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat_pages.dart';
import 'ui.dart';

/// A notification is not authenticated account/route authority. Existing push
/// payloads lack recipient binding, so a tap only offers the current inbox.
abstract class MessageOpenSource {
  bool get supported;
  Stream<void> get opens;
  Future<bool> initialOpen();
}

class MessageOpenHost extends StatefulWidget {
  const MessageOpenHost({
    super.key,
    required this.session,
    required this.navigatorKey,
    required this.source,
    required this.child,
  });
  final Session session;
  final GlobalKey<NavigatorState> navigatorKey;
  final MessageOpenSource source;
  final Widget child;
  @override
  State<MessageOpenHost> createState() => _MessageOpenHostState();
}

class _MessageOpenHostState extends State<MessageOpenHost> {
  StreamSubscription<void>? _subscription;
  late final Session _session;
  late final MessageOpenSource _source;
  int? _pendingGeneration;
  bool _initialChecked = false, _opening = false, _retired = false;
  bool get _ready =>
      !_retired &&
      identical(_session, widget.session) &&
      _session.user != null &&
      !_session.loading &&
      !_session.authenticating &&
      !_session.recoveringAccount &&
      !_session.accountViewNeedsRefresh &&
      !_session.profileSetupPending;
  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _source = widget.source;
    _session.addListener(_changed);
    if (_source.supported) {
      try {
        _subscription = _source.opens.listen(
          (_) => _offer(),
          onError: (Object _) {},
        );
      } catch (_) {
        // An unavailable provider must not prevent opening the normal app.
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(MessageOpenHost old) {
    super.didUpdateWidget(old);
    if (!identical(widget.session, _session) ||
        !identical(widget.source, _source)) {
      _retired = true;
      _pendingGeneration = null;
      unawaited(_subscription?.cancel());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_ready || _pendingGeneration != _session.generation) {
      setState(() => _pendingGeneration = null);
    }
    if (_ready && _source.supported && !_initialChecked) {
      _initialChecked = true;
      final generation = _session.generation;
      unawaited(() async {
        try {
          final opened = await _source.initialOpen();
          if (mounted &&
              _ready &&
              _session.generation == generation &&
              opened) {
            _offer();
          }
        } catch (_) {
          /* Provider absence never blocks the normal app. */
        }
      }());
    }
  }

  void _offer() {
    if (!mounted || !_ready || _opening) return;
    setState(() => _pendingGeneration = _session.generation);
  }

  Future<void> _open(int generation) async {
    if (!mounted ||
        !_ready ||
        _opening ||
        _pendingGeneration != generation ||
        _session.generation != generation) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    setState(() {
      _pendingGeneration = null;
      _opening = true;
    });
    try {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => ChatsPage(session: _session)),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _session.generation;
    return Column(
      children: [
        if (_ready && _pendingGeneration == _session.generation)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.38,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t_(
                            'Message notification opened. Open Chats for the account signed in now.',
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  (_pendingGeneration == generation &&
                                      _session.generation == generation)
                                  ? setState(() => _pendingGeneration = null)
                                  : null,
                              child: Text(t_('Dismiss')),
                            ),
                            TextButton(
                              onPressed: () => _open(generation),
                              child: Text(t_('Open chats')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

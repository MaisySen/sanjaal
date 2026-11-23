import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'chat_pages.dart';
import 'session_bound_state.dart';
import 'ui.dart';

/// A notification is not account/route authority. Legacy payloads offer the
/// current inbox. Versioned recipient-bound targets need an authenticated read.
class MessageOpenIntent {
  const MessageOpenIntent({this.recipient, this.conversation});
  final String? recipient, conversation;
  static MessageOpenIntent? fromData(Map<String, dynamic> data) {
    if (data['type'] != 'message') return null;
    final uuid = RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    );
    if (data['open_version'] == '1' &&
        data['recipient'] is String &&
        data['conversation'] is String &&
        uuid.hasMatch(data['recipient'] as String) &&
        uuid.hasMatch(data['conversation'] as String)) {
      return MessageOpenIntent(
        recipient: (data['recipient'] as String).toLowerCase(),
        conversation: (data['conversation'] as String).toLowerCase(),
      );
    }
    return const MessageOpenIntent();
  }
}

abstract class MessageOpenSource {
  bool get supported;
  Stream<MessageOpenIntent> get opens;
  Future<MessageOpenIntent?> initialOpen();
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
  StreamSubscription<MessageOpenIntent>? _subscription;
  late final Session _session;
  late final MessageOpenSource _source;
  int? _pendingGeneration;
  int _eventRevision = 0;
  MessageOpenIntent? _intent;
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
          (intent) => _offer(intent),
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
      final revision = _eventRevision;
      unawaited(() async {
        try {
          final opened = await _source.initialOpen();
          if (mounted &&
              _ready &&
              _session.generation == generation &&
              _eventRevision == revision &&
              opened != null) {
            _offer(opened);
          }
        } catch (_) {
          /* Provider absence never blocks the normal app. */
        }
      }());
    }
  }

  void _offer(MessageOpenIntent intent) {
    if (!mounted || !_ready || _opening) return;
    ++_eventRevision;
    setState(() {
      _pendingGeneration = _session.generation;
      _intent = intent;
    });
  }

  Future<void> _open(int generation, int revision) async {
    if (!mounted ||
        !_ready ||
        _opening ||
        _eventRevision != revision ||
        _pendingGeneration != generation ||
        _session.generation != generation) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    final intent = _intent;
    final exact =
        intent?.recipient == _session.user?['public_id'] &&
        intent?.conversation != null;
    setState(() {
      _pendingGeneration = null;
      _intent = null;
      _opening = true;
    });
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => exact
              ? NotificationConversationPage(
                  session: _session,
                  conversation: intent!.conversation!,
                )
              : ChatsPage(session: _session),
        ),
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
    final revision = _eventRevision;
    final exact =
        _intent?.recipient == _session.user?['public_id'] &&
        _intent?.conversation != null;
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
                            exact
                                ? 'Message notification opened. Review this conversation in the account signed in now.'
                                : 'Message notification opened. Open Chats for the account signed in now.',
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  (_pendingGeneration == generation &&
                                      _eventRevision == revision &&
                                      _session.generation == generation)
                                  ? setState(() => _pendingGeneration = null)
                                  : null,
                              child: Text(t_('Dismiss')),
                            ),
                            TextButton(
                              onPressed: () => _open(generation, revision),
                              child: Text(
                                t_(exact ? 'Open conversation' : 'Open chats'),
                              ),
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

/// Resolve only on the member's explicit action. Payload labels are never used.
class NotificationConversationPage extends StatefulWidget {
  const NotificationConversationPage({
    super.key,
    required this.session,
    required this.conversation,
  });
  final Session session;
  final String conversation;
  @override
  State<NotificationConversationPage> createState() =>
      _NotificationConversationPageState();
}

class _NotificationConversationPageState
    extends State<NotificationConversationPage>
    with SessionBoundState<NotificationConversationPage> {
  @override
  Session get viewSession => widget.session;
  bool reading = false, gone = false;
  String? error;
  Map<String, dynamic>? conversation;
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void sessionRetired() {
    conversation = null;
    error = null;
  }

  Future<void> _read() async {
    if (!mounted || !sessionActive || reading) return;
    setState(() {
      reading = true;
      error = null;
      gone = false;
    });
    try {
      final result = await widget.session.call(
        'GET',
        '/conversations/${widget.conversation}',
      ) as Map;
      final row = (result['conversation'] as Map).cast<String, dynamic>();
      if (row['public_id'] != widget.conversation ||
          !['direct', 'group'].contains(row['type']) ||
          row['title'] is! String) {
        throw const FormatException('Conversation identity mismatch');
      }
      if (mounted && sessionActive) setState(() => conversation = row);
    } catch (e) {
      if (mounted && sessionActive) {
        setState(() {
          gone = e is ApiError && (e.status == 404 || e.status == 410);
          error = gone
              ? 'This conversation is unavailable.'
              : 'The conversation could not be opened. Try again.';
        });
      }
    } finally {
      if (mounted && sessionActive) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionActive) return retiredSessionView();
    if (conversation != null) {
      return ChatPage(session: widget.session, convo: conversation!);
    }
    return Scaffold(
      appBar: AppBar(title: Text(t_('Chat'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reading) const LinearProgressIndicator(),
            if (error != null) Text(t_(error!)),
            if (error != null && !gone)
              TextButton(
                onPressed: reading ? null : _read,
                child: Text(t_('Try again')),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'room_microphone.dart';
import 'ph.dart';
import 'dart:convert';
import 'package:livekit_client/livekit_client.dart' hide Session;
import 'package:material_ui/material_ui.dart' hide ConnectionState;
import 'api.dart';
import 'gifts.dart';
import 'ui.dart';

/// Live audio rooms: a list of rooms that are on now, and a button to start your own.
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key, required this.session});
  final Session session;

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  List<Map<String, dynamic>> rooms = [];
  bool loading = true;
  bool reading = false;
  String? error;
  bool starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if(reading || !mounted) return;
    setState(()=>reading=true);
    try {
      final j = await widget.session.call('GET', '/rooms') as Map<String, dynamic>;
      final rows=(j['data'] as List).map((v)=>(v as Map).cast<String,dynamic>()).toList();
      if(rows.any((v)=>v['public_id'] is! String || (v['public_id'] as String).trim().isEmpty || v['title'] is! String)) throw const FormatException('Invalid rooms');
      if (mounted) setState(() { rooms=rows; error=null; });
    } catch (e) {
      if (mounted) setState(() => error=e is ApiError?t_(e.message):t_('Rooms could not be loaded.'));
    } finally {
      if(mounted) setState((){loading=false;reading=false;});
    }
  }

  Future<void> _open(String id, {Map<String, dynamic>? created}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(session: widget.session, roomId: id, joined: created)));
    if(mounted) _load();
  }

  Future<void> _start() async {
    if (starting) return;
    setState(() => starting = true);
    try {
      final title = await showDialog<String>(context: context, builder: (_) => const _RoomTitleDialog());
      if (!mounted || title == null) return;
      final j = await widget.session.call('POST', '/rooms', body: {'title': title}) as Map<String, dynamic>;
      if (!mounted) return;
      await _open(j['room_id'] as String, created: {...j, 'title': title, 'is_host': true});
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t_('Live rooms')), actions: [
        IconButton(tooltip:t_('Refresh'),onPressed:reading?null:_load,icon:const PhIcon('arrow-clockwise')),
      ]),
      body: Column(children:[
        Align(alignment:Alignment.centerRight,child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:FilledButton.icon(
          onPressed:starting?null:_start,icon:const PhIcon('microphone',size:18),label:Text(t_('Go live')),
        ))),
        if(error!=null && rooms.isNotEmpty) RefreshReadNotice(onRetry:reading?null:_load),
        Expanded(child:RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : rooms.isEmpty
                ? ListView(physics:const AlwaysScrollableScrollPhysics(),children: [EmptyState(icon: Ph.podcasts, title: error ?? t_('No rooms live right now'), hint: error == null ? t_('Start one and others can listen in.') : null, action: error != null ? OutlinedButton(onPressed: reading?null:_load, child: Text(t_('Try again'))) : FilledButton.icon(onPressed: starting ? null : _start, icon: const PhIcon('microphone', size: 18), label: Text(t_('Go live'))))])
                : ListView.separated(
                    physics:const AlwaysScrollableScrollPhysics(),
                    itemCount: rooms.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rooms[i];
                      return ListTile(
                        leading: const CircleAvatar(child: PhIcon('waveform')),
                        title: Text('${r['title']}'),
                        subtitle: Text('${t_('Hosted by')} ${r['host_name'] ?? r['host_username'] ?? t_('Member')}'),
                        trailing: const PhIcon('caret-right'),
                        onTap: () => _open(r['public_id'] as String),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

class _RoomTitleDialog extends StatefulWidget {
  const _RoomTitleDialog();
  @override
  State<_RoomTitleDialog> createState() => _RoomTitleDialogState();
}

class _RoomTitleDialogState extends State<_RoomTitleDialog> {
  final title = TextEditingController();
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t_('Go live')),
    content: TextField(
      controller: title, autofocus: true, maxLength: 80,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: t_('Room title'), hintText: t_('What is your room about?')),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) { if (title.text.trim().length >= 2) Navigator.pop(context, title.text.trim()); },
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t_('Cancel'))),
      FilledButton(onPressed: title.text.trim().length < 2 ? null : () => Navigator.pop(context, title.text.trim()), child: Text(t_('Start'))),
    ],
  );
}

/// One live room. The host speaks. Listeners chat, raise a hand and send gifts. The host can let a listener speak.
typedef StageMember = ({String id, String name, bool host, bool you, bool muted, bool speaking});

/// Who is on stage. The host label comes only from the stable identity the API returned at join,
/// never from a display name, so two members with the same name cannot be mixed up.
List<StageMember> buildStage({
  required String? meId,
  required String meName,
  required bool meOnStage,
  required bool meMuted,
  required bool meSpeaking,
  required bool iAmHost,
  required String? hostIdentity,
  required List<({String id, String name, bool muted, bool speaking})> remote,
}) {
  return [
    if (meOnStage) (id: meId ?? 'me', name: meName, host: iAmHost, you: true, muted: meMuted, speaking: !meMuted && meSpeaking),
    for (final p in remote)
      (id: p.id, name: p.name.isEmpty ? 'Member' : p.name, host: hostIdentity != null && p.id == hostIdentity, you: false, muted: p.muted, speaking: p.speaking),
  ];
}

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.session, required this.roomId, this.joined});
  final Session session;
  final String roomId;
  final Map<String, dynamic>? joined;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final Room room = Room();
  late final EventsListener<RoomEvent> _events = room.createListener();
  final _chat = TextEditingController();
  final List<Map<String, String>> messages = [];
  final Map<String, String> hands = {};
  String title = 'Live room';
  String status = 'Connecting...';
  String? myId;
  String hostName = 'the host';
  String? hostIdentity;
  bool isHost = false;
  late final RoomMicrophone microphone = RoomMicrophone((on) async {
    final participant = room.localParticipant;
    if (participant == null && on) throw StateError('Not connected');
    await participant?.setMicrophoneEnabled(on);
  });
  bool get speaker => microphone.speaker;
  bool get muted => microphone.muted;
  bool leaving = false;
  bool handUp = false;
  bool failed = false;
  bool ended = false;

  @override
  void initState() {
    super.initState();
    room.addListener(_changed);
    microphone.addListener(_changed);
    _events.on<DataReceivedEvent>(_onData);
    _events.on<RoomDisconnectedEvent>((_) {
      if (mounted && !ended && !failed) {
        unawaited(microphone.revoke().catchError(_micStopFailed));
        setState(() => status = 'Disconnected');
      }
    });
    _join();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _micStopFailed(Object error) {
    if (mounted && !leaving) {
      setState(() {
        failed = true;
        status = 'Microphone state could not be confirmed. Leave this room.';
      });
    }
    unawaited(room.disconnect().catchError((_) {}));
  }

  void _onData(DataReceivedEvent e) {
    if (!mounted) return;
    try {
      final m = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
      final from = e.participant?.name ?? '';
      final fromId = e.participant?.identity ?? '';
      switch (m['t']) {
        case 'gift':
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tf_('{from} sent a {name}', {'from': m['from'], 'name': m['name']}))));
        case 'chat':
          setState(() {
            final text = '${m['text']}';
            messages.add({'from': from, 'text': text.length > 300 ? text.substring(0, 300) : text});
            if (messages.length > 100) messages.removeAt(0);
          });
        case 'hand':
          if (isHost) setState(() => hands[fromId] = from);
        case 'mic':
          unawaited(_hostMicPacket(fromId, m));
      }
    } catch (_) {}
  }

  Future<void> _hostMicPacket(String sender, Map<String, dynamic> packet) async {
    try {
      final wasSpeaker = speaker;
      final accepted = await microphone.hostPacket(sender: sender, host: hostIdentity,
        me: myId, target: packet['to'], allow: packet['allow']);
      if (!mounted || leaving || !accepted) return;
      setState(() => handUp = false);
      if (packet['allow'] == true && !wasSpeaker) {
        showInfo(context, 'You can speak. Tap Unmute when ready.');
      }
    } catch (e) {
      if (microphone.stopUnconfirmed) _micStopFailed(e);
      if (mounted && !leaving) showError(context, e);
    }
  }

  Future<void> _send(Map<String, dynamic> m) async {
    await room.localParticipant?.publishData(utf8.encode(jsonEncode(m)), reliable: true);
  }

  Future<void> _join() async {
    try {
      final j = widget.joined ?? await widget.session.call('POST', '/rooms/${widget.roomId}/join') as Map<String, dynamic>;
      title = (j['title'] ?? title).toString();
      isHost = j['is_host'] == true;
      myId = j['identity']?.toString();
      hostName = (j['host_name'] ?? hostName).toString();
      hostIdentity = j['host_identity']?.toString();
      await room.connect(j['url'] as String, j['token'] as String);
      if (!mounted || leaving) return;
      if (isHost) await microphone.startHost();
      if (mounted) setState(() => status = 'Live');
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          status = e.status == 410 ? 'This room has ended.' : e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          status = 'Could not join. Check your connection${isHost ? ' and microphone permission' : ''}.';
        });
      }
    }
  }

  Future<void> _toggleMic() async {
    if (leaving || room.connectionState != ConnectionState.connected) return;
    try { await microphone.toggle(); } catch (e) {
      if (mounted && !leaving) showError(context, e);
    }
  }

  Future<void> _end() async {
    if (ended) return;
    ended = true;
    leaving = true;
    try { await microphone.revoke(); } catch (_) {}
    try {
      await widget.session.call('POST', '/rooms/${widget.roomId}/end');
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  Future<void> _sendChat() async {
    final t = _chat.text.trim();
    if (t.isEmpty) return;
    _chat.clear();
    final me = widget.session.user?['name'] ?? widget.session.user?['username'] ?? 'Me';
    setState(() => messages.add({'from': '$me', 'text': t}));
    await _send({'t': 'chat', 'text': t});
  }

  Future<void> _raise() async {
    setState(() => handUp = true);
    await _send({'t': 'hand'});
  }

  Future<void> _allow(String id, bool allow) async {
    try {
      await widget.session.call('POST', '/rooms/${widget.roomId}/speaker', body: {'identity': id, 'allow': allow});
      await _send({'t': 'mic', 'to': id, 'allow': allow});
      if (mounted) setState(() => hands.remove(id));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _gift() {
    showGiftSheet(
      context,
      widget.session,
      widget.roomId,
      hostName,
      path: '/rooms/${widget.roomId}/gifts',
      onSent: (g) {
        final me = widget.session.user?['name'] ?? widget.session.user?['username'] ?? 'Someone';
        _send({'t': 'gift', 'from': '$me', 'name': g['name']});
      },
    );
  }

  @override
  void dispose() {
    _events.dispose();
    _chat.dispose();
    leaving = true;
    microphone.removeListener(_changed);
    room.removeListener(_changed);
    unawaited(() async {
      try { await microphone.close(); } catch (_) {}
      try { await room.disconnect(); } finally {
        microphone.dispose();
        await room.dispose();
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoomView(
      title: title,
      status: microphone.stopUnconfirmed ? 'Microphone state could not be confirmed. Leave this room.' : status,
      failed: failed || microphone.stopUnconfirmed,
      isHost: isHost,
      speaker: speaker,
      muted: muted,
      handUp: handUp,
      inRoom: room.remoteParticipants.length + (failed ? 0 : 1),
      hands: hands,
      stage: buildStage(
        meId: myId,
        meName: (widget.session.user?['name'] ?? widget.session.user?['username'] ?? 'You').toString(),
        meOnStage: !failed && speaker,
        meMuted: muted,
        meSpeaking: room.localParticipant?.isSpeaking ?? false,
        iAmHost: isHost,
        hostIdentity: hostIdentity,
        remote: [for (final p in room.remoteParticipants.values.where((p) => p.permissions.canPublish)) (id: p.identity, name: p.name, muted: p.isMuted, speaking: p.isSpeaking)],
      ),
      messages: messages,
      chat: _chat,
      onEnd: _end,
      onToggleMic: _toggleMic,
      micBusy: microphone.busy || leaving || room.connectionState != ConnectionState.connected,
      onRaise: _raise,
      onGift: _gift,
      onAllow: _allow,
      onDismissHand: (id) => setState(() => hands.remove(id)),
      onSend: _sendChat,
    );
  }
}

/// The room screen as plain data and callbacks, so it can be rendered in tests without LiveKit.
class RoomView extends StatelessWidget {
  const RoomView({
    super.key,
    required this.title,
    required this.status,
    required this.failed,
    required this.isHost,
    required this.speaker,
    required this.muted,
    required this.handUp,
    required this.inRoom,
    required this.hands,
    required this.stage,
    required this.messages,
    required this.chat,
    required this.onEnd,
    required this.onToggleMic,
    this.micBusy = false,
    required this.onRaise,
    required this.onGift,
    required this.onAllow,
    required this.onDismissHand,
    required this.onSend,
  });
  final String title;
  final String status;
  final bool failed;
  final bool isHost;
  final bool speaker;
  final bool muted;
  final bool handUp;
  final bool micBusy;
  final int inRoom;
  final Map<String, String> hands;
  final List<StageMember> stage;
  final List<Map<String, String>> messages;
  final TextEditingController chat;
  final VoidCallback onEnd;
  final VoidCallback onToggleMic;
  final VoidCallback onRaise;
  final VoidCallback onGift;
  final void Function(String id, bool allow) onAllow;
  final void Function(String id) onDismissHand;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (!isHost && !failed) IconButton(tooltip: t_('Send a gift'), onPressed: onGift, icon: const PhIcon('gift')),
        if (isHost && !failed) TextButton(onPressed: onEnd, child: Text(t_('End'))),
      ]),
      body: failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  PhIcon('warning-circle', size: 64, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(status, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: () => Navigator.pop(context), child: Text(t_('Back'))),
                ]),
              ),
            )
          : _roomBody(context, <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
                    child: Text(status.toUpperCase(), style: TextStyle(color: scheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tf_('{n} in the room', {'n': inRoom}), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                  if (!isHost && !speaker) OutlinedButton.icon(onPressed: handUp ? null : onRaise, icon: const PhIcon('hand-waving', size: 18), label: Text(handUp ? 'Hand raised' : 'Raise hand'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36))),
                ]),
              ),
              _fx(context, 3, _scr(context, Column(children: [
              if (isHost && hands.isNotEmpty)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: Text(tf_('Raised hands ({n})', {'n': hands.length}), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.4))),
                    for (final h in hands.entries)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                        child: MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3
                            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  const PhIcon('hand-waving', size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(h.value.isEmpty ? 'Member' : h.value, maxLines: 2, overflow: TextOverflow.ellipsis)),
                                ]),
                                const SizedBox(height: 6),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  TextButton(onPressed: () => onDismissHand(h.key), child: Text(t_('Dismiss'))),
                                  FilledButton(onPressed: () => onAllow(h.key, true), child: Text(t_('Let speak'))),
                                ]),
                              ])
                            : Row(children: [
                                const PhIcon('hand-waving', size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Text(h.value.isEmpty ? 'Member' : h.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                TextButton(onPressed: () => onDismissHand(h.key), child: Text(t_('Dismiss'))),
                                const SizedBox(width: 4),
                                FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)), onPressed: () => onAllow(h.key, true), child: Text(t_('Let speak'))),
                              ]),
                      ),
                    const SizedBox(height: 4),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text(t_('On stage'), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6))),
              ),
              if (stage.isEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Align(alignment: Alignment.centerLeft, child: Text(t_('Nobody is speaking yet.'))))
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(),
                    child: SingleChildScrollView(child: Wrap(spacing: 12, runSpacing: 16, children: [
                    for (final m in stage)
                      SizedBox(
                        width: 96 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: m.speaking ? scheme.primary : Colors.transparent, width: 2)),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: scheme.surfaceContainerHighest,
                              child: Text(m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text([m.name, if (m.host) '(host)', if (m.you) '(you)'].join(' '), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                          const SizedBox(height: 2),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            PhIcon(m.muted ? Ph.mic_off : Ph.mic, size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Flexible(child: Text(m.muted ? 'Muted' : (m.speaking ? 'Speaking' : 'Mic on'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
                          ]),
                          if (isHost && !m.you && !m.host)
                            TextButton(onPressed: () => onAllow(m.id, false), style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)), child: Text(t_('Move to listeners'), style: const TextStyle(fontSize: 12))),
                        ]),
                      ),
                  ])),
                  ),
                ),
              ]))),
              if (speaker && muted && !isHost) Padding(
                padding: const EdgeInsets.symmetric(horizontal:16, vertical:8),
                child: Text(t_('You can speak. Tap Unmute when ready.')),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              _fx(context, 1, messages.isEmpty
                    ? (_large(context) ? Padding(padding: const EdgeInsets.fromLTRB(16,12,16,24), child: Text(t_('No messages yet. Say hello to the room.'), style: Theme.of(context).textTheme.bodyMedium)) : const SingleChildScrollView(child: EmptyState(icon: Ph.chat_bubble_outline, title: 'No messages yet', hint: 'Say hello to the room.')))
                    : ListView.builder(
                        reverse: !_large(context),
                        shrinkWrap: _large(context),
                        physics: _large(context) ? const NeverScrollableScrollPhysics() : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = _large(context) ? messages[i] : messages[messages.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: '${m['from']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: m['text']),
                            ])),
                          );
                        },
                      )),
            ],
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(children: [
                    if (speaker) IconButton.filledTonal(tooltip: t_(muted ? 'Unmute' : 'Mute'), onPressed: micBusy ? null : onToggleMic, icon: PhIcon(muted ? Ph.mic_off : Ph.mic)),
                    if (speaker) const SizedBox(width: 8),
                    Expanded(child: TextField(controller: chat, maxLength: 300, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, decoration: const InputDecoration(hintText: 'Say something'), onSubmitted: (_) => onSend())),
                    const SizedBox(width: 8),
                    IconButton.filled(tooltip: t_('Send'), onPressed: onSend, icon: PhIcon('paper-plane-tilt-fill', color: Theme.of(context).colorScheme.onPrimary)),
                  ]),
                ),
              ),
            ),
    );
  }
}


bool _large(BuildContext c) => MediaQuery.textScalerOf(c).scale(14) / 14 > 1.3;

/// Normal sizes: the top block and the messages share the room. Large text: one scroll area.
Widget _fx(BuildContext c, int flex, Widget w) => _large(c) ? w : Flexible(flex: flex, child: w);
Widget _scr(BuildContext c, Widget w) => _large(c) ? w : SingleChildScrollView(child: w);

Widget _roomBody(BuildContext c, List<Widget> pre, Widget composer) => _large(c)
    ? Column(children: [Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: pre))), composer])
    : Column(children: [...pre, composer]);

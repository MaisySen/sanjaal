import 'ph.dart';
import 'dart:convert';
import 'package:livekit_client/livekit_client.dart' hide Session;
import 'package:material_ui/material_ui.dart';
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
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.call('GET', '/rooms') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        rooms = (j['data'] as List).cast<Map<String, dynamic>>();
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _open(String id, {Map<String, dynamic>? created}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(session: widget.session, roomId: id, joined: created)));
    _load();
  }

  Future<void> _start() async {
    final c = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t_('Go live')),
        content: TextField(controller: c, autofocus: true, maxLength: 80, decoration: const InputDecoration(hintText: 'What is your room about?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t_('Start'))),
        ],
      ),
    );
    if (title == null || title.length < 2) return;
    try {
      final j = await widget.session.call('POST', '/rooms', body: {'title': title}) as Map<String, dynamic>;
      if (!mounted) return;
      await _open(j['room_id'] as String, created: {...j, 'title': title, 'is_host': true});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t_('Live rooms')), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(onPressed: _start, icon: const PhIcon('microphone', size: 18), label: Text(t_('Go live')), style: FilledButton.styleFrom(minimumSize: const Size(64, 36))),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : rooms.isEmpty
                ? ListView(children: [EmptyState(icon: Ph.podcasts, title: error ?? 'No rooms live right now', hint: 'Start one and others can listen in.')])
                : ListView.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rooms[i];
                      return ListTile(
                        leading: const CircleAvatar(child: PhIcon('waveform')),
                        title: Text('${r['title']}'),
                        subtitle: Text('Hosted by ${r['host_name'] ?? r['host_username']}'),
                        trailing: const PhIcon('caret-right'),
                        onTap: () => _open(r['public_id'] as String),
                      );
                    },
                  ),
      ),
    );
  }
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
  bool speaker = false;
  bool muted = false;
  bool handUp = false;
  bool failed = false;
  bool ended = false;

  @override
  void initState() {
    super.initState();
    room.addListener(_changed);
    _events.on<DataReceivedEvent>(_onData);
    _events.on<RoomDisconnectedEvent>((_) {
      if (mounted && !ended) setState(() => status = 'Disconnected');
    });
    _join();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onData(DataReceivedEvent e) {
    if (!mounted) return;
    try {
      final m = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
      final from = e.participant?.name ?? '';
      final fromId = e.participant?.identity ?? '';
      switch (m['t']) {
        case 'gift':
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${m['from']} sent a ${m['name']}')));
        case 'chat':
          setState(() {
            final text = '${m['text']}';
            messages.add({'from': from, 'text': text.length > 300 ? text.substring(0, 300) : text});
            if (messages.length > 100) messages.removeAt(0);
          });
        case 'hand':
          if (isHost) setState(() => hands[fromId] = from);
        case 'mic':
          if (m['to'] == myId) _setSpeaker(m['allow'] == true);
      }
    } catch (_) {}
  }

  Future<void> _setSpeaker(bool on) async {
    try {
      await room.localParticipant?.setMicrophoneEnabled(on);
      if (!mounted) return;
      setState(() {
        speaker = on;
        handUp = false;
        muted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(on ? 'The host let you speak' : 'The host took the mic back')));
    } catch (_) {}
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
      if (isHost) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        speaker = true;
      }
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
    final next = !muted;
    await room.localParticipant?.setMicrophoneEnabled(!next);
    if (mounted) setState(() => muted = next);
  }

  Future<void> _end() async {
    ended = true;
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
    room.removeListener(_changed);
    room.disconnect();
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoomView(
      title: title,
      status: status,
      failed: failed,
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
        if (!isHost && !failed) IconButton(tooltip: 'Send a gift', onPressed: onGift, icon: const PhIcon('gift')),
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
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
                    child: Text(status.toUpperCase(), style: TextStyle(color: scheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$inRoom in the room', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                  if (!isHost && !speaker) OutlinedButton.icon(onPressed: handUp ? null : onRaise, icon: const PhIcon('hand-waving', size: 18), label: Text(handUp ? 'Hand raised' : 'Raise hand'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36))),
                ]),
              ),
              if (isHost && hands.isNotEmpty)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(children: [
                    for (final h in hands.entries)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        ]),
                      ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text('On stage', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6))),
              ),
              if (stage.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 16), child: Align(alignment: Alignment.centerLeft, child: Text('Nobody is speaking yet.')))
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
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
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: messages.isEmpty
                    ? const EmptyState(icon: Ph.chat_bubble_outline, title: 'No messages yet', hint: 'Say hello to the room.')
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = messages[messages.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: '${m['from']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: m['text']),
                            ])),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(children: [
                    if (speaker) IconButton.filledTonal(tooltip: muted ? 'Unmute' : 'Mute', onPressed: onToggleMic, icon: PhIcon(muted ? Ph.mic_off : Ph.mic)),
                    if (speaker) const SizedBox(width: 8),
                    Expanded(child: TextField(controller: chat, maxLength: 300, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, decoration: const InputDecoration(hintText: 'Say something'), onSubmitted: (_) => onSend())),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: onSend, icon: PhIcon('paper-plane-tilt-fill', color: Theme.of(context).colorScheme.onPrimary)),
                  ]),
                ),
              ),
            ]),
    );
  }
}


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
        title: const Text('Go live'),
        content: TextField(controller: c, autofocus: true, maxLength: 80, decoration: const InputDecoration(hintText: 'What is your room about?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Start')),
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
      appBar: AppBar(title: const Text('Live rooms')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _start, icon: const Icon(Icons.mic), label: const Text('Go live')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
            : rooms.isEmpty
                ? ListView(children: [EmptyState(icon: Icons.podcasts, title: error ?? 'No rooms live right now', hint: 'Start one and others can listen in.')])
                : ListView.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rooms[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.graphic_eq)),
                        title: Text('${r['title']}'),
                        subtitle: Text('Hosted by ${r['host_name'] ?? r['host_username']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(r['public_id'] as String),
                      );
                    },
                  ),
      ),
    );
  }
}

/// One live room. The host can speak. Everyone else listens and can send the host a gift.
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
  String title = 'Live room';
  String status = 'Connecting...';
  bool isHost = false;
  bool muted = false;
  bool failed = false;
  bool ended = false;
  String? hostName;

  @override
  void initState() {
    super.initState();
    room.addListener(_changed);
    _events.on<DataReceivedEvent>((e) {
      try {
        final m = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
        if (m['t'] == 'gift' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${m['from']} sent a ${m['name']}')));
        }
      } catch (_) {}
    });
    _events.on<RoomDisconnectedEvent>((_) {
      if (mounted && !ended) setState(() => status = 'Disconnected');
    });
    _join();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    try {
      final j = widget.joined ?? await widget.session.call('POST', '/rooms/${widget.roomId}/join') as Map<String, dynamic>;
      title = (j['title'] ?? title).toString();
      isHost = j['is_host'] == true;
      await room.connect(j['url'] as String, j['token'] as String);
      if (isHost) await room.localParticipant?.setMicrophoneEnabled(true);
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

  void _gift() {
    final host = room.remoteParticipants.values.isNotEmpty ? room.remoteParticipants.values.first : null;
    hostName = host?.name;
    showGiftSheet(
      context,
      widget.session,
      widget.roomId,
      hostName ?? 'the host',
      path: '/rooms/${widget.roomId}/gifts',
      onSent: (g) {
        final me = widget.session.user?['name'] ?? widget.session.user?['username'] ?? 'Someone';
        room.localParticipant?.publishData(utf8.encode(jsonEncode({'t': 'gift', 'from': me, 'name': g['name']})), reliable: true);
      },
    );
  }

  @override
  void dispose() {
    _events.dispose();
    room.removeListener(_changed);
    room.disconnect();
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listeners = room.remoteParticipants.length + (failed ? 0 : 1);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(failed ? Icons.error_outline : Icons.graphic_eq, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(status, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (!failed) Text('$listeners in the room'),
            const SizedBox(height: 32),
            if (!failed && isHost) ...[
              FilledButton.icon(onPressed: _toggleMic, icon: Icon(muted ? Icons.mic_off : Icons.mic), label: Text(muted ? 'Unmute' : 'Mute')),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _end, icon: const Icon(Icons.stop_circle_outlined), label: const Text('End room')),
            ],
            if (!failed && !isHost) FilledButton.icon(onPressed: _gift, icon: const Icon(Icons.card_giftcard), label: const Text('Send a gift')),
            if (failed) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          ]),
        ),
      ),
    );
  }
}

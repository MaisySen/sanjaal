import 'package:livekit_client/livekit_client.dart' hide Session;
import 'package:material_ui/material_ui.dart';
import 'api.dart';

/// Voice or video call for one conversation, over LiveKit.
class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.session, required this.conversationId, required this.title, required this.video, this.callId});
  final Session session;
  final String conversationId;
  final String title;
  final bool video;
  final String? callId;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final Room room = Room();
  String status = 'Connecting...';
  bool muted = false;
  bool camOn = false;
  bool failed = false;
  String? _callId;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    room.addListener(_changed);
    _join();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    try {
      final qs = widget.callId != null ? '?call=${widget.callId}' : '?kind=${widget.video ? 'video' : 'voice'}';
      final j = await widget.session.call('POST', '/conversations/${widget.conversationId}/call-token$qs') as Map<String, dynamic>;
      _callId = j['call_id'] as String?;
      await room.connect(j['url'] as String, j['token'] as String);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (widget.video) {
        await room.localParticipant?.setCameraEnabled(true);
        camOn = true;
      }
      if (mounted) setState(() => status = 'Connected');
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          status = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          status = 'Could not start the call. Check your connection and microphone permission.';
        });
      }
    }
  }

  void _endCall() {
    if (_ended || _callId == null) return;
    _ended = true;
    widget.session.call('POST', '/calls/$_callId/action', body: {'action': 'end'}).catchError((_) => null);
  }

  @override
  void dispose() {
    _endCall();
    room.removeListener(_changed);
    room.disconnect();
    room.dispose();
    super.dispose();
  }

  VideoTrack? _videoOf(Participant p) {
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack && !pub.muted) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final remotes = room.remoteParticipants.values.toList();
    final tiles = <Widget>[];
    for (final p in remotes) {
      final v = _videoOf(p);
      tiles.add(_tile(p.name.isEmpty ? 'Member' : p.name, v));
    }
    final me = room.localParticipant;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Column(children: [
        Expanded(
          child: tiles.isEmpty
              ? Center(child: Text(failed ? status : (status == 'Connected' ? 'Waiting for others to join' : status), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
              : GridView.count(crossAxisCount: tiles.length > 1 ? 2 : 1, children: tiles),
        ),
        if (me != null && camOn && _videoOf(me) != null)
          SizedBox(height: 120, width: 90, child: VideoTrackRenderer(_videoOf(me)!)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filledTonal(
                onPressed: failed ? null : () async {
                  muted = !muted;
                  await room.localParticipant?.setMicrophoneEnabled(!muted);
                  _changed();
                },
                icon: Icon(muted ? Icons.mic_off : Icons.mic),
              ),
              if (widget.video)
                IconButton.filledTonal(
                  onPressed: failed ? null : () async {
                    camOn = !camOn;
                    await room.localParticipant?.setCameraEnabled(camOn);
                    _changed();
                  },
                  icon: Icon(camOn ? Icons.videocam : Icons.videocam_off),
                ),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.call_end),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tile(String name, VideoTrack? v) => Container(
        margin: const EdgeInsets.all(4),
        color: Colors.grey.shade900,
        child: Stack(children: [
          if (v != null) Positioned.fill(child: VideoTrackRenderer(v)) else const Center(child: Icon(Icons.person, size: 64, color: Colors.white54)),
          Positioned(left: 8, bottom: 8, child: Text(name, style: const TextStyle(color: Colors.white))),
        ]),
      );
}

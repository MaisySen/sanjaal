import 'ph.dart';
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
    return CallView(
      title: widget.title,
      status: status,
      failed: failed,
      video: widget.video,
      muted: muted,
      camOn: camOn,
      tiles: tiles,
      selfPreview: me != null && camOn && _videoOf(me) != null ? VideoTrackRenderer(_videoOf(me)!) : null,
      onMute: () async {
        muted = !muted;
        await room.localParticipant?.setMicrophoneEnabled(!muted);
        _changed();
      },
      onCamera: () async {
        camOn = !camOn;
        await room.localParticipant?.setCameraEnabled(camOn);
        _changed();
      },
      onEnd: () => Navigator.of(context).pop(),
    );
  }

  Widget _tile(String name, VideoTrack? v) => CallTile(name: name, video: v == null ? null : VideoTrackRenderer(v));
}

/// One participant tile: video when there is any, otherwise a placeholder with the name.
class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.name, this.video});
  final String name;
  final Widget? video;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (video != null) Positioned.fill(child: video!) else const Center(child: PhIcon('user-fill', size: 64, color: Colors.white54)),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)), child: Text(name, style: const TextStyle(color: Colors.white))),
          ),
        ]),
      );
}

/// The call screen without any LiveKit dependency, so it can be rendered offline.
class CallView extends StatelessWidget {
  const CallView({super.key, required this.title, required this.status, required this.failed, required this.video, required this.muted, required this.camOn, required this.tiles, required this.onMute, required this.onCamera, required this.onEnd, this.selfPreview});
  final String title;
  final String status;
  final bool failed;
  final bool video;
  final bool muted;
  final bool camOn;
  final List<Widget> tiles;
  final Widget? selfPreview;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Column(children: [
        Expanded(
          child: tiles.isEmpty
              ? Center(child: Text(failed ? status : (status == 'Connected' ? 'Waiting for others to join' : status), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
              : Stack(children: [
                  LayoutBuilder(builder: (context, box) {
                    final cols = tiles.length > 1 ? 2 : 1;
                    final rows = (tiles.length / cols).ceil();
                    return GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: cols,
                      childAspectRatio: (box.maxWidth / cols) / (box.maxHeight / rows),
                      children: tiles,
                    );
                  }),
                  if (selfPreview != null) Positioned(right: 14, top: 14, child: SizedBox(height: 120, width: 90, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: selfPreview))),
                ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(40)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), foregroundColor: Colors.white),
                  onPressed: failed ? null : onMute,
                  icon: PhIcon(muted ? Ph.mic_off : Ph.mic),
                ),
                if (video)
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), foregroundColor: Colors.white),
                    onPressed: failed ? null : onCamera,
                    icon: PhIcon(camOn ? Ph.videocam : Ph.videocam_off),
                  ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: onEnd,
                  icon: const PhIcon('phone-x-fill', color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

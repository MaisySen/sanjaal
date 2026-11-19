import 'session_bound_state.dart';
import 'ph.dart';
import 'package:livekit_client/livekit_client.dart' hide Session, ConnectionState;
import 'package:livekit_client/livekit_client.dart' as livekit show ConnectionState;
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'call_lifecycle.dart';
import 'call_presentation.dart';
import 'ui.dart' show showError, t_;

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

class _CallPageState extends State<CallPage> with SessionBoundState<CallPage> {
  @override Session get viewSession => widget.session;

  final Room room = Room();
  String status = 'Connecting...';
  bool muted = false;
  bool camOn = false;
  bool failed = false;
  String? _callId;
  bool _ended = false;
  bool _closed = false;
  bool _mediaBusy = false;
  bool _setupComplete = false;
  late final Future<void> _joining;
  Future<void>? _mediaChange;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId;
    room.addListener(_changed);
    _joining = _join();
  }

  @override void sessionRetired(){
    _closed=true;
    // Do not end this call with credentials from a different login.
    _ended=true;
    _releaseRoom();
  }
  void _changed() {
    if (mounted && sessionActive) setState(() {});
  }

  Future<void> _join() async {
    try {
      late Map<String, dynamic> token;
      final connected = await connectCallWhileActive(
        isActive: () => mounted && !_closed && sessionActive,
        requestToken: () async {
          final qs = widget.callId != null ? '?call=${widget.callId}' : '?kind=${widget.video ? 'video' : 'voice'}';
          token = await widget.session.call('POST', '/conversations/${widget.conversationId}/call-token$qs') as Map<String, dynamic>;
          _callId = token['call_id'] as String? ?? _callId;
        },
        connect: () => room.connect(token['url'] as String, token['token'] as String),
        microphone: () async { await room.localParticipant?.setMicrophoneEnabled(true); },
        camera: () async { await room.localParticipant?.setCameraEnabled(true); },
        video: widget.video,
      );
      if (!connected) {
        _endCall();
        await _disconnectSafely();
        return;
      }
      if (mounted && sessionActive) setState(() { _setupComplete = true; camOn = widget.video; });
    } on ApiError catch (e) {
      _endCall();
      await _disconnectSafely();
      if (mounted && sessionActive) {
        setState(() {
          failed = true;
          status = e.message;
        });
      }
    } catch (_) {
      _endCall();
      await _disconnectSafely();
      if (mounted && sessionActive) {
        setState(() {
          failed = true;
          status = 'Could not start the call. Check your connection and microphone permission.';
        });
      }
    }
  }

  void _endCall() {
    if (!sessionActive || _ended || _callId == null) return;
    _ended = true;
    widget.session.call('POST', '/calls/$_callId/action', body: {'action': 'end'}).catchError((_) => null);
  }

  @override
  void dispose() {
    _closed = true;
    _endCall();
    room.removeListener(_changed);
    _releaseRoom();
    super.dispose();
  }

  Future<void> _disconnectSafely() async {
    try { await room.disconnect(); } catch (_) {}
  }

  Future<void>? _release;
  Future<void> _releaseRoom() => _release ??= () async {
    // Stop capture immediately, then wait for any token/connect operation to
    // observe _closed before disposing the native room it may still be using.
    await _disconnectSafely();
    try { await _joining; } catch (_) {}
    try { await _mediaChange; } catch (_) {}
    await _disconnectSafely();
    try { await room.dispose(); } catch (_) {}
  }();

  void _changeMedia({required bool camera}) {
    if (!sessionActive || _closed || _mediaBusy || failed || room.localParticipant == null) return;
    _mediaChange = _media(camera: camera);
  }

  Future<void> _media({required bool camera}) async {
    if (!sessionActive || _closed || _mediaBusy || failed || room.localParticipant == null) return;
    setState(() => _mediaBusy = true);
    try {
      final next = camera ? !camOn : !muted;
      if (camera) {
        await room.localParticipant?.setCameraEnabled(next);
      } else {
        await room.localParticipant?.setMicrophoneEnabled(!next);
      }
      if (mounted && sessionActive) setState(() { if (camera) { camOn = next; } else { muted = next; } });
    } catch (e) {
      if (mounted && sessionActive) showError(context, e);
    } finally {
      if (mounted && sessionActive) setState(() => _mediaBusy = false);
    }
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
    if(!sessionActive)return retiredSessionView();
    final remotes = room.remoteParticipants.values.toList();
    final presentation = presentCall(
      transport: switch (room.connectionState) {
        livekit.ConnectionState.connected => CallTransport.connected,
        livekit.ConnectionState.reconnecting => CallTransport.reconnecting,
        livekit.ConnectionState.disconnected => CallTransport.disconnected,
        livekit.ConnectionState.connecting => CallTransport.connecting,
      },
      setupComplete: _setupComplete, remoteCount: remotes.length,
      previouslyConnected: _setupComplete,
    );
    final tiles = <Widget>[];
    for (final p in remotes) {
      final v = _videoOf(p);
      tiles.add(_tile(p.name.isEmpty ? 'Member' : p.name, v));
    }
    final me = room.localParticipant;
    return CallView(
      title: widget.title,
      status: failed ? status : presentation.status,
      failed: failed,
      video: widget.video,
      muted: muted,
      camOn: camOn,
      tiles: tiles,
      selfPreview: me != null && camOn && _videoOf(me) != null ? VideoTrackRenderer(_videoOf(me)!) : null,
      controlsBusy: _mediaBusy || !presentation.mediaAvailable,
      onMute: () => _changeMedia(camera: false),
      onCamera: () => _changeMedia(camera: true),
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
  const CallView({super.key, required this.title, required this.status, required this.failed, required this.video, required this.muted, required this.camOn, required this.tiles, required this.onMute, required this.onCamera, required this.onEnd, this.selfPreview, this.controlsBusy = false});
  final String title;
  final String status;
  final bool failed;
  final bool video;
  final bool muted;
  final bool camOn;
  final List<Widget> tiles;
  final Widget? selfPreview;
  final bool controlsBusy;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(leading: Navigator.of(context).canPop() ? BackButton(color: Colors.white, style: IconButton.styleFrom(foregroundColor: Colors.white), onPressed: onEnd) : null, title: Text(title, style: const TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Semantics(liveRegion: true, child: Text(status, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70))),
        ),
        Expanded(child: Stack(children: [
          if (tiles.isEmpty)
            const Center(child: PhIcon('user-fill', size: 80, color: Colors.white54))
          else LayoutBuilder(builder: (context, box) {
            final cols = tiles.length > 1 ? 2 : 1;
            final rows = (tiles.length / cols).ceil();
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(), crossAxisCount: cols,
              childAspectRatio: (box.maxWidth / cols) / (box.maxHeight / rows), children: tiles,
            );
          }),
          if (selfPreview != null) Positioned(right: 14, top: 14,
            child: Semantics(label: 'Your camera preview', child: SizedBox(height: 120, width: 90,
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: selfPreview)))),
        ])),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(40)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), foregroundColor: Colors.white),
                  tooltip: muted ? 'Unmute microphone' : 'Mute microphone',
                  onPressed: failed || controlsBusy ? null : onMute,
                  icon: PhIcon(muted ? Ph.mic_off : Ph.mic),
                ),
                if (video)
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), foregroundColor: Colors.white),
                    tooltip: camOn ? 'Turn camera off' : 'Turn camera on',
                    onPressed: failed || controlsBusy ? null : onCamera,
                    icon: PhIcon(camOn ? Ph.videocam : Ph.videocam_off),
                  ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  tooltip: t_('End call'),
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

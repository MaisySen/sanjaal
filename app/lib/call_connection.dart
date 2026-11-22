import 'package:material_ui/material_ui.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'call_presentation.dart';
import 'call_view.dart';

/// Attempt every owned capture stop, but never hide a failure behind another
/// successful cleanup. False success would allow a second native owner.
Future<void> stopCallCaptures(Iterable<Future<void> Function()> stops) async {
  Object? failure;
  StackTrace? trace;
  for (final stop in stops) {
    try {
      await stop();
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, trace!);
}

abstract class CallConnection {
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  CallTransport get transport;
  int get remoteCount;
  bool get localAvailable;
  bool? get microphoneEnabled;
  bool? get cameraEnabled;
  List<Widget> get tiles;
  Widget? get selfPreview;
  Future<void> connect(String url, String token);
  Future<void> microphone(bool enabled);
  Future<void> camera(bool enabled);
  Future<void> stopCapture();
  Future<void> disconnect();
  Future<void> dispose();
}

class NativeCallConnection implements CallConnection {
  NativeCallConnection({lk.Room? room}) : room = room ?? lk.Room();
  final _ownedTracks = <lk.LocalTrack>{};
  final _stoppedTracks = <Object>{};
  final _closedPeers = <Object>{};
  final lk.Room room;
  @override
  void addListener(VoidCallback listener) => room.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => room.removeListener(listener);
  @override
  CallTransport get transport => switch (room.connectionState) {
    lk.ConnectionState.connected => CallTransport.connected,
    lk.ConnectionState.connecting => CallTransport.connecting,
    lk.ConnectionState.reconnecting => CallTransport.reconnecting,
    lk.ConnectionState.disconnected => CallTransport.disconnected,
  };
  @override
  int get remoteCount => room.remoteParticipants.length;
  @override
  bool get localAvailable => room.localParticipant != null;
  @override
  bool? get microphoneEnabled => room.localParticipant?.isMicrophoneEnabled();
  @override
  bool? get cameraEnabled => room.localParticipant?.isCameraEnabled();
  lk.VideoTrack? _video(lk.Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.VideoTrack && !publication.muted) return track;
    }
    return null;
  }

  @override
  List<Widget> get tiles => [
    for (final participant in room.remoteParticipants.values)
      CallTile(
        name: participant.name.isEmpty ? 'Member' : participant.name,
        video: _video(participant) == null
            ? null
            : lk.VideoTrackRenderer(_video(participant)!),
      ),
  ];
  @override
  Widget? get selfPreview {
    final me = room.localParticipant;
    final track = me == null ? null : _video(me);
    return track == null ? null : lk.VideoTrackRenderer(track);
  }

  @override
  Future<void> connect(String url, String token) => room.connect(url, token);
  @override
  Future<void> microphone(bool enabled) async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('No local call participant');
    final publication = await participant.setMicrophoneEnabled(enabled);
    final track = publication?.track;
    if (track != null) _ownedTracks.add(track);
  }

  @override
  Future<void> camera(bool enabled) async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('No local call participant');
    final publication = await participant.setCameraEnabled(enabled);
    final track = publication?.track;
    if (track != null) _ownedTracks.add(track);
  }

  @override
  Future<void> stopCapture() async {
    final participant = room.localParticipant;
    if (participant != null) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track != null) _ownedTracks.add(track);
      }
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track != null) _ownedTracks.add(track);
      }
    }
    // LiveKit's generic dispose handler logs and swallows cleanup errors.
    // Stop owned tracks directly so a native failure reaches our quarantine.
    await stopCallCaptures([
      for (final track in _ownedTracks.toList())
        if (!_stoppedTracks.contains(track.mediaStreamTrack))
          () async {
            final nativeTrack = track.mediaStreamTrack;
            final stream = track.mediaStream;
            // Bypass LocalTrack.stop as well: it can swallow stream-disposal
            // failures. These platform futures propagate their native errors.
            await stopCallCaptures([nativeTrack.stop, stream.dispose]);
            _stoppedTracks.add(nativeTrack);
          },
    ]);
  }

  @override
  Future<void> disconnect() async {
    // The pinned SDK's Transport.dispose also uses its swallowing disposer.
    // Close the real peer connections before that wrapper discards them.
    // LiveKit 2.13.2 exposes no public error-propagating peer close. This is
    // a deliberate, narrow internal-API bridge, not a general SDK extension.
    // Exact SDK/plugin pins and native_call_connection_test protect upgrades.
    // ignore: invalid_use_of_internal_member
    final peers = [room.engine.publisher?.pc, room.engine.subscriber?.pc];
    Object? failure;
    StackTrace? trace;
    try {
      await stopCallCaptures([
        for (final peer in peers)
          if (peer != null && !_closedPeers.contains(peer))
            () async {
              await peer.close();
              _closedPeers.add(peer);
            },
      ]);
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    try {
      await room.disconnect();
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }

  @override
  Future<void> dispose() async {
    await room.dispose();
  }
}

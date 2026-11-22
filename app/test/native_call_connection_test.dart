// Pinned-SDK adapter contract tests intentionally construct its internal peer
// handle types. Production access and version guards are reviewed separately.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart'
    as platform;
import 'package:flutter_webrtc/src/native/media_stream_impl.dart' as platform;
import 'package:flutter_webrtc/src/native/rtc_peerconnection_impl.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_client/src/core/engine.dart' as sdk;
import 'package:livekit_client/src/core/transport.dart' as sdk;
import 'package:sanjaal/call_connection.dart';

class _Track implements rtc.MediaStreamTrack {
  _Track(this.name, this.events);
  final String name;
  final List<String> events;
  bool fail = false;
  Future<void>? wait;
  @override
  Future<void> stop() async {
    events.add('$name.stop');
    await wait;
    if (fail) throw StateError('Synthetic native track-stop failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements rtc.MediaStream {
  _Stream(this.name, this.events);
  final String name;
  final List<String> events;
  bool fail = false;
  @override
  Future<void> dispose() async {
    events.add('$name.dispose');
    if (fail) throw StateError('Synthetic native stream-disposal failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalTrack implements lk.LocalAudioTrack {
  _LocalTrack(this.mediaStreamTrack, this.mediaStream);
  @override
  rtc.MediaStreamTrack mediaStreamTrack;
  @override
  rtc.MediaStream mediaStream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Publication implements lk.LocalTrackPublication<lk.LocalAudioTrack> {
  _Publication(this.track);
  @override
  final lk.LocalAudioTrack track;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Participant implements lk.LocalParticipant {
  final audio = <lk.LocalTrackPublication<lk.LocalAudioTrack>>[];
  @override
  List<lk.LocalTrackPublication<lk.LocalAudioTrack>>
  get audioTrackPublications => audio;
  @override
  List<lk.LocalTrackPublication<lk.LocalVideoTrack>>
  get videoTrackPublications => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Peer implements rtc.RTCPeerConnection {
  _Peer(this.name, this.events);
  final String name;
  final List<String> events;
  bool fail = false;
  @override
  Future<void> close() async {
    events.add('$name.close');
    if (fail) throw StateError('Synthetic native peer-close failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements sdk.Transport {
  _Transport(this.pc);
  @override
  final rtc.RTCPeerConnection pc;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements sdk.Engine {
  @override
  sdk.Transport? publisher;
  @override
  sdk.Transport? subscriber;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements lk.Room {
  _Room(this.calls);
  final List<String> calls;
  @override
  final engine = _Engine();
  @override
  lk.LocalParticipant? localParticipant = _Participant();
  bool failDisconnect = false;
  @override
  Future<void> disconnect() async {
    calls.add('room.disconnect');
    if (failDisconnect) throw StateError('Synthetic room disconnect failure');
  }

  @override
  Future<bool> dispose() async {
    calls.add('room.dispose');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'adapter directly stops native handles once, not SDK track disposer',
    () async {
      final events = <String>[];
      final room = _Room(events);
      final track = _LocalTrack(_Track('mic', events), _Stream('mic', events));
      (room.localParticipant! as _Participant).audio.add(_Publication(track));
      final connection = NativeCallConnection(room: room);
      await connection.stopCapture();
      await connection.stopCapture();
      expect(events, ['mic.stop', 'mic.dispose']);
    },
  );
  test(
    'adapter propagates capture stop failure and still disposes other captures',
    () async {
      final events = <String>[];
      final room = _Room(events);
      final failed = _Track('first', events)..fail = true;
      final second = _Track('second', events);
      (room.localParticipant! as _Participant).audio.addAll([
        _Publication(_LocalTrack(failed, _Stream('first', events))),
        _Publication(_LocalTrack(second, _Stream('second', events))),
      ]);
      final connection = NativeCallConnection(room: room);
      await expectLater(connection.stopCapture(), throwsStateError);
      await connection.dispose();
      expect(events, [
        'first.stop',
        'first.dispose',
        'second.stop',
        'second.dispose',
        'room.dispose',
      ]);
      failed.fail = false;
      events.clear();
      await connection.stopCapture();
      expect(events, ['first.stop', 'first.dispose']);
    },
  );
  test('adapter propagates native stream disposal failure', () async {
    final events = <String>[];
    final room = _Room(events);
    final stream = _Stream('mic', events)..fail = true;
    (room.localParticipant! as _Participant).audio.add(
      _Publication(_LocalTrack(_Track('mic', events), stream)),
    );
    await expectLater(
      NativeCallConnection(room: room).stopCapture(),
      throwsStateError,
    );
    expect(events, ['mic.stop', 'mic.dispose']);
  });
  test('restart of same SDK track cannot inherit earlier native stop acknowledgement', () async {
    final events = <String>[];
    final room = _Room(events);
    final track = _LocalTrack(_Track('old', events), _Stream('old', events));
    (room.localParticipant! as _Participant).audio.add(_Publication(track));
    final connection = NativeCallConnection(room: room);
    await connection.stopCapture();
    track.mediaStreamTrack = _Track('new', events);
    track.mediaStream = _Stream('new', events);
    await connection.stopCapture();
    expect(events, ['old.stop', 'old.dispose', 'new.stop', 'new.dispose']);
  });
  test('late SDK handle replacement while stopping keeps each native pair together', () async {
    final events = <String>[];
    final room = _Room(events);
    final pending = Completer<void>();
    final track = _LocalTrack(
      _Track('old', events)..wait = pending.future,
      _Stream('old', events),
    );
    (room.localParticipant! as _Participant).audio.add(_Publication(track));
    final connection = NativeCallConnection(room: room);
    final stopping = connection.stopCapture();
    await Future<void>.delayed(Duration.zero);
    track.mediaStreamTrack = _Track('new', events);
    track.mediaStream = _Stream('new', events);
    pending.complete();
    await stopping;
    await connection.stopCapture();
    expect(events, ['old.stop', 'old.dispose', 'new.stop', 'new.dispose']);
  });
  test(
    'peer closes are direct, once per native handle, before room disposal',
    () async {
      final events = <String>[];
      final room = _Room(events);
      room.engine.publisher = _Transport(_Peer('publisher', events));
      room.engine.subscriber = _Transport(_Peer('subscriber', events));
      final connection = NativeCallConnection(room: room);
      await connection.disconnect();
      await connection.disconnect();
      expect(events, [
        'publisher.close',
        'subscriber.close',
        'room.disconnect',
        'room.disconnect',
      ]);
    },
  );
  test('failed native peer close propagates despite successful SDK disconnect and disposal', () async {
    final events = <String>[];
    final room = _Room(events);
    final failed = _Peer('publisher', events)..fail = true;
    room.engine.publisher = _Transport(failed);
    room.engine.subscriber = _Transport(_Peer('subscriber', events));
    final connection = NativeCallConnection(room: room);
    await expectLater(connection.disconnect(), throwsStateError);
    await connection.dispose();
    expect(events, [
      'publisher.close',
      'subscriber.close',
      'room.disconnect',
      'room.dispose',
    ]);
    failed.fail = false;
    events.clear();
    await connection.disconnect();
    expect(events, ['publisher.close', 'room.disconnect']);
  });
  test(
    'SDK disconnect failure still propagates after acknowledged peer close',
    () async {
      final events = <String>[];
      final room = _Room(events)..failDisconnect = true;
      room.engine.publisher = _Transport(_Peer('publisher', events));
      await expectLater(
        NativeCallConnection(room: room).disconnect(),
        throwsStateError,
      );
      expect(events, ['publisher.close', 'room.disconnect']);
    },
  );

  group('actual Dart plugin channel path, not physical hardware', () {
    const channel = MethodChannel('FlutterWebRTC.Method');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final operations = <String>[];
    String? failing;
    setUp(() {
      operations.clear();
      failing = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        operations.add(call.method);
        if (call.method == failing)
          throw PlatformException(code: 'synthetic-native-failure');
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC/peerConnectionEventsynthetic-peer'),
        (_) async => null,
      );
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    lk.LocalAudioTrack actualTrack() => lk.LocalAudioTrack(
      lk.TrackSource.microphone,
      platform.MediaStreamNative('synthetic-stream', 'local'),
      platform.MediaStreamTrackNative(
        'synthetic-track',
        'fixture',
        'audio',
        true,
        'local',
      ),
      const lk.AudioCaptureOptions(),
    );
    test('negative control: SDK dispose resolves despite real plugin track-stop error', () async {
      failing = 'trackDispose';
      final track = actualTrack();
      expect(await track.dispose(), isTrue);
      expect(operations, contains('trackDispose'));
    });
    for (final method in ['trackDispose', 'streamDispose']) {
      test(
        'adapter propagates platform $method error instead of SDK false success',
        () async {
          failing = method;
          final room = _Room([]);
          (room.localParticipant! as _Participant).audio.add(
            _Publication(actualTrack()),
          );
          final connection = NativeCallConnection(room: room);
          await expectLater(
            connection.stopCapture(),
            throwsA(isA<PlatformException>()),
          );
          await connection.dispose();
          expect(operations, containsAll(['trackDispose', 'streamDispose']));
        },
      );
    }
    test('adapter propagates actual plugin peer-close error', () async {
      failing = 'peerConnectionClose';
      final room = _Room([]);
      final peer = platform.RTCPeerConnectionNative('synthetic-peer', {});
      room.engine.publisher = _Transport(peer);
      final connection = NativeCallConnection(room: room);
      await expectLater(
        connection.disconnect(),
        throwsA(
          isA<String>().having(
            (e) => e,
            'message',
            contains('Unable to RTCPeerConnection::close'),
          ),
        ),
      );
      expect(operations, contains('peerConnectionClose'));
      failing = null;
      await peer.dispose();
    });
    test(
      'acknowledged actual plugin capture handles are not stopped twice',
      () async {
        final room = _Room([]);
        (room.localParticipant! as _Participant).audio.add(
          _Publication(actualTrack()),
        );
        final connection = NativeCallConnection(room: room);
        await connection.stopCapture();
        await connection.stopCapture();
        expect(operations.where((e) => e == 'trackDispose').length, 1);
        expect(operations.where((e) => e == 'streamDispose').length, 1);
      },
    );
  });
}

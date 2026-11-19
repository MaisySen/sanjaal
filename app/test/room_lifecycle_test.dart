// Fake token/native operations around the production lifecycle runner.
// This is not real LiveKit audio, an iOS device, or background-call proof.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/room_lifecycle.dart';

void main() {
  for (final stage in ['before', 'token', 'connect', 'microphone', 'never']) {
    test('room setup rechecks ownership after $stage', () async {
      var active = stage != 'before';
      final steps = <String>[];
      Future<void> step(String name) async {
        steps.add(name);
        if (name == stage) active = false;
      }
      final connected = await connectRoomWhileActive(
        isActive: () => active,
        requestToken: () => step('token'),
        connect: () => step('connect'),
        prepareMicrophone: () => step('microphone'),
      );
      final expected = <String>[];
      if (stage != 'before') {
        for (final name in ['token', 'connect', 'microphone']) {
          expected.add(name);
          if (name == stage) break;
        }
      }
      expect(steps, expected);
      expect(connected, stage == 'never');
    });
  }

  test('closing during delayed token never opens a native connection', () async {
    var active = true;
    final token = Completer<void>();
    final steps = <String>[];
    final joining = connectRoomWhileActive(
      isActive: () => active,
      requestToken: () => token.future,
      connect: () async => steps.add('connect'),
      prepareMicrophone: () async => steps.add('microphone'),
    );
    active = false;
    token.complete();
    expect(await joining, false);
    expect(steps, isEmpty);
  });

  test('closing during connect stops capture, waits, disconnects then disposes', () async {
    var active = true;
    final connect = Completer<void>();
    final entered = Completer<void>();
    final steps = <String>[];
    final joining = connectRoomWhileActive(
      isActive: () => active,
      requestToken: () async {},
      connect: () async { entered.complete(); await connect.future; steps.add('connected'); },
      prepareMicrophone: () async => steps.add('capture'),
    );
    await entered.future;
    active = false;
    final released = releaseRoomAfterJoin(
      joining: joining,
      closeMicrophone: () async => steps.add('stop'),
      disconnect: () async => steps.add('disconnect'),
      disposeMicrophone: () => steps.add('dispose mic'),
      disposeRoom: () async => steps.add('dispose room'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(steps, ['stop', 'disconnect']);
    connect.complete();
    await released;
    expect(await joining, false);
    expect(steps, ['stop', 'disconnect', 'connected', 'disconnect', 'dispose mic', 'dispose room']);
  });

  test('native cleanup failures cannot skip disposal', () async {
    final steps = <String>[];
    await releaseRoomAfterJoin(
      joining: Future.value(),
      closeMicrophone: () async { steps.add('stop'); throw StateError('fake stop'); },
      disconnect: () async { steps.add('disconnect'); throw StateError('fake disconnect'); },
      disposeMicrophone: () => steps.add('dispose mic'),
      disposeRoom: () async => steps.add('dispose room'),
    );
    expect(steps, ['stop', 'disconnect', 'disconnect', 'dispose mic', 'dispose room']);
  });

  test('failed token does not open native media and still permits cleanup', () async {
    final steps = <String>[];
    final joining = connectRoomWhileActive(
      isActive: () => true,
      requestToken: () async => throw StateError('fake token failure'),
      connect: () async => steps.add('connect'),
      prepareMicrophone: () async => steps.add('capture'),
    );
    // Observe the failure before cleanup also awaits it.
    await expectLater(joining, throwsStateError);
    await releaseRoomAfterJoin(
      joining: joining,
      closeMicrophone: () async => steps.add('stop'),
      disconnect: () async => steps.add('disconnect'),
      disposeMicrophone: () => steps.add('dispose mic'),
      disposeRoom: () async => steps.add('dispose room'),
    );
    expect(steps, ['stop', 'disconnect', 'disconnect', 'dispose mic', 'dispose room']);
  });
  for (final stopFails in [false, true]) {
    test('failed room setup disconnects even when mic stop fails=$stopFails', () async {
      final steps = <String>[];
      await stopRoomAfterJoinFailure(
        stopMicrophone: () async {
          steps.add('stop');
          if (stopFails) throw StateError('fake native failure');
        },
        disconnect: () async => steps.add('disconnect'),
      );
      expect(steps, ['stop', 'disconnect']);
    });
  }

}

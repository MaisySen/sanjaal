// Fake microphone adapter only. Not LiveKit, audio, recording or device proof.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/room_microphone.dart';

void main() {
  late RoomMicrophone mic;
  late List<bool> calls;
  Completer<void>? wait;
  setUp(() {
    calls = [];
    wait = null;
    mic = RoomMicrophone((on) async {
      calls.add(on);
      await wait?.future;
    });
  });
  tearDown(() => mic.dispose());
  Future<bool> grant({
    String? sender = 'host',
    String? host = 'host',
    String? me = 'listener',
    Object? target = 'listener',
    Object? allow = true,
  }) => mic.hostPacket(
    sender: sender,
    host: host,
    me: me,
    target: target,
    allow: allow,
  );
  test(
    'verified host grant offers stage without enabling microphone',
    () async {
      expect(await grant(), isTrue);
      expect(mic.speaker, isTrue);
      expect(mic.muted, isTrue);
      expect(calls, isEmpty);
    },
  );
  for (final bad in ['outsider', '', 'listener'])
    test('rejects nonhost SFU identity $bad', () async {
      expect(await grant(sender: bad), isFalse);
      expect(mic.speaker, isFalse);
      expect(calls, isEmpty);
    });
  test('missing identities fail closed', () async {
    expect(await grant(host: null), isFalse);
    expect(await grant(me: null), isFalse);
    expect(await grant(sender: null), isFalse);
    expect(calls, isEmpty);
  });
  test('wrong target and nonboolean allow fail closed', () async {
    expect(await grant(target: 'other'), isFalse);
    expect(await grant(allow: 'true'), isFalse);
    expect(await grant(allow: 1), isFalse);
    expect(calls, isEmpty);
  });
  test('only explicit local unmute enables capture', () async {
    await grant();
    await mic.toggle();
    expect(calls, [true]);
    expect(mic.muted, isFalse);
    await mic.toggle();
    expect(calls, [true, false]);
    expect(mic.muted, isTrue);
  });
  test('duplicate remote grant preserves manual mute', () async {
    await grant();
    await mic.toggle();
    await mic.toggle();
    await grant();
    expect(calls, [true, false]);
    expect(mic.muted, isTrue);
  });
  test('duplicate grant does not toggle active local choice', () async {
    await grant();
    await mic.toggle();
    await grant();
    expect(calls, [true]);
    expect(mic.muted, isFalse);
  });
  test('host revoke disables mic and removes speak control', () async {
    await grant();
    await mic.toggle();
    await grant(allow: false);
    expect(calls, [true, false]);
    expect(mic.speaker, isFalse);
    await mic.toggle();
    expect(calls, [true, false]);
  });
  test('revocation follows inflight unmute with final disable', () async {
    await grant();
    wait = Completer<void>();
    final enabling = mic.toggle();
    await Future<void>.delayed(Duration.zero);
    final revoke = mic.revoke();
    expect(mic.speaker, isFalse);
    expect(mic.muted, isTrue);
    wait!.complete();
    await enabling;
    await revoke;
    expect(calls, [true, false]);
    expect(mic.muted, isTrue);
  });
  test('leave follows inflight enable with final disable', () async {
    await grant();
    wait = Completer<void>();
    final enabling = mic.toggle();
    await Future<void>.delayed(Duration.zero);
    final close = mic.close();
    wait!.complete();
    await enabling;
    await close;
    expect(calls, [true, false]);
    expect(await grant(), isFalse);
    await mic.toggle();
    expect(calls, [true, false]);
  });
  test('queued unmute is discarded when revoked before native call', () async {
    await grant();
    final enabling = mic.toggle();
    final revoke = mic.revoke();
    await enabling;
    await revoke;
    expect(calls, [false]);
  });
  test('busy button cannot double-toggle', () async {
    await grant();
    wait = Completer<void>();
    final enabling = mic.toggle();
    await mic.toggle();
    wait!.complete();
    await enabling;
    expect(calls, [true]);
  });
  test('host start explicitly enables once', () async {
    await mic.startHost();
    expect(calls, [true]);
    expect(mic.speaker, isTrue);
    expect(mic.muted, isFalse);
  });
  test('failed native enable retains muted state and releases busy', () async {
    mic.dispose();
    mic = RoomMicrophone((_) async => throw StateError('permission denied'));
    await grant();
    await expectLater(mic.toggle(), throwsStateError);
    expect(mic.muted, isTrue);
    expect(mic.busy, isFalse);
  });
  test(
    'failed revoke records uncertain stop and blocks later enables',
    () async {
      mic.dispose();
      mic = RoomMicrophone((on) async {
        if (!on) throw StateError('native stop failed');
        calls.add(on);
      });
      await grant();
      await mic.toggle();
      await expectLater(mic.revoke(), throwsStateError);
      expect(mic.stopUnconfirmed, isTrue);
      await grant();
      await mic.toggle();
      expect(calls, [true]);
    },
  );
  test('failed enable attempts native off but remains terminal', () async {
    mic.dispose();var fail=true;
    mic=RoomMicrophone((on)async{calls.add(on);if(on && fail){fail=false;throw StateError('enable acknowledgement lost');}});
    await grant();await expectLater(mic.toggle(),throwsStateError);
    expect(calls,[true,false]);expect(mic.muted,isTrue);expect(mic.stopUnconfirmed,isTrue);expect(mic.busy,isFalse);
    await mic.toggle();expect(calls,[true,false]);expect(mic.muted,isTrue);
  });
  test('failed enable and failed cleanup block host grants and local retry', () async {
    mic.dispose();mic=RoomMicrophone((on)async{calls.add(on);throw StateError('native result unknown');});
    await grant();await expectLater(mic.toggle(),throwsStateError);
    expect(calls,[true,false]);expect(mic.stopUnconfirmed,isTrue);expect(mic.busy,isFalse);
    await grant();await mic.toggle();expect(calls,[true,false]);
  });
  test('failed manual mute attempts a second stop and marks uncertainty', () async {
    mic.dispose();mic=RoomMicrophone((on)async{calls.add(on);if(!on)throw StateError('stop result unknown');});
    await grant();await mic.toggle();await expectLater(mic.toggle(),throwsStateError);
    expect(calls,[true,false,false]);expect(mic.stopUnconfirmed,isTrue);
    await mic.toggle();expect(calls,[true,false,false]);
  });
  test('cleanup stays busy and revoke waits behind failed-enable stop', () async {
    mic.dispose();final stop=Completer<void>();var stops=0;
    mic=RoomMicrophone((on)async{calls.add(on);if(on)throw StateError('enable result unknown');if(++stops==1)await stop.future;});
    await grant();final enabling=expectLater(mic.toggle(),throwsStateError);
    await Future<void>.delayed(Duration.zero);expect(calls,[true,false]);expect(mic.busy,isTrue);
    final revoked=mic.revoke();await mic.toggle();expect(calls,[true,false]);
    stop.complete();await enabling;await revoked;expect(calls,[true,false,false]);expect(mic.speaker,isFalse);expect(mic.muted,isTrue);expect(mic.stopUnconfirmed,isTrue);
  });
  test('a failed mute remains uncertain even when cleanup acknowledges off', () async {
    mic.dispose();var firstStop=true;
    mic=RoomMicrophone((on)async{calls.add(on);if(!on && firstStop){firstStop=false;throw StateError('stop acknowledgement lost');}});
    await grant();await mic.toggle();await expectLater(mic.toggle(),throwsStateError);
    expect(calls,[true,false,false]);expect(mic.muted,isTrue);expect(mic.stopUnconfirmed,isTrue);
  });

  test('successful cleanup cannot permit retry after failed enable', () async {
    mic.dispose();var first=true;
    mic=RoomMicrophone((on)async{calls.add(on);if(on && first){first=false;throw StateError('synthetic failed enable');}});
    await grant();await expectLater(mic.toggle(),throwsStateError);
    await mic.toggle();expect(calls,[true,false]);
  });
  test('later revoke acknowledgment cannot unlock failed room capture', () async {
    mic.dispose();var first=true;
    mic=RoomMicrophone((on)async{calls.add(on);if(on && first){first=false;throw StateError('synthetic failed enable');}});
    await grant();await expectLater(mic.toggle(),throwsStateError);
    await mic.revoke();expect(mic.stopUnconfirmed,isTrue);
    expect(await grant(),isFalse);await mic.startHost();await mic.toggle();expect(calls,[true,false,false]);
  });

  test('terminal notification precedes slow cleanup and cannot unlock capture', () async {
    mic.dispose();final stop=Completer<void>();final notified=Completer<void>();final events=<String>[];
    mic=RoomMicrophone((on)async{events.add(on?'enable':'off');if(on)throw StateError('synthetic failed enable');await stop.future;},onFailure:(){expect(mic.stopUnconfirmed,isTrue);events.add('terminal');notified.complete();});
    await grant();final result=expectLater(mic.toggle(),throwsStateError);await notified.future;
    expect(mic.busy,isTrue);await mic.toggle();expect(events,['enable','terminal','off']);
    stop.complete();await result;await mic.toggle();expect(events,['enable','terminal','off']);
  });

}

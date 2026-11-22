import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_controller.dart';

import 'call_continuity_fakes.dart';

void main() {
  test(
    'native microphone and camera snapshot changes update presentation',
    () async {
      final session = CallFixtureSession(), native = FakeCallConnection();
      final call = CallController(
        session: session,
        conversationId: 'chat',
        title: 'Member',
        video: true,
        connection: native,
      );
      await settleCall();
      expect(call.muted, isFalse);
      expect(call.camOn, isTrue);
      native.microphoneEnabled = false;
      native.cameraEnabled = false;
      native.emit();
      expect(call.muted, isTrue);
      expect(call.camOn, isFalse);
      native.microphoneEnabled = true;
      native.cameraEnabled = true;
      native.emit();
      expect(call.muted, isFalse);
      expect(call.camOn, isTrue);
      expect(await call.close(), isTrue);
      call.dispose();
    },
  );
  test('call owner connects once, changes media, and releases once', () async {
    final s = CallFixtureSession(), native = FakeCallConnection();
    final call = CallController(
      session: s,
      conversationId: 'chat',
      title: 'Member',
      video: true,
      connection: native,
    );
    await settleCall();
    expect(native.events, ['connect', 'microphone:true', 'camera:true']);
    expect(call.presentation.status, 'Waiting for others to join');
    native.remoteCount = 1;
    native.emit();
    expect(call.presentation.status, 'Connected');
    await call.changeMedia(camera: false);
    expect(call.muted, isTrue);
    await call.changeMedia(camera: true);
    expect(call.camOn, isFalse);
    final first = call.close(), second = call.close();
    expect(identical(first, second), isTrue);
    expect(await first, isTrue);
    call.dispose();
    await settleCall();
    expect(native.events.where((e) => e == 'dispose').length, 1);
    expect(s.requests.where((r) => r.path.endsWith('/action')).length, 1);
  });
  test(
    'closing before setup does not request a token or start capture',
    () async {
      final s = CallFixtureSession(), native = FakeCallConnection();
      final call = CallController(
        session: s,
        conversationId: 'chat',
        title: 'Member',
        video: true,
        connection: native,
      );
      expect(await call.close(), isTrue);
      expect(s.requests, isEmpty);
      expect(native.events.where((event) => event != 'stopCapture').toList(), [
        'disconnect',
        'disconnect',
        'disconnect',
        'dispose',
      ]);
      expect(native.events.where((event) => event == 'stopCapture').length, 2);
      call.dispose();
    },
  );
  for (final retire in [false, true]) {
    test(
      'late token never starts capture after close, retired=$retire',
      () async {
        final reply = Completer<dynamic>();
        final s = CallFixtureSession()..tokenReply = reply.future;
        final native = FakeCallConnection();
        final call = CallController(
          session: s,
          conversationId: 'chat',
          title: 'Member',
          video: true,
          connection: native,
        );
        await settleCall();
        if (retire) s.replace();
        final released = call.close();
        reply.complete({
          'call_id': 'late-call',
          'url': 'wss://fixture.invalid',
          'token': 'synthetic',
        });
        expect(await released, isTrue);
        expect(
          native.events.any(
            (e) =>
                e == 'connect' ||
                e.startsWith('microphone:') ||
                e.startsWith('camera:'),
          ),
          isFalse,
        );
        expect(
          s.requests.where((r) => r.path.endsWith('/action')).length,
          retire ? 0 : 1,
        );
        call.dispose();
      },
    );
  }
  test(
    'late native connection cannot enable microphone after login replacement',
    () async {
      final connected = Completer<void>();
      final s = CallFixtureSession(),
          native = FakeCallConnection()..connectWait = connected.future;
      final call = CallController(
        session: s,
        conversationId: 'chat',
        title: 'Member',
        video: true,
        connection: native,
      );
      await settleCall();
      s.replace(owner: 'other');
      connected.complete();
      expect(await call.close(), isTrue);
      expect(
        native.events.where(
          (e) => e.startsWith('microphone:') || e.startsWith('camera:'),
        ),
        isEmpty,
      );
      expect(s.requests.where((r) => r.path.endsWith('/action')), isEmpty);
      call.dispose();
    },
  );
  test(
    'overlapping media actions do not toggle twice and cleanup waits',
    () async {
      final s = CallFixtureSession(), native = FakeCallConnection();
      final call = CallController(
        session: s,
        conversationId: 'chat',
        title: 'Member',
        video: true,
        connection: native,
      );
      await settleCall();
      final pending = Completer<void>();
      native.microphoneWait = pending.future;
      final first = call.changeMedia(camera: false);
      await call.changeMedia(camera: false);
      expect(native.events.where((e) => e == 'microphone:false').length, 1);
      final release = call.close();
      var released = false;
      unawaited(release.then((_) => released = true));
      await settleCall();
      expect(released, isFalse);
      pending.complete();
      await first;
      expect(await release, isTrue);
      call.dispose();
    },
  );
  test(
    'uncertain native cleanup is returned to the host, never called success',
    () async {
      final s = CallFixtureSession(),
          native = FakeCallConnection()..failDispose = true;
      final call = CallController(
        session: s,
        conversationId: 'chat',
        title: 'Member',
        video: false,
        connection: native,
      );
      await settleCall();
      expect(await call.close(), isFalse);
      call.dispose();
    },
  );
}

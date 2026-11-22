import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_connection.dart';
import 'package:sanjaal/call_controller.dart';

import 'call_continuity_fakes.dart';

void main() {
  test(
    'failed capture stop propagates while every other stop is attempted',
    () async {
      final attempted = <String>[];
      await expectLater(
        stopCallCaptures([
          () async {
            attempted.add('microphone');
            throw StateError('native stop failed');
          },
          () async {
            attempted.add('camera');
          },
        ]),
        throwsStateError,
      );
      expect(attempted, ['microphone', 'camera']);
    },
  );
  test('all successful direct capture stops complete normally', () async {
    var stopped = 0;
    await stopCallCaptures([
      () async {
        stopped++;
      },
      () async {
        stopped++;
      },
    ]);
    expect(stopped, 2);
  });
  test(
    'successful disposal cannot hide a failed direct capture stop',
    () async {
      final session = CallFixtureSession();
      final native = FakeCallConnection()..failStopCapture = true;
      final controller = CallController(
        session: session,
        conversationId: 'chat',
        title: 'Member',
        video: true,
        connection: native,
      );
      await settleCall();
      expect(native.cameraEnabled, isTrue);
      expect(await controller.close(), isFalse);
      expect(native.events.where((event) => event == 'stopCapture').length, 2);
      expect(native.events.last, 'dispose');
      expect(native.failDispose, isFalse);
      controller.dispose();
    },
  );
}

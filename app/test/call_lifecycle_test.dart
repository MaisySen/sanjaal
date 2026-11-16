// Cancellation ordering of the real setup runner, with fake native operations.
// This is not live audio/video or device proof.
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/call_lifecycle.dart';

void main() {
  for (final closeAfter in ['before', 'token', 'connect', 'microphone', 'camera', 'never']) {
    for (final video in [false, true]) {
      test('setup video=$video stops after $closeAfter', () async {
        var active = closeAfter != 'before';
        final steps = <String>[];
        Future<void> step(String name) async {
          steps.add(name);
          if (name == closeAfter) active = false;
        }
        final connected = await connectCallWhileActive(
          isActive: () => active,
          requestToken: () => step('token'), connect: () => step('connect'),
          microphone: () => step('microphone'), camera: () => step('camera'), video: video,
        );
        final expected = <String>[];
        if (closeAfter != 'before') {
          for (final name in ['token', 'connect', 'microphone', if (video) 'camera']) {
            expected.add(name);
            if (name == closeAfter) break;
          }
        }
        expect(steps, expected);
        expect(connected, closeAfter == 'never' || (!video && closeAfter == 'camera'));
      });
    }
  }
  test('a failed media permission does not open later capabilities', () async {
    final steps = <String>[];
    await expectLater(connectCallWhileActive(
      isActive: () => true,
      requestToken: () async => steps.add('token'),
      connect: () async => steps.add('connect'),
      microphone: () async { steps.add('microphone'); throw StateError('fixture permission denied'); },
      camera: () async => steps.add('camera'), video: true,
    ), throwsStateError);
    expect(steps, ['token', 'connect', 'microphone']);
  });
}

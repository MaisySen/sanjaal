import 'package:flutter_test/flutter_test.dart';

import '../integration_test/native_capture_barrier.dart';

void main() {
  testWidgets('runAsync captures errors instead of throwing to its caller', (
    t,
  ) async {
    final result = await t.runAsync<bool>(() async {
      throw StateError('Synthetic native handshake failure');
    });
    expect(result, isNull);
    expect(t.takeException(), isA<StateError>());
  });

  for (final outcome in [true, false, null]) {
    test(
      'capture boundary continues only after positive host acknowledgement: $outcome',
      () async {
        var continued = false;
        Future<void> journey() async {
          await nativeCaptureBarrier(
            name: 'ios_test',
            runAsync: (_) async => outcome,
            acknowledge: () async => true,
          );
          continued = true;
        }

        if (outcome == true) {
          await journey();
          expect(continued, isTrue);
        } else {
          await expectLater(journey(), throwsStateError);
          expect(continued, isFalse);
        }
      },
    );
  }

  testWidgets(
    'real runAsync cannot swallow a boundary failure and advance UI',
    (t) async {
      var continued = false;
      await expectLater(() async {
        await nativeCaptureBarrier(
          name: 'ios_test',
          runAsync: (body) => t.runAsync(body),
          acknowledge: () async =>
              throw StateError('Synthetic filesystem failure'),
        );
        continued = true;
      }(), throwsStateError);
      expect(continued, isFalse);
      expect(t.takeException(), isA<StateError>());
    },
  );
}

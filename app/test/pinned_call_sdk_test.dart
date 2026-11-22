import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reviewed native call bridge requires exact SDK and plugin versions',
    () {
      final spec = File('pubspec.yaml').readAsStringSync();
      final lock = File('pubspec.lock').readAsStringSync();
      for (final entry in {
        'livekit_client': '2.13.2',
        'flutter_webrtc': '1.6.3',
      }.entries) {
        expect(
          RegExp(
            '^  ${entry.key}: ${RegExp.escape(entry.value)}\$',
            multiLine: true,
          ).hasMatch(spec),
          isTrue,
          reason: 'An SDK update needs a new native cleanup bridge review, not a range upgrade.',
        );
        final block = RegExp(
          '^  ${entry.key}:\\n([\\s\\S]*?)(?=^  \\w)',
          multiLine: true,
        ).firstMatch(lock)?.group(1);
        expect(block, contains('version: "${entry.value}"'));
      }
    },
  );
}

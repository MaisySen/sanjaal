import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retained SDK matches recorded upstream except exact reviewed native patch files', () {
    final root='vendor/livekit_client/';
    final data=jsonDecode(File('${root}UPSTREAM_SOURCE.json').readAsStringSync()) as Map;
    final hashes=(data['upstream_sha256'] as Map).cast<String,String>();
    const changed={
      'android/src/main/kotlin/io/livekit/plugin/LKAudioSwitchManager.kt',
      'android/src/main/kotlin/io/livekit/plugin/LiveKitPlugin.kt',
    };
    for(final entry in hashes.entries) {
      final bytes=File('$root${entry.key}').readAsBytesSync();
      if(!changed.contains(entry.key)) {
        expect(sha256.convert(bytes).toString(),entry.value,reason:entry.key);
      }
    }
    expect(hashes.length,greaterThan(200));
    expect(File('${root}LICENSE').readAsStringSync(),contains('Apache License'));
  });
  test(
    'reviewed native call bridge requires exact SDK and plugin versions',
    () {
      final spec = File('pubspec.yaml').readAsStringSync();
      final lock = File('pubspec.lock').readAsStringSync();
      expect(spec,contains('path: vendor/livekit_client'));
      final manager=File('vendor/livekit_client/android/src/main/kotlin/io/livekit/plugin/LKAudioSwitchManager.kt').readAsStringSync();
      expect(manager,contains('fun externalTelecomOwnership'));
      expect(manager,contains('if (externalGate.owned) return@post'));
      expect(File('vendor/livekit_client/UPSTREAM_SOURCE.json').existsSync(),true);
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

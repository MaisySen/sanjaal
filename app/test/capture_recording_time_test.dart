import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/capture_recording_time.dart';

void main() {
  test(
    'recording starts with zero and counts actual elapsed time between ticks',
    () {
      var now = const Duration(seconds: 50);
      final time = CaptureRecordingTime(() => now);
      expect(time.elapsed, Duration.zero);
      time.begin();
      expect(time.elapsed, Duration.zero);
      now += const Duration(milliseconds: 2350);
      expect(time.elapsed, const Duration(milliseconds: 2350));
    },
  );

  test('pause excludes waiting and resume does not reset the recording', () {
    var now = Duration.zero;
    final time = CaptureRecordingTime(() => now)..begin();
    now += const Duration(milliseconds: 1450);
    time.pause();
    expect(time.running, isFalse);
    now += const Duration(minutes: 10);
    expect(time.elapsed, const Duration(milliseconds: 1450));
    time.resume();
    expect(time.running, isTrue);
    now += const Duration(milliseconds: 650);
    expect(time.elapsed, const Duration(milliseconds: 2100));
  });

  test(
    'many short pauses cannot reset fractions and extend the recording limit',
    () {
      var now = Duration.zero;
      final time = CaptureRecordingTime(() => now)..begin();
      for (var i = 0; i < 100; i++) {
        now += const Duration(milliseconds: 35);
        time.pause();
        now += const Duration(seconds: 3);
        time.resume();
      }
      expect(time.elapsed, const Duration(milliseconds: 3500));
    },
  );

  test('repeated pause or resume is idempotent', () {
    var now = Duration.zero;
    final time = CaptureRecordingTime(() => now)..begin();
    now += const Duration(milliseconds: 450);
    time.pause();
    now += const Duration(seconds: 30);
    time.pause();
    expect(time.elapsed, const Duration(milliseconds: 450));
    time.resume();
    now += const Duration(milliseconds: 550);
    time.resume();
    expect(time.elapsed, const Duration(seconds: 1));
  });

  test('a new capture resets prior accumulated time', () {
    var now = Duration.zero;
    final time = CaptureRecordingTime(() => now)..begin();
    now += const Duration(seconds: 12);
    time.pause();
    time.begin();
    expect(time.elapsed, Duration.zero);
    now += const Duration(seconds: 2);
    expect(time.elapsed, const Duration(seconds: 2));
  });

  test('an invalid injected clock cannot make displayed time go backward', () {
    var now = const Duration(seconds: 50);
    final time = CaptureRecordingTime(() => now)..begin();
    now += const Duration(seconds: 3);
    expect(time.elapsed, const Duration(seconds: 3));
    now -= const Duration(seconds: 2);
    expect(time.elapsed, const Duration(seconds: 3));
  });
}
